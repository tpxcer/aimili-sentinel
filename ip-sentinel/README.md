# IP-Sentinel

IP-Sentinel 是一个 VPS IP 质量检测与区域养护模块，包含 Agent 与 Master 两种角色。Agent 在目标 VPS 上定时执行 IP 质量、Google 区域、可信站点等检测；Master 通过 Telegram Bot 管理多台 Agent。

## 功能

- Agent 定时巡检
- Master-Agent 管理模式
- Telegram 私有机器人控制
- IP 质量检测与历史趋势记录
- 国家/地区关键词与本土站点数据
- OTA 更新能力

## 部署

从合并项目根安装器安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/installer/install.sh)"
```

单独部署 Agent：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/ip-sentinel/install.sh)"
```

单独部署 Master：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/ip-sentinel/master/install_master.sh)"
```

## 配置流程

IP-Sentinel 分为两个角色：

- Master：Telegram 私有机器人控制端，用于管理多台 Agent
- Agent：部署在 VPS 上的检测节点，用于执行 IP 质量、Google 区域、可信站点和趋势巡检

推荐顺序：

1. 先部署 Master
2. 再部署一台或多台 Agent

只想检测当前 VPS 时，也可以只部署 Agent。

### Master 配置

运行 Master 安装命令后，按提示填写：

- Telegram Bot Token
- 是否允许司令部接收 OTA 重构指令，建议默认 `y`
- 司令部展示别名，例如 `台湾主控`

Master 服务命令：

```bash
systemctl restart ip-sentinel-master.service
systemctl status ip-sentinel-master.service --no-pager
```

Master 配置文件：

```bash
/opt/ip_sentinel_master/master.conf
```

### Agent 配置

运行 Agent 安装命令后，按提示填写：

- 操作选择：选择部署边缘节点
- 目标地区：洲、国家、省/州、城市
- 是否接入 Master，建议 `y`
- Telegram Bot Token
- 是否允许 OTA，建议 `y`
- Telegram Chat ID
- Webhook 监听端口，通常直接回车使用推荐端口
- 公网 IP，自动检测正确时直接使用；检测错误时手动填写
- 节点展示别名，例如 `台湾节点`

Agent 配置文件：

```bash
/opt/ip_sentinel/config.conf
```

Agent 服务命令：

```bash
systemctl restart ip-sentinel-agent-daemon.service
systemctl restart ip-sentinel-runner.timer ip-sentinel-updater.timer ip-sentinel-report.timer
systemctl status ip-sentinel-agent-daemon.service --no-pager
systemctl list-timers | grep ip-sentinel
```

手动执行一次检测：

```bash
bash /opt/ip_sentinel/core/runner.sh
```

重新配置 Agent：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/ip-sentinel/install.sh)"
```

当安装器提示是否按原配置平滑升级时选择 `n`，即可重新进入配置流程。

## 默认路径

- Agent：`/opt/ip_sentinel`
- Master：`/opt/ip_sentinel_master`

## 来源与许可证

本模块基于 `hotyue/IP-Sentinel` 修改，保留原始 AGPLv3 许可证约束。修改版删除了第三方推广、公共网关推广、外部博客引导和统计入口，默认面向私有化部署。
