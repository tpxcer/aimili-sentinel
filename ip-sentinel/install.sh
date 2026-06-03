#!/bin/bash
# ==========================================================
# 脚本名称: install.sh (v4.3.0 模块化终极引导入口)
# 核心功能: 权限鉴定、沙盒创建、Ctrl+C 熔断保护、业务流引导
# ==========================================================

if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m❌ 权限被拒绝: 部署 IP-Sentinel 需要最高系统权限。\033[0m"
  echo -e "💡 请切换到 root 用户 (执行 su root 或 sudo -i) 后重新运行指令。"
  exit 1
fi

SECURE_TMP=$(mktemp -d /tmp/ips_install.XXXXXX)

cleanup_and_exit() {
    echo -e "\n\n\033[33m⚠️ 检测到中断信号 (Ctrl+C)，安装操作已被手动中止。\033[0m"
    echo -e "🧹 正在清理临时沙盒文件..."
    rm -rf "$SECURE_TMP" 2>/dev/null
    exit 1
}
trap cleanup_and_exit INT QUIT TERM
trap 'rm -rf "$SECURE_TMP" 2>/dev/null' EXIT HUP

REPO_RAW_URL="https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/ip-sentinel"

echo -e "\n⏳ 正在拉取 IP-Sentinel v4.3.0 安装模块引擎..."

# 【核心防线】追加 ?t=$(date +%s) 强行击穿 GitHub CDN 缓存
curl -fsSL --connect-timeout 10 --retry 3 "${REPO_RAW_URL}/install/build_agent.sh?t=$(date +%s)" -o "${SECURE_TMP}/build_agent.sh"

if [ ! -s "${SECURE_TMP}/build_agent.sh" ]; then
    echo -e "\033[31m❌ 致命错误：核心安装引擎拉取失败！网络阻断或 GitHub Raw 异常。\033[0m"
    exit 1
fi

export SECURE_TMP
export REPO_RAW_URL

chmod +x "${SECURE_TMP}/build_agent.sh"
bash "${SECURE_TMP}/build_agent.sh"

exit $?
