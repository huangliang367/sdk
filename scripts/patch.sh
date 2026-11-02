#!/usr/bin/env bash
# 补丁管理（见 spec §4）
#   ./scripts/patch.sh apply            # 全部组件（common → 平台 顺序）
#   ./scripts/patch.sh apply linux      # 仅指定组件，可多个
#   ./scripts/patch.sh unapply linux    # 撤销（git reset 回基线）
#   ./scripts/patch.sh check            # 状态检查（上游版本 / 已打 patch / 工作树）
#
# 已打补丁记录在 <repo>/.patched，apply 幂等。
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

CMD="${1:-}"; shift || true
case "$CMD" in
    apply|unapply|check) ;;
    *) sdk_die "用法: patch.sh apply|unapply|check [组件...]"; ;;
esac

if [ "$#" -gt 0 ]; then
    COMPONENTS="$*"
else
    COMPONENTS="$(sdk_components)"
fi

# 需要 SOC_NAME 定位平台补丁层；未 lunch 时按 qemu-virt 缺省
if [ -z "${SOC_NAME:-}" ]; then
    if [ -n "${SDK_PRODUCT:-}" ] || [ -n "${PRODUCT:-}" ]; then
        sdk_ensure_product
    else
        sdk_warn "未 lunch，平台补丁层按缺省 SOC_NAME=qemu-virt 处理"
        SOC_NAME=qemu-virt
    fi
fi

# 每层目录中的补丁，按文件名（编号）排序
patches_in_layer() { # <layer 相对路径> → 排序后的 patch 文件列表
    local dir="$SDK_ROOT/$1"
    if [ -d "$dir" ]; then
        find "$dir" -maxdepth 1 -name '*.patch' | sort
    fi
}

series_of() { # <component> → 该组件完整补丁序列（common → 平台）
    local component="$1" layer
    while read -r layer; do
        patches_in_layer "$layer"
    done < <(sdk_patch_layers "$component")
}

apply_one() { # <repo 绝对路径> <patch 文件>
    local repo="$1" p="$2"
    if git -C "$repo" am --3way "$p" >/dev/null 2>&1; then
        echo "am:$p" >> "$repo/.patched"
        sdk_log "  [APPLY ] $(basename "$p")"
        return 0
    fi
    git -C "$repo" am --abort >/dev/null 2>&1 || true

    # 回退路径：非 git 邮箱格式的补丁用 patch -p1（见 spec §4.2）
    sdk_warn "  git am 失败，回退 patch -p1: $(basename "$p")"
    if (cd "$repo" && patch -p1 --dry-run -f < "$p" >/dev/null 2>&1); then
        (cd "$repo" && patch -p1 -f < "$p" >/dev/null)
        echo "patch:$p" >> "$repo/.patched"
        sdk_warn "  [PATCH ] $(basename "$p")（未形成 commit，unapply 时将用 patch -R）"
        return 0
    fi
    sdk_err "补丁应用失败: $p"
    sdk_err "请进入 $repo 手动解决，或调整后重试"
    return 1
}

cmd_apply() {
    local c repo p
    for c in $COMPONENTS; do
        repo_rel="$(sdk_component_repo "$c")" || sdk_die "未知组件: $c"
        repo="$SDK_ROOT/$repo_rel"
        [ -d "$repo/.git" ] || sdk_die "组件 $c 源码不存在（$repo_rel），先执行 scripts/sync.sh"
        if [ -f "$repo/.patched" ]; then
            sdk_log "[$c] 已打过补丁，跳过（删除 $repo_rel/.patched 可强制重打）"
            continue
        fi
        sdk_log "[$c] 应用补丁 → $repo_rel"
        : > "$repo/.patched"
        for p in $(series_of "$c"); do
            apply_one "$repo" "$p"
        done
    done
}

cmd_unapply() {
    local c repo repo_rel n
    for c in $COMPONENTS; do
        repo_rel="$(sdk_component_repo "$c")" || sdk_die "未知组件: $c"
        repo="$SDK_ROOT/$repo_rel"
        [ -f "$repo/.patched" ] || { sdk_log "[$c] 无补丁记录，跳过"; continue; }

        # 工作树必须干净（忽略 .patched 标记文件自身），避免误删未入库的修改
        if [ -n "$(git -C "$repo" status --porcelain | grep -v '^?? \.patched$')" ]; then
            sdk_err "[$c] 工作树不干净，拒绝 unapply。请先提交/导出 patch 或手工处理"
            exit 1
        fi

        # patch -p1 方式应用的不构成 commit，需要反向补丁撤销（逆序收集）
        local rev_patches=()
        if grep -q '^patch:' "$repo/.patched" 2>/dev/null; then
            mapfile -t rev_patches < <(grep '^patch:' "$repo/.patched" | cut -d: -f2- | tac)
        fi

        n=$(grep -c '^am:' "$repo/.patched" || true)
        if [ "$n" -gt 0 ]; then
            # 补丁 commit 必须是当前 HEAD 之上的最近 n 个
            if ! git -C "$repo" rev-parse -q --verify "HEAD~$n" >/dev/null; then
                sdk_err "[$c] HEAD~$n 不存在：补丁 commit 可能已被改写，无法自动撤销"
                sdk_err "请手工处理，确认后删除 $repo_rel/.patched"
                exit 1
            fi
            sdk_log "[$c] git reset --hard HEAD~$n"
            git -C "$repo" reset --hard "HEAD~$n" >/dev/null
        fi
        # 先删标记，避免后续失败留下"已 reset 但标记还在"的卡死状态
        rm -f "$repo/.patched"
        local p
        for p in "${rev_patches[@]}"; do
            sdk_log "[$c] patch -R $(basename "$p")"
            (cd "$repo" && patch -p1 -R -f < "$p" >/dev/null) || {
                sdk_err "[$c] 反向补丁失败: $p，请手工检查 $repo_rel"
                exit 1
            }
        done
        sdk_log "[$c] 补丁已撤销"
    done
}

cmd_check() {
    local c repo repo_rel dirty
    printf "%-8s %-40s %-14s %s\n" "组件" "仓库 HEAD" "工作树" "已打补丁"
    for c in $COMPONENTS; do
        repo_rel="$(sdk_component_repo "$c")" || continue
        repo="$SDK_ROOT/$repo_rel"
        if [ ! -d "$repo/.git" ]; then
            printf "%-8s %s\n" "$c" "源码缺失（$repo_rel）"
            continue
        fi
        local head dirty_state applied
        head="$(git -C "$repo" describe --tags --always 2>/dev/null) ($(git -C "$repo" rev-parse --short HEAD))"
        if [ -n "$(git -C "$repo" status --porcelain | grep -v '^?? \.patched$')" ]; then
            dirty_state="脏（待导出 patch!）"
        else
            dirty_state="干净"
        fi
        if [ -f "$repo/.patched" ]; then
            applied="$(grep -c . "$repo/.patched") 个"
        else
            applied="无"
        fi
        printf "%-8s %-40s %-14s %s\n" "$c" "$head" "$dirty_state" "$applied"
        if [ -f "$repo/.patched" ]; then
            sed 's/^/         /' "$repo/.patched"
        fi
    done
}

case "$CMD" in
    apply)   cmd_apply ;;
    unapply) cmd_unapply ;;
    check)   cmd_check ;;
esac
