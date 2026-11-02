# configs/product/qemu_release.mk
# Product 级配置：QEMU 发布版（安全启动预留，见 docs/sdk-directory-spec.md §2.3 / Lab 7）

include $(SDK_ROOT)/configs/board/qemu-a78ae.mk

PRODUCT_NAME    := qemu_release
BUILD_VARIANT   := release
TFA_BUILD       := release        # TF-A DEBUG=0, LOG_LEVEL=20
ENABLE_GDBSERVER:= n
ENABLE_PERFETTO := y
SIGN_IMAGES     := n              # TODO(Lab 7): 接入安全启动后改为 y
KERNEL_FRAGMENTS:= optee.cfg      # 发布版不携带 debug fragment
