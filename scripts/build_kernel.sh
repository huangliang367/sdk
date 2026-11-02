#!/usr/bin/env bash
# 构建 Linux Kernel（Image + DTB + modules），见 spec §5.3
# 流程: make <KERNEL_DEFCONFIG> → merge qemu_defconfig 增量与 KERNEL_FRAGMENTS → 编译
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log kernel
sdk_require_source source/linux
sdk_use_toolchain
sdk_timer_start

KERNEL_SRC="$SDK_ROOT/source/linux"
KERNEL_OUT="$SDK_OUT/kernel"
mkdir -p "$KERNEL_OUT/dtb" "$KERNEL_OUT/modules"

sdk_log "make -C source/linux $KERNEL_DEFCONFIG"
make -C "$KERNEL_SRC" ARCH=arm64 "$KERNEL_DEFCONFIG"

# 合并配置: 平台增量 + product 指定的 fragments（见 configs/kernel/）
MERGE_LIST=( "$SDK_ROOT/configs/kernel/qemu_defconfig" )
for frag in ${KERNEL_FRAGMENTS:-}; do
    f="$SDK_ROOT/configs/kernel/fragments/$frag"
    [ -f "$f" ] || sdk_die "kernel fragment 不存在: $f（检查 configs 的 KERNEL_FRAGMENTS）"
    MERGE_LIST+=( "$f" )
done
if [ "${#MERGE_LIST[@]}" -gt 0 ]; then
    sdk_log "merge fragments: ${MERGE_LIST[*]#$SDK_ROOT/}"
    (cd "$KERNEL_SRC" && KCONFIG_CONFIG=.config \
        scripts/kconfig/merge_config.sh -m .config "${MERGE_LIST[@]}")
    make -C "$KERNEL_SRC" ARCH=arm64 olddefconfig
fi

sdk_log "make -C source/linux -j$(nproc) Image dtbs modules"
make -C "$KERNEL_SRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$(nproc)" \
    Image dtbs modules

sdk_log "modules_install → $KERNEL_OUT/modules"
make -C "$KERNEL_SRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
    INSTALL_MOD_PATH="$KERNEL_OUT/modules" modules_install

# 拷贝产物
cp -v "$KERNEL_SRC/arch/arm64/boot/Image" "$KERNEL_OUT/"
gzip -kf "$KERNEL_OUT/Image" 2>/dev/null || true
[ -f "$KERNEL_SRC/vmlinux" ] && cp -v "$KERNEL_SRC/vmlinux" "$KERNEL_OUT/"

# 收集全部 dtb；KERNEL_DTB 指定的做顶层软链，供 run_qemu.sh 使用
while IFS= read -r dtb; do
    cp -v "$dtb" "$KERNEL_OUT/dtb/"
done < <(find "$KERNEL_SRC/arch/arm64/boot/dts" -name '*.dtb' 2>/dev/null)

if [ -n "${KERNEL_DTB:-}" ]; then
    if [ -f "$KERNEL_OUT/dtb/$KERNEL_DTB" ]; then
        ln -sfv "dtb/$KERNEL_DTB" "$KERNEL_OUT/board.dtb"
    else
        sdk_warn "KERNEL_DTB=$KERNEL_DTB 不在本次构建产物中，忽略"
    fi
fi

sdk_log "Kernel 构建完成，耗时 $(sdk_timer_elapsed)s → $KERNEL_OUT"
