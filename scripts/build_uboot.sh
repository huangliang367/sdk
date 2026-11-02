#!/usr/bin/env bash
# 构建 U-Boot（BL33），见 spec §5.3
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log u-boot
sdk_require_source source/u-boot
sdk_use_toolchain
sdk_timer_start

UBOOT_SRC="$SDK_ROOT/source/u-boot"
UBOOT_OUT="$SDK_OUT/u-boot"
mkdir -p "$UBOOT_OUT"

sdk_log "make -C source/u-boot $UBOOT_DEFCONFIG"
make -C "$UBOOT_SRC" "$UBOOT_DEFCONFIG"

sdk_log "make -C source/u-boot -j$(nproc)"
make -C "$UBOOT_SRC" CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)"

for f in u-boot.bin u-boot u-boot.dtb; do
    [ -f "$UBOOT_SRC/$f" ] && cp -v "$UBOOT_SRC/$f" "$UBOOT_OUT/"
done

[ -f "$UBOOT_OUT/u-boot.bin" ] || sdk_die "未生成 u-boot.bin"

sdk_log "U-Boot 构建完成，耗时 $(sdk_timer_elapsed)s → $UBOOT_OUT"
