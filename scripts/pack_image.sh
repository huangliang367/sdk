#!/usr/bin/env bash
# 镜像打包（spec §5.3）：
#   把最终文件归拢到 out/<product>/images/，并生成 manifest.txt
#   记录每个文件的来源组件 commit 与构建时间（Lab 7 验收项）
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log pack
sdk_timer_start

IMAGES="$SDK_OUT/images"
mkdir -p "$IMAGES"

sdk_log "归拢镜像 → $IMAGES"

# 1. 固件（TF-A: BL1+FIP 合成的 flash 镜像）
if [ -f "$SDK_OUT/tf-a/qemu_fw.bios" ]; then
    cp -v "$SDK_OUT/tf-a/qemu_fw.bios" "$IMAGES/flash.bin"
elif [ -f "$SDK_OUT/tf-a/flash.bin" ]; then
    cp -v "$SDK_OUT/tf-a/flash.bin" "$IMAGES/flash.bin"
elif [ -f "$SDK_OUT/tf-a/bl1.bin" ]; then
    sdk_warn "仅有 BL1/BL2/BL31（无 FIP），拷贝原始产物"
    for f in bl1.bin bl2.bin bl31.bin fip.bin; do
        [ -f "$SDK_OUT/tf-a/$f" ] && cp -v "$SDK_OUT/tf-a/$f" "$IMAGES/"
    done
else
    sdk_err "缺少 TF-A 产物，请先执行 scripts/build_tf-a.sh"
    exit 1
fi

# 2. kernel / dtb / rootfs
[ -f "$SDK_OUT/kernel/Image" ] && cp -v "$SDK_OUT/kernel/Image" "$IMAGES/"
[ -f "$SDK_OUT/kernel/Image.gz" ] && cp -v "$SDK_OUT/kernel/Image.gz" "$IMAGES/"
if [ -n "${KERNEL_DTB:-}" ] && [ -f "$SDK_OUT/kernel/board.dtb" ]; then
    cp -v "$SDK_OUT/kernel/board.dtb" "$IMAGES/$(basename "$KERNEL_DTB")"
fi
[ -f "$SDK_OUT/rootfs/rootfs.cpio.gz" ] && cp -v "$SDK_OUT/rootfs/rootfs.cpio.gz" "$IMAGES/"

# 3. manifest.txt：构建时间 + product + 各组件来源 commit
MANIFEST_TXT="$IMAGES/manifest.txt"
{
    echo "# SDK image manifest"
    echo "build_time: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "product:    $SDK_PRODUCT"
    echo "variant:    $BUILD_VARIANT"
    echo "soc/board:  $SOC_NAME / $BOARD_NAME"
    echo ""
    echo "# source revisions"
    for c in $(sdk_components) buildroot; do
        repo_rel="$(sdk_component_repo "$c" 2>/dev/null || echo "source/buildroot")"
        if [ -d "$SDK_ROOT/$repo_rel/.git" ]; then
            printf '%-28s %s\n' "$c:" \
                "$(git -C "$SDK_ROOT/$repo_rel" describe --tags --always 2>/dev/null) ($(git -C "$SDK_ROOT/$repo_rel" rev-parse HEAD 2>/dev/null))"
        else
            printf '%-28s %s\n' "$c:" "N/A"
        fi
    done
    echo ""
    echo "# applied patches"
    for c in $(sdk_components); do
        repo_rel="$(sdk_component_repo "$c")"
        if [ -f "$SDK_ROOT/$repo_rel/.patched" ]; then
            sed "s|^|$c: |" "$SDK_ROOT/$repo_rel/.patched"
        fi
    done
    echo ""
    echo "# files"
    (cd "$IMAGES" && ls -l | grep -v manifest.txt)
} > "$MANIFEST_TXT"

sdk_log "manifest: $MANIFEST_TXT"
sdk_log "打包完成，耗时 $(sdk_timer_elapsed)s"
echo
ls -l "$IMAGES"
