# configs/toolchain.mk
# 交叉编译工具链下载配置（scripts/setup.sh 消费）
# 官方发布页：https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain
#
# 校验和获取方式：下载完成后执行
#   sha256sum downloads/toolchains/<tarball 文件名>
# 把结果填入下方 *_SHA256，setup.sh 会在解压前强制校验。

AARCH64_LINUX_GNU_VERSION := 14.2.rel1
AARCH64_LINUX_GNU_NAME    := arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu
AARCH64_LINUX_GNU_URL     := https://developer.arm.com/-/media/Files/downloads/gnu/14.2.rel1/binrel/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu.tar.xz
AARCH64_LINUX_GNU_SHA256  :=
AARCH64_LINUX_GNU_DIR     := aarch64-none-linux-gnu
