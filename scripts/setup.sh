#!/usr/bin/env bash
# 首次环境搭建：系统依赖、repo 工具、交叉工具链（见 spec §5.1）
#   ./scripts/setup.sh
# 跳过 apt（非 Debian 系或无权 sudo）: SKIP_APT=1 ./scripts/setup.sh
#
# 禁止 source：set -euo pipefail 会残留在调用方 shell 中，
# 之后任何返回非零的命令（如 lunch 不存在的 product）都会直接退出交互 shell。
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    echo "错误: 请直接执行 ./scripts/setup.sh，不要 source" >&2
    return 1
fi
set -euo pipefail

SDK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$SDK_ROOT/scripts/lib/common.sh"

# ---------------------------------------------------------------- 1. 系统依赖
APT_PKGS=(
    build-essential bc bison flex libssl-dev libncurses-dev device-tree-compiler
    u-boot-tools cpio rsync python3-pyelftools python3-cryptography
    qemu-system-arm gdb-multiarch ccache ninja-build
    swig libgnutls28-dev uuid-dev
)

if [ "${SKIP_APT:-0}" != "1" ]; then
    if command -v apt-get >/dev/null 2>&1; then
        SUDO=""
        [ "$(id -u)" -ne 0 ] && SUDO="sudo"
        sdk_log "安装 apt 依赖 ..."
        $SUDO apt-get update
        $SUDO apt-get install -y --no-install-recommends "${APT_PKGS[@]}"
    else
        sdk_warn "非 apt 系统，跳过依赖安装。请手动安装: ${APT_PKGS[*]}"
    fi
else
    sdk_log "SKIP_APT=1，跳过系统依赖安装"
fi

# ---------------------------------------------------------------- 2. repo 工具
if [ -x "$SDK_ROOT/tools/repo/repo" ]; then
    sdk_log "repo 已存在: tools/repo/repo"
elif command -v repo >/dev/null 2>&1; then
    sdk_log "使用系统 repo: $(command -v repo)"
else
    sdk_log "下载 repo 到 tools/repo/ ..."
    mkdir -p "$SDK_ROOT/tools/repo"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
        -o "$SDK_ROOT/tools/repo/repo"
    chmod +x "$SDK_ROOT/tools/repo/repo"
fi

# ---------------------------------------------------------------- 3. 交叉工具链
sdk_log "读取 configs/toolchain.mk ..."
# shellcheck disable=SC1090
eval "$(make -s -C "$SDK_ROOT/scripts/lib" -f expand.mk -f "$SDK_ROOT/configs/toolchain.mk" print-toolchain)"

TC_TARBALL="$AARCH64_LINUX_GNU_NAME.tar.xz"
TC_CACHE="$SDK_ROOT/downloads/toolchains/$TC_TARBALL"
TC_INSTALL="$SDK_ROOT/toolchains/$AARCH64_LINUX_GNU_DIR"

mkdir -p "$SDK_ROOT/downloads/toolchains" "$SDK_ROOT/toolchains"

if [ -x "$TC_INSTALL/bin/${CROSS_COMPILE:-aarch64-none-linux-gnu-}gcc" ]; then
    sdk_log "工具链已安装: $TC_INSTALL"
else
    if [ ! -f "$TC_CACHE" ]; then
        sdk_log "下载工具链（约 200MB，首次较慢）..."
        sdk_log "URL: $AARCH64_LINUX_GNU_URL"
        curl -fSL --retry 3 -o "$TC_CACHE" "$AARCH64_LINUX_GNU_URL"
    fi

    if [ -n "$AARCH64_LINUX_GNU_SHA256" ]; then
        sdk_log "校验 sha256 ..."
        echo "$AARCH64_LINUX_GNU_SHA256  $TC_CACHE" | sha256sum -c -
    else
        sdk_warn "configs/toolchain.mk 未配置 SHA256，跳过校验"
        sdk_warn "建议执行: sha256sum '$TC_CACHE' 并把结果填入 AARCH64_LINUX_GNU_SHA256"
    fi

    sdk_log "解压到 $TC_INSTALL ..."
    mkdir -p "$TC_INSTALL"
    tar -xJf "$TC_CACHE" -C "$TC_INSTALL" --strip-components=1
fi
