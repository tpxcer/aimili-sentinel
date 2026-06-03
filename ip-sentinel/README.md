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

## 默认路径

- Agent：`/opt/ip_sentinel`
- Master：`/opt/ip_sentinel_master`

## 来源与许可证

本模块基于 `hotyue/IP-Sentinel` 修改，保留原始 AGPLv3 许可证约束。修改版删除了第三方推广、公共网关推广、外部博客引导和统计入口，默认面向私有化部署。
