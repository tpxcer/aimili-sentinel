# Aimili Sentinel

Aimili Sentinel 是一个合并仓库，包含两个互相独立的 VPS 网络工具模块：

- `aimili-vpngate/`：VPNGate/OpenVPN 代理网关与 Web 节点管理后台
- `ip-sentinel/`：VPS IP 质量检测、区域养护与 Telegram 私有 Master-Agent 管理

两个模块保持独立安装、独立服务名和独立运行目录，避免 root 级部署脚本互相覆盖。

## 一键安装

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/installer/install.sh)"
```

安装器会提供菜单：

- 安装 AimiliVPN Gateway
- 安装 IP-Sentinel Agent
- 安装 IP-Sentinel Master
- 依次安装 AimiliVPN Gateway 与 IP-Sentinel Agent

## 模块路径

AimiliVPN Gateway：

- 安装路径：`/opt/aimili-sentinel/aimili-vpngate`
- Web 后台默认端口：`8787`
- 本地代理默认端口：`7928`
- 管理命令：`ml`

IP-Sentinel：

- Agent 安装路径：`/opt/ip_sentinel`
- Master 安装路径：`/opt/ip_sentinel_master`

## 本次改版

- 合并 `aimili-vpngate` 与 `IP-Sentinel` 到一个仓库
- 删除第三方社群、广告、捐赠、公共网关推广、博客推广、装机量统计和 Star 引导
- AimiliVPN 节点后台增加 IP 类型筛选
- AimiliVPN 节点后台增加可用状态筛选
- AimiliVPN 节点后台增加连接延迟排序
- AimiliVPN 安装脚本适配合并仓库子目录
- IP-Sentinel 默认面向私有化 Master-Agent 部署

## 来源与许可证

本仓库组合了两个上游项目并做了本地化修改：

- `aimili-vpngate/` 基于 `baoweise-bot/aimili-vpngate`，按 GPLv3-or-later 处理
- `ip-sentinel/` 基于 `hotyue/IP-Sentinel`，按 AGPLv3 处理

许可证全文放在 `LICENSES/` 目录中。两个模块保持目录级隔离，便于分别遵守各自许可证要求。
