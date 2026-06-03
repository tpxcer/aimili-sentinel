#!/usr/bin/env bash
set -e

RAW_BASE="https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main"

if [ "$(id -u)" != "0" ]; then
  echo "错误: 请使用 root 权限运行安装器。"
  exit 1
fi

echo "========================================"
echo " Aimili Sentinel 安装器"
echo "========================================"
echo "1) 安装 AimiliVPN Gateway"
echo "2) 安装 IP-Sentinel Agent"
echo "3) 安装 IP-Sentinel Master"
echo "4) 依次安装 AimiliVPN Gateway 与 IP-Sentinel Agent"
echo "0) 退出"
read -r -p "请选择 [0-4]: " choice

case "$choice" in
  1)
    bash -c "$(curl -fsSL "${RAW_BASE}/aimili-vpngate/install.sh")"
    ;;
  2)
    bash -c "$(curl -fsSL "${RAW_BASE}/ip-sentinel/install.sh")"
    ;;
  3)
    bash -c "$(curl -fsSL "${RAW_BASE}/ip-sentinel/master/install_master.sh")"
    ;;
  4)
    bash -c "$(curl -fsSL "${RAW_BASE}/aimili-vpngate/install.sh")"
    bash -c "$(curl -fsSL "${RAW_BASE}/ip-sentinel/install.sh")"
    ;;
  0|"")
    echo "已退出。"
    ;;
  *)
    echo "无效选择。"
    exit 1
    ;;
esac
