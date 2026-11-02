#!/usr/bin/env bash
# 拉取/切换上游源码（manifest 驱动，见 spec §3）
#   ./scripts/sync.sh                      # 默认 manifest/default.xml
#   ./scripts/sync.sh -m qemu-linux61.xml  # 指定变体
#   FULL_SYNC=1 ./scripts/sync.sh          # 完整历史（默认 shallow，见 spec §3.2）
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

MANIFEST="default.xml"
while getopts ":m:h" opt; do
    case "$opt" in
        m) MANIFEST="$OPTARG" ;;
        h|*) grep '^#' "$0" | head -n 6; exit 0 ;;
    esac
done

MANIFEST_FILE="$SDK_ROOT/manifest/$MANIFEST"
[ -f "$MANIFEST_FILE" ] || sdk_die "manifest 不存在: $MANIFEST_FILE"

# repo 工具：优先 SDK 内置，其次系统 PATH
if [ -x "$SDK_ROOT/tools/repo/repo" ]; then
    REPO="$SDK_ROOT/tools/repo/repo"
else
    REPO="$(command -v repo)" || sdk_die "未找到 repo，请先执行 scripts/setup.sh"
fi

# manifest 仓库地址：默认指向 SDK 仓库本身（manifest/ 目录在库内）。
# 如需远端 manifest 仓库（如 CI 只拉 manifest），用 REPO_MANIFEST_URL 覆盖。
MANIFEST_URL="${REPO_MANIFEST_URL:-file://$SDK_ROOT}"
MANIFEST_BRANCH="${REPO_MANIFEST_BRANCH:-$(git -C "$SDK_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)}"
# repo 的 -m 相对于 manifest 仓库根，SDK 内 manifest 位于 manifest/ 子目录
MANIFEST_PATH="manifest/$MANIFEST"

SYNC_ARGS=( -c --no-clone-bundle -j"$(nproc)" )
if [ "${FULL_SYNC:-0}" != "1" ]; then
    # 首次浅克隆（见 spec §3.2）；调试需要完整历史时 FULL_SYNC=1
    SYNC_ARGS+=( --depth=1 --no-tags )
    INIT_ARGS=( --depth=1 )
else
    INIT_ARGS=()
fi

sdk_log "repo init: $MANIFEST_URL (branch=$MANIFEST_BRANCH, manifest=$MANIFEST_PATH)"
"$REPO" init -u "$MANIFEST_URL" -b "$MANIFEST_BRANCH" -m "$MANIFEST_PATH" "${INIT_ARGS[@]}"

sdk_log "repo sync ..."
"$REPO" sync "${SYNC_ARGS[@]}"

sdk_log "源码同步完成 → $SDK_ROOT/source/"
