#!/usr/bin/env bash
# 构建 RootFS（buildroot → rootfs.cpio.gz），叠加板级 overlay，见 spec §5.3
# 当前支持 ROOTFS_TYPE=cpio.gz；ext4 等留给实体板卡接入时扩展（spec §9）
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log rootfs
sdk_require_source source/buildroot
sdk_timer_start

case "$ROOTFS_TYPE" in
    cpio.gz) ;;
    *) sdk_die "暂不支持的 ROOTFS_TYPE=$ROOTFS_TYPE（当前仅实现 cpio.gz）" ;;
esac

BR_SRC="$SDK_ROOT/source/buildroot"
BR_OUT="$SDK_OUT/rootfs/build"
ROOTFS_OUT="$SDK_OUT/rootfs"
mkdir -p "$BR_OUT" "$ROOTFS_OUT"

# 1. 基础 defconfig + O= 独立输出目录
sdk_log "make -C source/buildroot O=$BR_OUT qemu_aarch64_virt_defconfig"
make -C "$BR_SRC" O="$BR_OUT" qemu_aarch64_virt_defconfig

# 2. SDK 定制 fragment：板级 overlay、串口、cpio.gz 格式
OVERLAY_DIR="$SDK_ROOT/board/$BOARD_NAME/rootfs"
cat >> "$BR_OUT/.config" <<EOF

# --- sdk fragment (scripts/build_rootfs.sh) ---
BR2_ROOTFS_OVERLAY="$OVERLAY_DIR"
BR2_TARGET_GENERIC_GETTY_PORT="ttyAMA0"
BR2_TARGET_ROOTFS_CPIO=y
BR2_TARGET_ROOTFS_CPIO_GZIP=y
EOF
if [ "${ENABLE_PERFETTO:-n}" = "y" ]; then
    echo "BR2_PACKAGE_PERFETTO=y" >> "$BR_OUT/.config"
fi
make -C "$BR_SRC" O="$BR_OUT" olddefconfig

# 3. 构建
sdk_log "make -C source/buildroot O=$BR_OUT -j$(nproc)"
make -C "$BR_SRC" O="$BR_OUT" -j"$(nproc)"

cp -v "$BR_OUT/images/rootfs.cpio.gz" "$ROOTFS_OUT/rootfs.cpio.gz"

sdk_log "RootFS 构建完成，耗时 $(sdk_timer_elapsed)s → $ROOTFS_OUT"
