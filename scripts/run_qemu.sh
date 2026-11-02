#!/usr/bin/env bash
# 启动 QEMU（spec §7.1 / §7.3）
#   ./scripts/run_qemu.sh            # 正常启动
#   ./scripts/run_qemu.sh --debug    # 附加 -s -S（GDB stub :1234，CPU 停复位处）
#   ./scripts/run_qemu.sh --log      # 串口输出 tee 到 out/<product>/logs/console-<ts>.log
#   ./scripts/run_qemu.sh --dry-run  # 只打印命令，不启动
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

sdk_ensure_product

DEBUG=0
LOG=0
DRY_RUN=0
EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --debug)   DEBUG=1 ;;
        --log)     LOG=1 ;;
        --dry-run) DRY_RUN=1 ;;
        *)         EXTRA_ARGS+=( "$arg" ) ;;
    esac
done

IMAGES="$SDK_OUT/images"
BIOS="$IMAGES/flash.bin"
KERNEL_IMG="$IMAGES/Image"
INITRD="$IMAGES/rootfs.cpio.gz"
DTB=""
[ -n "${KERNEL_DTB:-}" ] && [ -f "$IMAGES/$(basename "$KERNEL_DTB")" ] && DTB="$IMAGES/$(basename "$KERNEL_DTB")"

# 镜像就绪检查（--dry-run 除外）
if [ "$DRY_RUN" = 0 ]; then
    [ -f "$BIOS" ] || sdk_die "缺少 $BIOS，请先执行 scripts/build_all.sh"
    [ -f "$KERNEL_IMG" ] || sdk_warn "缺少 $KERNEL_IMG，QEMU 将只启动固件"
fi

# 内核日志级别：调试版 8，其余 4（spec §7.3）
if [ "$BUILD_VARIANT" = debug ]; then
    KERN_LOGLEVEL=8
else
    KERN_LOGLEVEL=4
fi

CMD=(
    qemu-system-aarch64
    -machine "$QEMU_MACHINE"
    -cpu "$QEMU_CPU"
    -smp "$CPU_CORES"
    -m "$DRAM_SIZE"
    -nographic
    -bios "$BIOS"
    -append "console=ttyAMA0,115200 earlycon loglevel=$KERN_LOGLEVEL"
    -serial mon:stdio
    -netdev user,id=n0 -device virtio-net-device,netdev=n0
)
[ -f "$KERNEL_IMG" ] && CMD+=( -kernel "$KERNEL_IMG" )
[ -f "$INITRD" ]     && CMD+=( -initrd "$INITRD" )
[ -n "$DTB" ]        && CMD+=( -dtb "$DTB" )

if [ "$DEBUG" = 1 ]; then
    CMD+=( -s -S )
fi
CMD+=( "${EXTRA_ARGS[@]}" )

if [ "$DRY_RUN" = 1 ]; then
    printf '%q ' "${CMD[@]}"; echo
    exit 0
fi

if [ "$LOG" = 1 ]; then
    CONSOLE_LOG="$(sdk_newlog console)"
    CONSOLE_LOG="${CONSOLE_LOG%.log}-console.log"
    sdk_log "串口日志: $CONSOLE_LOG"
    set -o pipefail
    "${CMD[@]}" 2>&1 | tee "$CONSOLE_LOG"
else
    exec "${CMD[@]}"
fi
