# AimiliVPN Gateway

AimiliVPN Gateway 是一个基于 VPNGate 与 OpenVPN 的轻量代理网关模块。它提供 Web 管理后台、节点测速、自动切换、本机 HTTP/SOCKS5 代理出口和运行状态自检。

## 功能

- VPNGate 节点拉取、测速与可用性检测
- Web 后台节点管理
- 国家、IP 类型、可用状态筛选
- 按连接延迟、评分或状态排序
- HTTP/SOCKS5 本地代理出口
- OpenVPN 连接状态与代理出口自检
- 终端菜单配置域名访问地址

## 部署

从合并项目根安装器安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/installer/install.sh)"
```

单独安装本模块：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/tpxcer/aimili-sentinel/main/aimili-vpngate/install.sh)"
```

安装后可使用 `ml` 命令进入本模块管理菜单。

常用命令：

- `ml web`：配置后台监听地址与安全后缀
- `ml domain`：配置域名访问地址
- `ml port`：配置 Web 后台端口与代理端口

反代模式：

- 推荐在 `ml domain` 中选择“反代 HTTPS”
- 反代上游指向：`http://127.0.0.1:8787`
- 外部访问地址形如：`https://vpn.example.com/安全后缀/`
- 反代需要保留原始路径，不要把安全后缀路径改写掉

Nginx 示例：

```nginx
location / {
    proxy_pass http://127.0.0.1:8787;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## 默认端口

- Web 管理后台：`8787`
- 本地 HTTP/SOCKS5 代理：`7928`

代理默认绑定 `127.0.0.1`，只接收 VPS 本机流量。需要公网访问时再修改监听地址和防火墙规则。

## 来源与许可证

本模块基于 `baoweise-bot/aimili-vpngate` 修改，保留原始 GPL 许可证约束。修改版删除了第三方推广内容，并调整了节点管理筛选与排序体验。
