# scripts/lib/expand.mk
# 把 configs/product/<product>.mk（含 include 链）展开为 shell 可 eval 的
# `export VAR='value'` 序列。由 envsetup.sh 的 lunch() 调用，脚本不直接执行。
#
# 用法:
#   make -s -C scripts/lib -f expand.mk PRODUCT=<product> printenv
#   make -s -C scripts/lib -f expand.mk -f configs/toolchain.mk print-toolchain
#
# 实现说明: 只导出 origin 为 file 的变量（即在 mk 文件中定义的配置变量），
# 自动排除 make 内建/环境/命令行变量；sq/USER_VARS/EXCLUDE 为本文件辅助
# 变量，显式排除（sq 被导出会因自引用展开导致 make 无限递归）。
# 注意不能用 filter-out 做快照差集——自动变量名 %D/%F 等会作为模式
# 误杀以 D/F 结尾的变量名（如 TFA_BUILD）。

SDK_ROOT := $(abspath $(CURDIR)/../..)

# 值的单引号转义: ' → '"'"'。注意外层包裹引号也必须是 '"'"' 形式，
# 否则会被 shell 当引号剥掉，eval 时含空格的值（如 KERNEL_FRAGMENTS）会炸开。
define sq
'"'"'$(subst ','"'"',$(strip $($(strip $1))))'"'"'
endef

# 排除本文件辅助变量 + make 自身 origin 也为 file 的特殊变量
EXCLUDE := sq EXCLUDE USER_VARS \
           MAKEFLAGS MAKEFILE_LIST MAKECMDGOALS MAKE_COMMAND \
           .DEFAULT_GOAL .VARIABLES .RECIPEPREFIX CURDIR SHELL

ifneq ($(filter printenv,$(MAKECMDGOALS)),)
PRODUCT ?=
ifeq ($(PRODUCT),)
$(error 用法: make -f expand.mk PRODUCT=<product> printenv)
endif
include $(SDK_ROOT)/configs/product/$(PRODUCT).mk
endif

USER_VARS = $(foreach v,$(.VARIABLES),$(if $(filter file,$(origin $v)),$v))

.PHONY: printenv print-toolchain
# 整条 export 语句通过 make 展开进 printf 的格式串（单引号均为字面量，
# 不能被 shell 当引号剥掉）；配置值中不允许出现 % 和反斜杠。
printenv print-toolchain:
	@$(foreach v,$(filter-out $(EXCLUDE),$(USER_VARS)),printf 'export $(v)=$(call sq,$v)\n';)
