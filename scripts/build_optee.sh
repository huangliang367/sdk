#!/usr/bin/env bash
# 构建 OP-TEE OS（BL32），见 spec §5.3
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product
sdk_begin_log optee
sdk_require_source source/optee/optee_os
sdk_use_toolchain
sdk_timer_start

OPTEE_SRC="$SDK_ROOT/source/optee/optee_os"
OPTEE_OUT="$SDK_OUT/optee"
mkdir -p "$OPTEE_OUT"

case "$BUILD_VARIANT" in
    debug)   OPTEE_DEBUG=1; OPTEE_LOG_LEVEL="${OPTEE_LOG_LEVEL:-3}" ;;
    release) OPTEE_DEBUG=0; OPTEE_LOG_LEVEL="${OPTEE_LOG_LEVEL:-1}" ;;
esac

sdk_log "make -C source/optee/optee_os PLATFORM=$OPTEE_PLATFORM DEBUG=$OPTEE_DEBUG"
# 屏蔽外部 ARCH（内核构建常 export ARCH=arm64，会覆盖 optee 的 ARCH ?= arm 默认值）
env -u ARCH make -C "$OPTEE_SRC" \
    PLATFORM="$OPTEE_PLATFORM" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    CROSS_COMPILE_CORE="$CROSS_COMPILE" \
    CFG_ARM64_core=y \
    DEBUG="$OPTEE_DEBUG" \
    CFG_TEE_CORE_LOG_LEVEL="$OPTEE_LOG_LEVEL" \
    -j"$(nproc)"

# OP-TEE 产物目录: out/arm-plat-<platform 短名>/core/（如 vexpress-qemu_virt → arm-plat-vexpress）
PLAT_SHORT="${OPTEE_PLATFORM%%-*}"
CORE_OUT="$OPTEE_SRC/out/arm-plat-$PLAT_SHORT/core"
LEGACY_OUT="$OPTEE_SRC/out/arm-plat-$OPTEE_PLATFORM"
for f in tee-header_v2.bin tee-pager_v2.bin tee-pageable_v2.bin tee.elf; do
    for d in "$CORE_OUT" "$CORE_OUT/.." "$LEGACY_OUT" "$LEGACY_OUT/core"; do
        if [ -f "$d/$f" ]; then cp -v "$d/$f" "$OPTEE_OUT/"; break; fi
    done
done

ls "$OPTEE_OUT"/tee-header_v2.bin >/dev/null 2>&1 \
    || sdk_die "未找到 tee-header_v2.bin，请检查 OP-TEE 构建输出"

sdk_log "OP-TEE 构建完成，耗时 $(sdk_timer_elapsed)s → $OPTEE_OUT"
