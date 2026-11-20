#!/usr/bin/env bash
# 创建/删除 WSL 与 QEMU guest 直连的 tap 网卡（配合 QEMU_NET=tap 使用）
#   sudo scripts/net_tap.sh setup   # 建 tap0 并配置宿主机侧 IP
#   sudo scripts/net_tap.sh clean   # 删除 tap0
#
# 网段与 guest 侧回退静态 IP 保持一致（见 board/qemu-a78ae/rootfs/etc/init.d/S40network）
set -euo pipefail

TAP_IF="${QEMU_TAP_IF:-tap0}"
TAP_HOST_IP="192.168.76.1/24"
TAP_GUEST_IP="192.168.76.2"
TAP_USER="${SUDO_USER:-$USER}"

case "${1:-}" in
    setup)
        if ip link show "$TAP_IF" >/dev/null 2>&1; then
            echo "$TAP_IF 已存在"
        else
            ip tuntap add dev "$TAP_IF" mode tap user "$TAP_USER"
            ip addr add "$TAP_HOST_IP" dev "$TAP_IF"
            ip link set "$TAP_IF" up
        fi
        echo "宿主侧: $TAP_IF ($TAP_HOST_IP)  guest 静态 IP: $TAP_GUEST_IP"
        echo "启动:   QEMU_NET=tap ./scripts/run_qemu.sh"
        echo "连接:   ping $TAP_GUEST_IP / sftp root@$TAP_GUEST_IP（密码见 BR2_TARGET_GENERIC_ROOT_PASSWD）"
        ;;
    clean)
        ip link del "$TAP_IF" 2>/dev/null || true
        ;;
    *)
        echo "用法: $0 setup|clean" >&2
        exit 1
        ;;
esac
