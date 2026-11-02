#!/usr/bin/env bash
# SDK 环境入口（source 使用，勿直接执行）
#   source scripts/envsetup.sh
#   lunch qemu_debug
#
# 也可带参数自动 lunch: source scripts/envsetup.sh qemu_debug

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# 工具链 / repo 注入 PATH（存在才注入）
_tc="$SDK_ROOT/toolchains/aarch64-none-linux-gnu/bin"
[ -d "$_tc" ] && export PATH="$_tc:$PATH"
[ -d "$SDK_ROOT/tools/repo" ] && export PATH="$SDK_ROOT/tools/repo:$PATH"
export PATH="$SDK_ROOT/scripts:$PATH"

# ---------------------------------------------------------------- lunch
lunch() { # <product>
    local product="$1"
    local mk="$SDK_ROOT/configs/product/$product.mk"
    if [ -z "$product" ] || [ ! -f "$mk" ]; then
        sdk_err "unknown product: '${product:-<空>}'，可选:"
        ls "$SDK_ROOT/configs/product/"*.mk 2>/dev/null | sed 's/.*\//    /; s/\.mk//'
        return 1
    fi

    export SDK_PRODUCT="$product"
    export SDK_OUT="$SDK_ROOT/out/$product"
    mkdir -p "$SDK_OUT"

    # 用 make 展开三级配置，避免重复解析逻辑（见 spec §2.4）
    local env
    if ! env="$(make -s -C "$SDK_ROOT/scripts/lib" -f expand.mk PRODUCT="$product" printenv)"; then
        sdk_err "配置展开失败: $product"
        return 1
    fi
    eval "$env"

    # 记录当前选择，便于新终端恢复
    echo "$product" > "$SDK_ROOT/.sdk_product"

    echo "== SDK: $SDK_PRODUCT | out: $SDK_OUT =="
    echo "   soc=$SOC_NAME board=$BOARD_NAME variant=$BUILD_VARIANT cross=$CROSS_COMPILE"
}

# 恢复上次的 product（存在记录时）
if [ -z "${SDK_PRODUCT:-}" ] && [ -f "$SDK_ROOT/.sdk_product" ]; then
    _prev="$(cat "$SDK_ROOT/.sdk_product")"
    [ -f "$SDK_ROOT/configs/product/$_prev.mk" ] && lunch "$_prev" >/dev/null
fi

# source envsetup.sh <product> 时自动 lunch
if [ -n "${1:-}" ]; then
    lunch "$1"
fi
