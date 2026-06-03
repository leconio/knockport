# KnockGate

[English](README.md)

## 这是做什么的

KnockGate 用 `knockd` 监听 TCP 顺序端口敲门，用 `nftables` timeout set 临时放行来源 IP。

它的安全模型是：

- 接管入站防火墙规则；
- 默认丢弃所有入站流量；
- 保留当前防火墙已经放行的端口；
- 自动保留当前 SSH 端口，降低锁机风险；
- 用户指定保护端口，保护端口默认关闭；
- 敲门成功后，把来源 IP 加入 `nftables` set；
- 该 IP 可访问所有保护端口，直到超时过期；
- 也支持手动永久放行 IP，但会有显著警告和二次确认。

这不是 VPN、代理、隧道或强认证系统。传统端口敲门可能被路径上的观察者重放，它适合减少普通公网扫描暴露，不应替代 SSH key、TLS、应用认证、VPN 或零信任访问控制。

## 工作原理

KnockGate 生成完整 `nftables` 入站规则：

```nft
table inet knockgate {
    set knock_allow_temp_v4 {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority filter; policy drop;

        iif lo accept
        ct state established,related accept
        ip protocol icmp accept

        tcp dport { 当前防火墙已放行的 TCP 端口 } accept
        ip saddr @knock_allow_temp_v4 tcp dport { 保护端口 } accept
    }
}
```

敲门端口本身不需要在防火墙中开放。`knockd` 通过抓包看到 TCP SYN 包，所以敲门端口从外部看通常应该是 `closed`、`filtered` 或超时。

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

脚本会在支持的发行版上尝试安装缺失依赖。如果找不到 `knockd` 包，会明确报错并停止。

## 文件

仓库文件：

- `knockgate.sh`：服务端安装和管理脚本
- `rfcjp-knock.sh`：通用客户端敲门脚本
- `rfcjp-check.sh`：通用客户端 TCP 连通性检查脚本

安装后的服务端路径：

- `/usr/local/bin/knockgate`
- `/etc/knockgate/knockgate.conf`
- `/etc/knockgate/backups`
- `/etc/knockgate/README`
- `/etc/nftables.conf`
- `/etc/knockd.conf`
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

提交到 GitHub 后的一键安装命令模板：

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/knockgate.sh -o /tmp/knockgate.sh \
  && chmod +x /tmp/knockgate.sh \
  && sudo /tmp/knockgate.sh
```

把 `OWNER/REPO` 替换为你的 GitHub 仓库。

使用安装器脚本：

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sudo KNOCKGATE_REPO=OWNER/REPO bash
```

Fork 或自建 raw 文件地址时：

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sudo KNOCKGATE_RAW_BASE=https://raw.githubusercontent.com/OWNER/REPO/main bash
```

## 首次运行

启动时会先选择语言：

```text
1. 中文
2. English
```

也可以通过环境变量跳过语言选择：

```bash
sudo KNOCKGATE_LANG=zh knockgate
sudo KNOCKGATE_LANG=en knockgate
```

安装或重置时，KnockGate 会：

1. 检测当前 SSH 端口；
2. 读取当前防火墙中的 `accept` 规则；
3. 保留当前已放行的 TCP/UDP 端口；
4. 要求用户确认默认入站策略将变成 `DROP`；
5. 让用户输入保护端口；
6. 自动随机生成 6 个敲门端口；
7. 展示最终配置摘要；
8. 要求输入大写 `YES` 才真正应用。

随机敲门端口会避开：

- 当前防火墙常开 TCP/UDP 端口；
- 用户输入的保护端口；
- 当前系统已监听 TCP/UDP 端口；
- 敲门序列内部重复端口。

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
9. 恢复防火墙备份
10. 卸载
11. 测试配置
12. 退出
```

危险操作都会要求确认。应用防火墙、恢复备份、卸载、清空白名单、永久放行 IP 都需要显式确认。

## 客户端如何开锁

KnockGate 使用 TCP 敲门序列。客户端必须按服务器显示的顺序，对每个敲门端口发起 TCP 连接尝试。

规则：

- 使用 TCP，不是 UDP；
- 严格按顺序敲；
- 不要跳过端口；
- 不要乱序；
- 不要在序列中插入其他敲门端口；
- 必须在 `SEQ_TIMEOUT` 内完成整组序列；
- 建议端口之间间隔 `0.2s` 到 `0.5s`；
- 成功后，客户端来源 IP 会加入临时白名单；
- 该来源 IP 可访问所有保护端口，直到 `OPEN_TIMEOUT` 过期。

示例服务端摘要：

```text
敲门序列：38127 -> 19452 -> 47219 -> 26083 -> 50001 -> 50002
序列超时：10s
开门时长：12h
保护端口：5432,9092
```

使用仓库里的客户端脚本：

```bash
./rfcjp-knock.sh SERVER_IP 38127 19452 47219 26083 50001 50002
```

等价的手动 `nc` 命令：

```bash
nc -z -w1 SERVER_IP 38127 || true
sleep 0.25
nc -z -w1 SERVER_IP 19452 || true
sleep 0.25
nc -z -w1 SERVER_IP 47219 || true
sleep 0.25
nc -z -w1 SERVER_IP 26083 || true
sleep 0.25
nc -z -w1 SERVER_IP 50001 || true
sleep 0.25
nc -z -w1 SERVER_IP 50002 || true
```

敲门后测试保护端口：

```bash
./rfcjp-check.sh SERVER_IP 5432
```

结果含义：

- `OPEN`：防火墙已放行，且端口上有服务监听；
- `REFUSED`：防火墙已放行，但端口上没有服务监听；
- `FILTERED/TIMEOUT`：敲门没有成功放行，或网络路径在过滤。

如果失败，请检查：

- 端口顺序是否完全正确；
- 是否在 `SEQ_TIMEOUT` 内完成；
- 敲门和访问保护端口是否来自同一个公网来源 IP；
- 是否有代理、VPN、NAT 改变来源 IP；
- `knockd` 是否监听了正确网卡。

## 客户端辅助脚本

敲门：

```bash
./rfcjp-knock.sh SERVER_IP PORT1 PORT2 PORT3 PORT4 PORT5 PORT6
```

只检查连通性，不敲门：

```bash
./rfcjp-check.sh SERVER_IP
```

检查指定 TCP 端口：

```bash
./rfcjp-check.sh SERVER_IP 22 80 443 5432
```

覆盖默认检查端口：

```bash
SSH_PORT=2222 PROTECTED_PORT=5432 ORDINARY_PORT=15555 ./rfcjp-check.sh SERVER_IP
```

典型测试流程：

```bash
./rfcjp-check.sh SERVER_IP
./rfcjp-knock.sh SERVER_IP PORT1 PORT2 PORT3 PORT4 PORT5 PORT6
./rfcjp-check.sh SERVER_IP
```

## 手动白名单

菜单 `7` 可以手动放行 IP。

支持时长：

- `30s`
- `10m`
- `12h`
- `1d`
- `0` 表示永久放行

永久放行不会自动过期。KnockGate 会显示警告，并要求输入大写 `YES` 才会添加永久放行。

菜单 `6` 会显示：

- 放行 IP；
- 可访问的保护端口；
- 剩余时间；
- 原始 `nftables` set 输出。

## 备份和恢复

写入重要文件前，KnockGate 会在这里创建时间戳备份：

```text
/etc/knockgate/backups
```

备份内容包括：

- `/etc/nftables.conf`
- `/etc/knockd.conf`
- `/etc/default/knockd`
- systemd override
- live `nft list ruleset`

如果备份里包含 UFW 或 iptables-nft 兼容规则，直接 `nft -f` 可能失败。KnockGate 会在检测到 UFW 且配置存在时回退到：

```bash
nft flush ruleset
ufw --force reload
```

## 卸载

运行：

```bash
sudo knockgate
```

选择：

```text
10. 卸载
```

卸载流程可以：

- 停止并禁用 `knockd`；
- 删除 live `inet knockgate` nft 表；
- 恢复 `nftables.conf` 备份；
- 恢复 `knockd.conf` 备份；
- 删除 systemd override；
- 删除 `/usr/local/bin/knockgate`；
- 可选删除 `/etc/knockgate`。

## 安全提醒

- 应用前必须确认 SSH 仍然常开；
- 远程服务器请确保云厂商控制台/救援方式可用；
- 防火墙接管会重写 `/etc/nftables.conf`；
- 默认入站策略是 `DROP`；
- 敲门端口不在 nftables 里开放，`knockd` 通过抓包观察 TCP SYN；
- 当前版本以 IPv4 为主；
- 不要把端口敲门当作强认证机制。

## 协议

MIT License。详见 [LICENSE](LICENSE)。

---
