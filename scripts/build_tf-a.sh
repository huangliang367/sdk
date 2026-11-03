#!/usr/bin/env bash
# 构建 TF-A（BL1/BL2/BL31 + FIP），见 spec §5.3
# 依赖 build_optee.sh / build_uboot.sh 的产物（BL32/BL33）；缺省时只构建 BL1/BL2/BL31
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log tf-a
sdk_require_source source/atf
sdk_use_toolchain
sdk_timer_start

TFA_SRC="$SDK_ROOT/source/atf"
TFA_OUT="$SDK_OUT/tf-a"
mkdir -p "$TFA_OUT"

# 调试级别（spec §7.3：bringup 用 40，稳定后可降 20）
case "$TFA_BUILD" in
    debug)   TFA_DEBUG=1; TFA_LOG_LEVEL="${TFA_LOG_LEVEL:-40}" ;;
    release) TFA_DEBUG=0; TFA_LOG_LEVEL="${TFA_LOG_LEVEL:-20}" ;;
    *) sdk_die "未知 TFA_BUILD=$TFA_BUILD（configs/product 应为 debug/release）" ;;
esac

# BL33(U-Boot) / BL32(OP-TEE) 就绪则打包进 FIP
BL33="$SDK_OUT/u-boot/u-boot.bin"
BL32_HEADER="$SDK_OUT/optee/tee-header_v2.bin"
BL32_PAGER="$SDK_OUT/optee/tee-pager_v2.bin"
BL32_PAGEABLE="$SDK_OUT/optee/tee-pageable_v2.bin"

EXTRA_VARS=()
TARGETS=(bl1 bl2 bl31)
if [ -f "$BL33" ] && [ -f "$BL32_HEADER" ]; then
    sdk_log "BL32/BL33 就绪，构建 all fip（SPD=opteed）"
    EXTRA_VARS+=(
        "BL33=$BL33"
        "BL32=$BL32_HEADER"
        "BL32_EXTRA1=$BL32_PAGER"
        "BL32_EXTRA2=$BL32_PAGEABLE"
        "SPD=opteed"
    )
    TARGETS=(all fip)
else
    sdk_warn "缺 BL32 或 BL33（先跑 build_optee.sh / build_uboot.sh 可打包 FIP），仅构建 BL1/BL2/BL31"
fi

sdk_log "make -C source/atf PLAT=$TFA_PLAT DEBUG=$TFA_DEBUG LOG_LEVEL=$TFA_LOG_LEVEL ${TARGETS[*]}"
make -C "$TFA_SRC" \
    PLAT="$TFA_PLAT" ARCH=aarch64 \
    CROSS_COMPILE="$CROSS_COMPILE" \
    DEBUG="$TFA_DEBUG" LOG_LEVEL="$TFA_LOG_LEVEL" \
    QEMU_USE_GIC_DRIVER=QEMU_GICV3 \
    "${EXTRA_VARS[@]}" \
    -j"$(nproc)" \
    "${TARGETS[@]}"

# TF-A 构建目录: build/<plat>/<debug|release>/
BD="$TFA_SRC/build/$TFA_PLAT/$TFA_BUILD"

sdk_log "拷贝产物 → $TFA_OUT"
for f in bl1.bin bl2.bin bl31.bin fip.bin qemu_fw.bios qemu_fw.rom; do
    [ -f "$BD/$f" ] && cp -v "$BD/$f" "$TFA_OUT/"
done
# .elf 供 GDB 使用（见 spec §7.2）
for d in bl1 bl2 bl31; do
    [ -f "$BD/$d/$d.elf" ] && cp -v "$BD/$d/$d.elf" "$TFA_OUT/"
done
# QEMU -bios 使用的统一命名
if [ -f "$TFA_OUT/qemu_fw.bios" ] && [ ! -f "$TFA_OUT/flash.bin" ]; then
    cp -v "$TFA_OUT/qemu_fw.bios" "$TFA_OUT/flash.bin"
fi

sdk_log "TF-A 构建完成，耗时 $(sdk_timer_elapsed)s → $TFA_OUT"
