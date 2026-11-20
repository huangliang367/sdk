export ARCH=arm64

PWD := $(shell pwd)
# SDK 根目录（本目录的上两级），工具链在 SDK 内，直接用绝对路径
SDK_ROOT := ${PWD}/../..
export CROSS_COMPILE=${SDK_ROOT}/toolchains/aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-

export KDIR=${PWD}/../../source/linux

obj-m += test.o

all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean