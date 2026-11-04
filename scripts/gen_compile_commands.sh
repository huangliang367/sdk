#!/usr/bin/env bash
# 为 source/ 下各仓库生成 compile_commands.json，供 clangd/IDE 索引
#
# 生成方式（各仓库原生机制，能解析 .cmd 的都不重编）：
#   linux     内核原生目标 make compile_commands.json（扫描 .cmd）
#   u-boot    仓库自带 scripts/gen_compile_commands.py（扫描 .cmd）
#   optee     仓库自带 scripts/gen_compile_commands.py（扫描 out/ 下 .cmd）
#   atf       无原生工具，bear 拦截一次强制增量编译（make -B；有 ccache 时很快）
#   scp       SDK 尚未接线 SCP 构建，默认跳过；接入后设 SCP_TARGET/SCP_PLATFORM 再生成
#   buildroot 上游不支持导出编译数据库，跳过
#
# 前置条件：目标仓库至少完整构建过一次（.cmd 文件是生成的数据源）
# 用法：
#   source scripts/envsetup.sh && lunch qemu_debug
#   ./scripts/gen_compile_commands.sh                # 全部组件
#   ./scripts/gen_compile_commands.sh linux u-boot   # 指定组件
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log gen_compile_commands
sdk_use_toolchain
sdk_timer_start

ALL_COMPONENTS=(linux u-boot optee atf scp)
REQUESTED=("$@")
if [ "${#REQUESTED[@]}" -eq 0 ]; then
    REQUESTED=("${ALL_COMPONENTS[@]}")
fi

# 统计条目数：空库（[]）说明该仓库没构建过，需要警告
cc_count() { # <json>
    python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' "$1" 2>/dev/null || echo 0
}

check_result() { # <组件> <json 路径>
    local n
    n=$(cc_count "$2")
    if [ "$n" -eq 0 ]; then
        sdk_warn "$1: $2 为空（该仓库可能未构建过，先跑对应 build_*.sh）"
    else
        sdk_log "$1: $2（$n 条）"
    fi
}

gen_linux() {
    local src="$SDK_ROOT/source/linux"
    sdk_require_source source/linux
    if [ ! -f "$src/.config" ]; then
        sdk_warn "linux: 缺少 .config（先跑 build_kernel.sh），跳过"
        return 0
    fi
    sdk_log "linux: make compile_commands.json"
    make -C "$src" ARCH=arm64 compile_commands.json
    check_result linux "$src/compile_commands.json"
}

gen_uboot() {
    local src="$SDK_ROOT/source/u-boot"
    sdk_require_source source/u-boot
    if [ ! -f "$src/.config" ]; then
        sdk_warn "u-boot: 缺少 .config（先跑 build_uboot.sh），跳过"
        return 0
    fi
    sdk_log "u-boot: scripts/gen_compile_commands.py"
    (cd "$src" && ./scripts/gen_compile_commands.py)
    check_result u-boot "$src/compile_commands.json"
}

gen_optee() {
    local src="$SDK_ROOT/source/optee/optee_os"
    sdk_require_source source/optee/optee_os
    local out="out/arm-plat-${OPTEE_PLATFORM%%-*}"
    if [ ! -d "$src/$out" ]; then
        sdk_warn "optee: 缺少 $out（先跑 build_optee.sh），跳过"
        return 0
    fi
    # .cmd 里的源文件路径相对仓库根目录解析，-d 必须给根目录（给 out/ 会全部
    # "File not found" 产出空库）；已构建由上面的 out 目录存在性保证
    sdk_log "optee: scripts/gen_compile_commands.py -d .（构建目录 $out）"
    (cd "$src" && ./scripts/gen_compile_commands.py -d . \
        -a "$(command -v "${CROSS_COMPILE}ar" || echo ar)")
    check_result optee "$src/compile_commands.json"
}

gen_atf() {
    local src="$SDK_ROOT/source/atf"
    sdk_require_source source/atf
    if ! command -v bear >/dev/null 2>&1; then
        sdk_warn "atf: 未安装 bear（apt install bear），跳过"
        return 0
    fi
    case "$TFA_BUILD" in
        debug)   TFA_DEBUG=1; TFA_LOG_LEVEL="${TFA_LOG_LEVEL:-40}" ;;
        release) TFA_DEBUG=0; TFA_LOG_LEVEL="${TFA_LOG_LEVEL:-20}" ;;
        *) sdk_die "未知 TFA_BUILD=$TFA_BUILD" ;;
    esac
    # 与 build_tf-a.sh 相同的编译变量；make -B 强制重编让 bear 有命令可拦截，
    # ccache 命中时代价很小（bear 会剥掉 ccache 包装，记录真实编译器）。
    # 注意必须另设 BUILD_BASE：bear 不会带上 build_tf-a.sh 的 SPD/BL32/BL33 变量，
    # 若用默认 ./build 目录会把正式产物里的 BL31 覆盖成 SPD_none 版本
    sdk_log "atf: bear -- make -B PLAT=$TFA_PLAT DEBUG=$TFA_DEBUG（bl1 bl2 bl31）"
    bear --output "$src/compile_commands.json" -- \
        make -C "$src" -B -j"$(nproc)" \
        BUILD_BASE="$SDK_OUT/tf-a/cc-db" \
        PLAT="$TFA_PLAT" ARCH=aarch64 \
        CROSS_COMPILE="$CROSS_COMPILE" \
        DEBUG="$TFA_DEBUG" LOG_LEVEL="$TFA_LOG_LEVEL" \
        QEMU_USE_GIC_DRIVER=QEMU_GICV3 \
        bl1 bl2 bl31 >/dev/null
    check_result atf "$src/compile_commands.json"
}

gen_scp() {
    local src="$SDK_ROOT/source/scp"
    sdk_require_source source/scp
    if [ -z "${SCP_TARGET:-}" ]; then
        sdk_warn "scp: SDK 尚未接线 SCP 构建（build_all.sh 无此步骤），跳过"
        sdk_warn "     接入后: SCP_TARGET=<product> [SCP_PLATFORM=<platform>] $0 scp"
        return 0
    fi
    local bdir="$SDK_OUT/scp/compile-db"
    sdk_log "scp: cmake -DSCP_TARGET=$SCP_TARGET（build dir: ${bdir#$SDK_ROOT/}）"
    # shellcheck disable=SC2086
    cmake -S "$src" -B "$bdir" -G Ninja \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DSCP_TARGET="$SCP_TARGET" \
        ${SCP_PLATFORM:+-DSCP_PLATFORM="$SCP_PLATFORM"}
    ln -sfvn "${bdir}/compile_commands.json" "$src/compile_commands.json"
    check_result scp "$src/compile_commands.json"
}

for component in "${REQUESTED[@]}"; do
    echo
    sdk_log "===== [$component] 生成 compile_commands.json ====="
    case "$component" in
        linux)  gen_linux ;;
        u-boot) gen_uboot ;;
        optee)  gen_optee ;;
        tf-a|atf) gen_atf ;;
        scp)    gen_scp ;;
        buildroot)
            sdk_warn "buildroot: 上游不支持导出编译数据库，跳过（busybox 等包如需索引可单独处理）"
            ;;
        *) sdk_die "未知组件: $component（可选: ${ALL_COMPONENTS[*]} buildroot）" ;;
    esac
done

echo
sdk_log "完成，耗时 $(sdk_timer_elapsed)s。clangd 需配置 --query-driver 识别交叉工具链，"
sdk_log "见 .vscode/settings.json（VS Code 直接生效；其他编辑器参考配置同参数）。"
