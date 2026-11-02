# configs/board/qemu-a78ae.mk
# Board 级配置：板卡对 SoC 的实例化（见 docs/sdk-directory-spec.md §2.2）

include $(SDK_ROOT)/configs/soc/qemu-virt.mk

BOARD_NAME      := qemu-a78ae
# QEMU virt 无 a78ae 专用 model，用 max 并打开所需扩展
QEMU_MACHINE    := virt,gic-version=3,virtualization=on,secure=on
QEMU_CPU        := max
DTS_OVERLAYS    := board/qemu-a78ae/dts
ROOTFS_TYPE     := cpio.gz        # 调试期用 initramfs，免块设备
KERNEL_FRAGMENTS:= optee.cfg debug.cfg

# QEMU 启动用的 DTB。留空表示由 QEMU 根据 machine 自动生成
# （virt 平台无上游 dts，板级 dts 就绪后改为相对 dts 目录的路径，如 qemu-virt-a78ae.dtb）
KERNEL_DTB      :=
