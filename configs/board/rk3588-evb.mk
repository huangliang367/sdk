# configs/board/rk3588-evb.mk
# Board 级配置（预留，见 docs/sdk-directory-spec.md §9）

include $(SDK_ROOT)/configs/soc/rk3588.mk

BOARD_NAME      := rk3588-evb
# QEMU_MACHINE    := 实体板卡不使用
# ROOTFS_TYPE     := ext4
# KERNEL_FRAGMENTS:= optee.cfg
