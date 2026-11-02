# configs/product/qemu_debug.mk
# Product 级配置：QEMU 调试版（见 docs/sdk-directory-spec.md §2.3）

include $(SDK_ROOT)/configs/board/qemu-a78ae.mk

PRODUCT_NAME    := qemu_debug
BUILD_VARIANT   := debug
TFA_BUILD       := debug          # TF-A DEBUG=1, LOG_LEVEL=40
ENABLE_GDBSERVER:= y
ENABLE_PERFETTO := y
SIGN_IMAGES     := n
