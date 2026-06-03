# KnockGate

[English](README.md)

## 这是做什么的

KnockGate 是一个 Go 编写的服务端工具：它使用 `libpcap` 在网卡上抓取 UDP 顺序敲门包，先按端口顺序推进状态，只在最后一步执行 `HMAC-SHA256 + timestamp + nonce` 校验，成功后把来源 IPv4 临时加入 `nftables` timeout set。

它不会监听敲门端口，不依赖 `knockd`，也不会接管你的原防火墙。KnockGate 只管理自己的 `table inet knockgate`，并只对你指定的保护端口和协议做预过滤。SSH 端口规则不读取、不询问、不修改。

保护端口写法：

- `2345`：同时保护 `2345/tcp` 和 `2345/udp`；
- `2345/tcp`：只保护 TCP；
- `2345/udp`：只保护 UDP。

这不是 VPN、代理或强认证系统。HMAC 能防止简单重放和伪造敲门包，但导入 URL/二维码里的 secret 必须保密。

## 工作原理

服务端：

- Go 进程以 systemd 服务运行：`/usr/local/bin/knockgate serve`
- 通过 libpcap 抓取目的端口属于敲门序列的 UDP 包；
- 前面的敲门包只检查端口顺序，不做 HMAC；
- 最后一个包校验 compact binary payload：`K1 + step + unix_timestamp + nonce + truncated_hmac`
- HMAC 输入：`K1 + udp_port + step + unix_timestamp + nonce`
- 按顺序完成所有端口后执行：
  `nft add element inet knockgate knock_allow_temp_v4 { IP timeout OPEN_TIMEOUT }`

防火墙叠加表：

```nft
table inet knockgate {
    set knock_allow_temp_v4 {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

        ip saddr @knock_allow_temp_v4 tcp dport { PROTECTED_TCP_PORTS } accept
        tcp dport { PROTECTED_TCP_PORTS } drop

        ip saddr @knock_allow_temp_v4 udp dport { PROTECTED_UDP_PORTS } accept
        udp dport { PROTECTED_UDP_PORTS } drop
    }
}
```

关键点：

- 不写 `/etc/nftables.conf`；
- 不 flush 系统原规则；
- 不管理 SSH 端口；
- 不安装或使用 `knockd`；
- HMAC 只在最后一步执行，避免公网噪声对每个敲门包都触发加密计算；
- 敲门端口不需要真正开放，但云厂商安全组必须允许 UDP 包到达主机，否则 pcap 看不到。

## 环境要求

运行依赖：

- Linux + systemd
- `nftables`
- `iproute2`
- `libpcap`
- `qrencode` 可选，用于终端二维码

一键安装会下载 GitHub Release 中已经编译好的 Linux 二进制产物，不在目标服务器上编译 Go。

- Debian/Ubuntu：`ca-certificates curl tar nftables iproute2 libpcap0.8 qrencode`
- RHEL/Rocky/Alma/Fedora：`ca-certificates curl tar nftables iproute libpcap qrencode`
- Arch：`ca-certificates curl tar nftables iproute2 libpcap qrencode`

## 文件

服务端：

- `cmd/knockgate`：Go 主入口
- `internal/config`：配置读写
- `internal/protocol`：HMAC payload 生成/校验
- `internal/knock`：libpcap 抓包和顺序状态机
- `internal/nft`：只管理 KnockGate 自己的 nft table
- `internal/system`：systemd 和依赖安装
- `install.sh`：一键下载 Release 产物并安装

安装后路径：

- `/usr/local/bin/knockgate`
- `/etc/knockgate/knockgate.conf`
- `/etc/knockgate/knockgate.nft`
- `/etc/systemd/system/knockgate.service`

## 安装

一键安装：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport bash
```

Release 产物下载地址：

```bash
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_arm64.tar.gz
```

安装后：

```bash
sudo knockgate
```

## 菜单

```text
KnockGate Manager

1. 安装 / 修复
2. 更新配置
3. 重置保护端口、敲门序列、密钥和时间
4. 查看状态
5. 查看日志
6. 查看临时白名单
7. 添加 IP 到临时白名单
8. 清空临时白名单
9. 重载 KnockGate 规则
10. 清空 KnockGate 防火墙表
11. 生成客户端导入二维码
12. 卸载
13. 退出
```

## 客户端开锁

使用导入 URL：

```bash
./rfcjp-knock.sh --url 'knockgate://import/v1?scheme=udp-hmac&host=SERVER_IP&knock_ports=37708%2C31114&protected_ports=5432&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=KnockGate'
```

或手动指定 secret：

```bash
./rfcjp-knock.sh --secret BASE64URL_SECRET SERVER_IP 37708 31114 25880 62009 61086 33854
```

敲门后检查保护端口：

```bash
./rfcjp-check.sh SERVER_IP 5432
./rfcjp-check.sh SERVER_IP 5432/tcp 5432/udp
```

结果含义：

- `OPEN`：TCP 握手成功；
- `REFUSED`：路径已打开，但端口没有服务监听；
- `FILTERED`：仍被防火墙或网络路径丢弃。
- `UDP-SENT`：UDP 没有可靠握手，只代表探测包已发出，不能证明端口开放。

## Flutter 客户端

[`flutter/`](flutter/) 是图形客户端，支持：

- 导入 `knockgate://` URL；
- Android/iOS/macOS 扫码导入；
- 手动修改服务器、敲门端口、保护端口、HMAC secret；
- 一键 UDP-HMAC 敲门；
- 检测保护 TCP 端口；UDP 只能发送探测包，不能像 TCP 一样确认握手。

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

## 卸载和清空

卸载：

```bash
sudo knockgate uninstall
```

只清空临时白名单：

```bash
sudo knockgate flush
```

只删除 KnockGate 自己的 nft table：

```bash
sudo knockgate clear
```

这些操作不会修改 SSH 端口规则，也不会恢复或重写 `/etc/nftables.conf`。

## 协议

MIT License。详见 [LICENSE](LICENSE)。
