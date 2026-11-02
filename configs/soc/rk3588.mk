# configs/soc/rk3588.mk
# SoC 级配置（预留，见 docs/sdk-directory-spec.md §9）
# 接入实体板卡时按 qemu-virt.mk 的格式补全，并新增对应 board/product 配置。

SOC_NAME        := rk3588
ARCH            := arm64
CROSS_COMPILE   := aarch64-none-linux-gnu-
# TFA_PLAT        := rk3588
# OPTEE_PLATFORM  := rockchip-rk3588
# UBOOT_DEFCONFIG := rk3588_defconfig
# KERNEL_DEFCONFIG:= defconfig
CPU_CORES       := 8
# DRAM_BASE       := 0x80000000
# DRAM_SIZE       := 8G
# UART_BASE       := 0xfeb50000
