#!/usr/bin/env bash
# SDK 脚本公共函数库：日志、错误处理、配置加载
# 由其他脚本 source，不直接执行。

if [ -n "${SDK_COMMON_LOADED:-}" ]; then
    return 0
fi
SDK_COMMON_LOADED=1

# ---------------------------------------------------------------- 路径解析
_SDK_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 允许外部预先注入 SDK_ROOT（如 tests 或异地调用），否则按本文件位置推导
SDK_ROOT="${SDK_ROOT:-$(cd "$_SDK_LIB_DIR/../.." && pwd)}"
export SDK_ROOT

# ---------------------------------------------------------------- 日志
_sdk_log() { # <level> <msg...>
    local level="$1"; shift
    echo "[$(date '+%H:%M:%S')] [$level] $*"
}
sdk_log()  { _sdk_log "INFO" "$@"; }
sdk_warn() { _sdk_log "WARN" "$@" >&2; }
sdk_err()  { _sdk_log "ERROR" "$@" >&2; }
sdk_die()  { sdk_err "$@"; exit 1; }

sdk_ts() { date '+%Y%m%d-%H%M%S'; }

# ---------------------------------------------------------------- 构建日志
# 每个组件每次构建写 out/<product>/logs/YYYYMMDD-HHMMSS-<component>.log
sdk_newlog() { # <component> → 打印日志文件路径
    local component="$1"
    [ -n "${SDK_OUT:-}" ] || sdk_die "sdk_newlog: SDK_OUT 未设置（先 lunch <product>）"
    mkdir -p "$SDK_OUT/logs"
    echo "$SDK_OUT/logs/$(sdk_ts)-${component}.log"
}

sdk_begin_log() { # <component>：后续 stdout/stderr 全部 tee 到构建日志
    local component="$1"
    local log
    log="$(sdk_newlog "$component")"
    export SDK_LOG_FILE="$log"
    sdk_log "日志: $log"
    exec > >(tee -a "$log") 2>&1
}

# ---------------------------------------------------------------- product / 配置
# 确保已选择 product：优先用已注入的 SDK_PRODUCT，其次 PRODUCT 环境变量
sdk_ensure_product() {
    if [ -z "${SDK_PRODUCT:-}" ]; then
        if [ -n "${PRODUCT:-}" ]; then
            # shellcheck disable=SC1091
            source "$SDK_ROOT/scripts/envsetup.sh"
            lunch "$PRODUCT" || sdk_die "lunch $PRODUCT 失败"
        else
            sdk_die "未选择 product。请先执行: source scripts/envsetup.sh && lunch qemu_debug
或带变量调用: PRODUCT=qemu_debug $0"
        fi
    fi
    export SDK_OUT="${SDK_OUT:-$SDK_ROOT/out/$SDK_PRODUCT}"
}

# 确保上游源码已同步
sdk_require_source() { # <相对路径>…
    local d
    for d in "$@"; do
        [ -d "$SDK_ROOT/$d" ] || sdk_die "缺少 $d，请先执行: scripts/sync.sh"
    done
}

# 组件 → 源码目录（patch.sh / build_*.sh 共用）
sdk_component_repo() { # <component> → 源码树相对路径
    case "$1" in
        tf-a)   echo "source/arm-trusted-firmware" ;;
        optee)  echo "source/optee/optee_os" ;;
        u-boot) echo "source/u-boot" ;;
        linux)  echo "source/linux" ;;
        *)      return 1 ;;
    esac
}

sdk_components() { echo "tf-a optee u-boot linux"; }

# 平台补丁层级：common → $SOC_NAME（见 spec §4.1）
sdk_patch_layers() { # <component> → 每层补丁目录（相对 SDK_ROOT），可能为空
    local component="$1"
    echo "patches/$component/common"
    [ -n "${SOC_NAME:-}" ] && echo "patches/$component/$SOC_NAME"
}

# ---------------------------------------------------------------- 工具链 / ccache
# 把工具链与 ccache 注入 PATH（若存在）
sdk_use_toolchain() {
    local tc="$SDK_ROOT/toolchains/${CROSS_COMPILE%-}/bin"
    if [ -d "$tc" ]; then
        export PATH="$tc:$PATH"
    else
        sdk_warn "工具链未安装: toolchains/${CROSS_COMPILE%-}（可执行 scripts/setup.sh）"
    fi
    if command -v ccache >/dev/null 2>&1; then
        export CCACHE_DIR="${CCACHE_DIR:-$SDK_ROOT/.ccache}"
        export PATH="/usr/lib/ccache:$PATH"
    fi
}

# ---------------------------------------------------------------- 计时
SDK_T0=0
sdk_timer_start() { SDK_T0=$(date +%s); }
sdk_timer_elapsed() { echo $(( $(date +%s) - SDK_T0 )); }
