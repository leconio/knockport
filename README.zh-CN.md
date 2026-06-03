# KnockGate

[English](README.md)

## 这是做什么的

KnockGate 用 `knockd` 监听 UDP 顺序端口敲门，用 `nftables` timeout set 临时放行来源 IP。

它不会接管你原来的防火墙。它只创建自己的 `table inet knockgate`，并且只预先过滤你指定的保护 TCP 端口。其他端口继续保持原防火墙、云安全组和服务本身的行为。

这不是 VPN、代理、隧道或强认证系统。传统端口敲门可能被路径上的观察者重放，它适合减少普通公网扫描暴露，不应替代 SSH key、TLS、应用认证、VPN 或零信任访问控制。

## 工作原理

KnockGate 安装一个叠加保护层：

```nft
table inet knockgate {
    set knock_allow_temp_v4 {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

        ip saddr @knock_allow_temp_v4 tcp dport { PROTECTED_PORTS } accept
        tcp dport { PROTECTED_PORTS } drop
    }
}
```

UDP 敲门端口不在 `nftables` 中开放；`knockd` 通过抓包观察 UDP 包。

关键行为：

- 保护 TCP 端口默认被 KnockGate 丢弃；
- UDP 敲门成功后，来源 IP 被加入临时白名单；
- 其他流量不由 KnockGate 修改；
- 不重写 `/etc/nftables.conf`；
- 原防火墙规则和云安全组仍然生效。

## 推荐配置指南

把 KnockGate 当作已有防火墙前面的一层额外保护：

- SSH、Web、VPN 等公开端口继续由你原来的防火墙或云安全组管理；
- 保护服务端口应在原防火墙里本来可达，然后由 KnockGate 对未知来源隐藏；
- 不要在原防火墙里继续阻断保护端口，否则敲门后 KnockGate 也无法绕过原防火墙；
- UDP 敲门包必须能到达服务器路径。主机 `nftables` 不需要放行敲门端口，但云厂商防火墙不能在包到主机前就拦掉；
- 使用随机高位 UDP 敲门端口，并把导入二维码当作敏感信息保存。

例子：

- 原防火墙允许 SSH `22` 和应用端口 `5432`；
- KnockGate 保护 `5432`；
- 敲门前：`5432` 被 KnockGate 丢弃；
- 敲门后：客户端 IP 可以访问 `5432`，前提是原防火墙仍允许它通过。

## 环境要求

支持系统：

- Debian 11/12/13
- Ubuntu 20.04/22.04/24.04
- Rocky Linux 8/9
- AlmaLinux 8/9
- CentOS Stream 8/9
- Fedora 38+
- Arch Linux

依赖组件：

- `bash`
- `systemd`
- `nftables`
- `knockd`
- `iproute2`
- `qrencode`

脚本会在支持的发行版上尝试安装缺失依赖。`qrencode` 用于在终端生成客户端导入二维码。

## 文件

仓库文件：

- `knockgate.sh`：服务端安装和管理脚本
- `rfcjp-knock.sh`：客户端 UDP 敲门脚本
- `rfcjp-check.sh`：客户端 TCP 连通性检查脚本

安装后的服务端路径：

- `/usr/local/bin/knockgate`
- `/etc/knockgate/knockgate.conf`
- `/etc/knockgate/knockgate.nft`
- `/etc/knockgate/backups`
- `/etc/knockgate/README`
- `/etc/knockd.conf`
- `/etc/systemd/system/knockgate-nft.service`
- `/etc/systemd/system/knockd.service.d/override.conf`

## 安装

手动安装：

```bash
chmod +x knockgate.sh
sudo ./knockgate.sh
```

安装后运行：

```bash
sudo knockgate
```

一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport bash
```

客户端辅助脚本默认不会装到服务器。如需在客户端机器安装：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport INSTALL_CLIENT_HELPERS=1 bash
```

## 菜单

```text
KnockGate 管理器

1. 安装 / 修复
2. 更新配置
3. 重置端口和时间
4. 查看状态
5. 查看 knockd 日志
6. 查看临时白名单
7. 添加 IP 到临时白名单
8. 清空临时白名单
9. 重载 KnockGate 保护表
10. 卸载
11. 生成客户端导入二维码
12. 退出
```

## 客户端开锁

按 `knockgate` 显示的顺序发送 UDP 敲门：

```bash
./rfcjp-knock.sh SERVER_IP 38127 19452 47219 26083 50001 50002
```

等价手动命令：

```bash
printf knockgate | nc -u -w1 SERVER_IP 38127 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 19452 || true
```

敲门后检查保护 TCP 端口：

```bash
./rfcjp-check.sh SERVER_IP 5432
```

结果含义：

- `OPEN`：防火墙已放行，且有服务监听；
- `REFUSED`：路径已打开，但没有服务监听；
- `FILTERED`：仍被阻断，或网络路径过滤。

## 客户端导入 URL

菜单第 11 项会生成二维码，并在二维码下方显示协议 URL：

```text
knockgate://import/v1?host=SERVER_IP&scheme=udp&knock_ports=38127%2C19452%2C47219&protected_ports=5432&seq_timeout=10&open_timeout=12h&label=KnockGate
```

二维码包含 UDP 敲门顺序，请把它当作敏感信息，只分享给可信客户端。

## 卸载

卸载流程可以：

- 停止并禁用 `knockd`；
- 停止并禁用 `knockgate-nft.service`；
- 删除 live `inet knockgate` nft 表；
- 删除 KnockGate 自己的 nft 配置和 systemd 文件；
- 按需恢复 `knockd.conf` 备份；
- 删除 `/usr/local/bin/knockgate`；
- 可选删除 `/etc/knockgate`。

它不会恢复或重写 `/etc/nftables.conf`，因为 KnockGate 不修改这个文件。

## 协议

MIT License。详见 [LICENSE](LICENSE)。
