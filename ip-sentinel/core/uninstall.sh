#!/bin/bash

# ==========================================================
# 脚本名称: uninstall.sh
# 核心功能: 无痕追踪溯源、全面抹杀幽灵进程、清空宿主脏数据残留与防火墙回缩
# ==========================================================

# ----------------------------------------------------------
# [权限鉴权] 防止非管理员误触导致组件残留挂起
# ----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[31m❌ 权限被拒绝: 卸载 IP-Sentinel 需要最高系统权限。\033[0m"
  echo -e "💡 请切换到 root 用户 (执行 su root 或 sudo -i) 后重新运行指令。"
  exit 1
fi

INSTALL_DIR="/opt/ip_sentinel"
CONFIG_FILE="${INSTALL_DIR}/config.conf"

echo "========================================================"
echo "      🗑️ 准备卸载 IP-Sentinel (边缘节点 Edge Agent)"

if [ -f "$CONFIG_FILE" ]; then
    CURRENT_VER=$(grep "^AGENT_VERSION=" "$CONFIG_FILE" | cut -d'"' -f2)
    [ -n "$CURRENT_VER" ] && echo "        📍 目标版本: v${CURRENT_VER}"
fi
echo "========================================================"

# ----------------------------------------------------------
# [进程抹杀] 阻塞并卸除底层 Systemd 强绑定服务单元
# ----------------------------------------------------------
echo "[1/5] 正在停止并删除 Systemd 服务..."
if command -v systemctl >/dev/null 2>&1; then
    echo "💡 检测到 Systemd 环境，正在抹除 Systemd 服务单元..."
    # 强制压制守护状态，发送 SIGKILL 剥夺其产生遗言及重启的机会
    systemctl kill --signal=SIGKILL ip-sentinel-agent-daemon.service >/dev/null 2>&1 || true
    systemctl disable --now ip-sentinel-runner.service ip-sentinel-runner.timer \
        ip-sentinel-updater.service ip-sentinel-updater.timer \
        ip-sentinel-report.service ip-sentinel-report.timer \
        ip-sentinel-agent-daemon.service >/dev/null 2>&1
    rm -f /etc/systemd/system/ip-sentinel-runner.service
    rm -f /etc/systemd/system/ip-sentinel-runner.timer
    rm -f /etc/systemd/system/ip-sentinel-updater.service
    rm -f /etc/systemd/system/ip-sentinel-updater.timer
    rm -f /etc/systemd/system/ip-sentinel-report.service
    rm -f /etc/systemd/system/ip-sentinel-report.timer
    rm -f /etc/systemd/system/ip-sentinel-agent-daemon.service
    systemctl daemon-reload
    systemctl reset-failed
else
    echo "💡 未检测到 Systemd，跳过此步骤..."
fi

# ----------------------------------------------------------
# [内存清洗] 全面追踪并镇压游离状态的挂起业务逻辑
# ----------------------------------------------------------
echo "[2/5] 正在终止后台守护进程与所有养护任务..."
pkill -9 -f "tg_daemon.sh" >/dev/null 2>&1
pkill -9 -f "agent_daemon.sh" >/dev/null 2>&1
pkill -9 -f "python3.*webhook.py" >/dev/null 2>&1
pkill -9 -f "webhook.py" >/dev/null 2>&1
pkill -9 -f "runner.sh" >/dev/null 2>&1
pkill -9 -f "updater.sh" >/dev/null 2>&1
pkill -9 -f "tg_report.sh" >/dev/null 2>&1
pkill -9 -f "mod_google.sh" >/dev/null 2>&1
pkill -9 -f "mod_trust.sh" >/dev/null 2>&1
pkill -9 -f "sentinel_scheduler.sh" >/dev/null 2>&1

# ----------------------------------------------------------
# [任务清洗] 基于内存管道流彻底擦除系统底层调度劫持
# ----------------------------------------------------------
echo "[3/5] 正在清理系统定时任务 (Cron)..."
# 通过管道原位清洗避免落地到 /tmp，免疫提权或外部劫持探测
crontab -l 2>/dev/null | grep -v "ip_sentinel" | crontab - >/dev/null 2>&1 || true

# 扫除高受限环境 (如 Alpine) 中的额外触发隐患
for CRON_FILE in "/var/spool/cron/crontabs/root" "/etc/crontabs/root"; do
    if [ -f "$CRON_FILE" ]; then
        grep -v "ip_sentinel" "$CRON_FILE" > "${CRON_FILE}.tmp" 2>/dev/null || true
        cat "${CRON_FILE}.tmp" > "$CRON_FILE" 2>/dev/null || true
        rm -f "${CRON_FILE}.tmp" 2>/dev/null
    fi
done
rm -f /etc/local.d/ip_sentinel.start 2>/dev/null
rm -f /etc/local.d/ip_sentinel_scheduler.start 2>/dev/null

if grep -q "sentinel_scheduler.sh" /etc/profile 2>/dev/null; then
    sed -i '/sentinel_scheduler\.sh/d' /etc/profile 2>/dev/null || true
fi

# ----------------------------------------------------------
# [防线回缩] 读取遗留端口，撤除自动化防火墙挂载点
# ----------------------------------------------------------
echo "[4/5] 正在执行本地防火墙撤防操作..."
if [ -f "$CONFIG_FILE" ]; then
    AGENT_PORT=$(grep "^AGENT_PORT=" "$CONFIG_FILE" | cut -d'"' -f2)
    if [ -n "$AGENT_PORT" ]; then
        if command -v ufw >/dev/null 2>&1 && ufw status | grep -qw active; then
            ufw delete allow "$AGENT_PORT"/tcp >/dev/null 2>&1
            echo -e " ✅ \033[32mUFW 防火墙双栈撤防成功 (剔除端口: $AGENT_PORT)。\033[0m"
        elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld | grep -qw active; then
            firewall-cmd --zone=public --remove-port="$AGENT_PORT"/tcp --permanent >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            echo -e " ✅ \033[32mFirewalld 持久化拦截规则回缩完毕。\033[0m"
        else
            local fw_removed=false
            if command -v iptables >/dev/null 2>&1; then
                # 循环清洗，防备由于中途故障引发的复数规则残留
                while iptables -C INPUT -p tcp --dport "$AGENT_PORT" -j ACCEPT >/dev/null 2>&1; do
                    iptables -D INPUT -p tcp --dport "$AGENT_PORT" -j ACCEPT
                    fw_removed=true
                done
            fi
            if command -v ip6tables >/dev/null 2>&1; then
                while ip6tables -C INPUT -p tcp --dport "$AGENT_PORT" -j ACCEPT >/dev/null 2>&1; do
                    ip6tables -D INPUT -p tcp --dport "$AGENT_PORT" -j ACCEPT
                    fw_removed=true
                done
            fi
            
            if [ "$fw_removed" = true ]; then
                echo -e " ✅ \033[32m原生 iptables/ip6tables 双轨锚点清理完毕。\033[0m"
            else
                echo -e " 💡 \033[33m未检测到残留底层拦截规则，防线保持默认流转。\033[0m"
            fi
        fi
    else
        echo " 💡 未在主核配置内探测到通讯端口配置，跳过清理..."
    fi
else
    echo " 💡 核心配置文件丢失，未能追溯部署端口状态，放弃网络防御清洗。"
fi

# ----------------------------------------------------------
# [物理销毁] 抹杀持久化特征，销毁系统沙盒痕迹
# ----------------------------------------------------------
echo "[5/5] 正在抹除核心程序、配置文件与系统痕迹..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
fi

echo "========================================================"
echo "✅ 卸载彻底完成！IP-Sentinel 引擎及对空信道已从您的系统中无痕移除。"
echo "💡 提示：如果此前云端控制面板 (如 AWS/阿里云等) 配有入站安全组例外，请手动阻断以确保靶机零敞露。"
echo "👋 感谢您的使用，期待未来再次为您守护资产！"
echo "========================================================"
