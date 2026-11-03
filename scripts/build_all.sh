#!/usr/bin/env bash
# 一键全量构建（spec §5.2）：
#   optee → u-boot → tf-a(FIP) → kernel → rootfs → pack
# 可独立运行的单组件脚本见 scripts/build_<component>.sh
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product

STEPS=(
    build_tf-a.sh
    build_uboot.sh
    build_optee.sh
    build_kernel.sh
    build_rootfs.sh
    pack_image.sh
)

declare -a SUMMARY=()
overall_start=$(date +%s)

for step in "${STEPS[@]}"; do
    step_start=$(date +%s)
    echo
    sdk_log "===== [$step] 开始 ====="
    if ! "$SDK_ROOT/scripts/$step"; then
        sdk_err "===== [$step] 失败，终止全量构建 ====="
        exit 1
    fi
    SUMMARY+=( "$(printf '%-18s %ss' "$step" "$(( $(date +%s) - step_start ))")" )
done

echo
sdk_log "===== 全量构建完成（总计 $(( $(date +%s) - overall_start ))s）====="
printf '  %s\n' "${SUMMARY[@]}"
echo
sdk_log "镜像目录: $SDK_OUT/images/（启动: scripts/run_qemu.sh [--debug] [--log]）"
