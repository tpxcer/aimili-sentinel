#!/bin/bash

# ==========================================================
# 脚本名称: uninstall_master.sh
# 核心功能: 司令部无痕销毁、调度进程抹杀、SQLite 资产库安全覆写
# ==========================================================

# ----------------------------------------------------------
# [权限鉴权] 防止非管理员误触导致中枢组件挂起或卸载不全
# ----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m❌ 权限被拒绝: 卸载 IP-Sentinel 需要最高系统权限。\033[0m"
  echo -e "💡 请切换到 root 用户 (执行 su root 或 sudo -i) 后重新运行指令。"
  exit 1
fi

MASTER_DIR="/opt/ip_sentinel_master"
CONF_FILE="${MASTER_DIR}/master.conf"

echo "========================================================"
echo "      🗑️ 准备卸载 IP-Sentinel Master (控制中枢)"

# [态势感知] 卸载前动态提取并播报当前中枢内核版本
if [ -f "$CONF_FILE" ]; then
    MASTER_VER=$(grep "^MASTER_VERSION=" "$CONF_FILE" | cut -d'"' -f2)
    [ -n "$MASTER_VER" ] && echo "        📍 目标版本: v${MASTER_VER}"
fi
echo "========================================================"

echo -e "\n⚠️ 警告: 此操作将永久删除包含所有节点档案的 SQLite 数据库！"
read -p "确定要继续卸载吗？(y/n) [默认 n]: " CONFIRM_DEL
if [[ ! "$CONFIRM_DEL" =~ ^[Yy]$ ]]; then
    echo "已取消卸载操作。"
    exit 0
fi

# ----------------------------------------------------------
# [进程抹杀] 阻塞并卸除底层 Systemd 强绑定服务单元
# ----------------------------------------------------------
echo "[1/4] 正在停止并删除 Systemd 服务..."
if command -v systemctl >/dev/null 2>&1; then
    echo "💡 检测到 Systemd 环境，正在抹除 Systemd 服务单元..."
    # 强制压制守护状态，发送 SIGKILL 剥夺其产生遗言及重启的机会
    systemctl kill --signal=SIGKILL ip-sentinel-master.service >/dev/null 2>&1 || true
    systemctl disable --now ip-sentinel-master.service >/dev/null 2>&1
    rm -f /etc/systemd/system/ip-sentinel-master.service
    systemctl daemon-reload
    systemctl reset-failed
else
    echo "💡 未检测到 Systemd，跳过此步骤..."
fi

# ----------------------------------------------------------
# [内存清洗] 全面追踪并镇压游离状态的中枢调度进程
# ----------------------------------------------------------
echo "[2/4] 正在终止后台中枢调度进程..."
pkill -9 -f "tg_master.sh" >/dev/null 2>&1 || true

# ----------------------------------------------------------
# [任务清洗] 基于内存管道流彻底擦除系统底层看门狗劫持
# ----------------------------------------------------------
echo "[3/4] 正在清理系统定时任务 (Cron)..."
# 内存管道流原位清洗，不留中间文件，免疫提权探测
crontab -l 2>/dev/null | grep -v "tg_master.sh" | crontab - >/dev/null 2>&1 || true

# ----------------------------------------------------------
# [物理销毁] 抹杀持久化特征，彻底销毁档案库与配置容器
# ----------------------------------------------------------
echo "[4/4] 正在抹除核心程序、配置文件与 SQLite 数据库..."
if [ -d "$MASTER_DIR" ]; then
    rm -rf "$MASTER_DIR"
fi

echo "========================================================"
echo "✅ 卸载彻底完成！Master 司令部已从您的系统中无痕移除。"
echo "========================================================"