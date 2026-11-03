# configs/soc/qemu-virt.mk
# SoC 级配置：描述芯片本身能力，与具体板卡无关（见 docs/sdk-directory-spec.md §2.1）

SOC_NAME        := qemu-virt
ARCH            := arm64
CROSS_COMPILE   := aarch64-none-linux-gnu-
TFA_PLAT        := qemu
# OP-TEE ≥ 4.x：qemu_virt flavor 仅 32 位（cortex-a15），aarch64 用 qemu_armv8a
OPTEE_PLATFORM  := vexpress-qemu_armv8a
UBOOT_DEFCONFIG := qemu_arm64_defconfig
KERNEL_DEFCONFIG:= defconfig
CPU_CORES       := 4
DRAM_BASE       := 0x40000000
DRAM_SIZE       := 2G
UART_BASE       := 0x09000000
