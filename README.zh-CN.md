# KnockGate

[English](README.md)

KnockGate 是一个 Linux 端口敲门服务。客户端按 UDP 端口顺序发送敲门包后，服务端会把通过校验的来源 IPv4 临时加入 `nftables` 白名单，从而放行指定的保护端口。

KnockGate 使用 `libpcap` 抓包，不监听敲门端口；使用 HMAC 校验最后一个敲门包；只管理自己的 `table inet knockgate`。它不会接管系统防火墙，不会重写 `/etc/nftables.conf`，也不会修改 SSH 规则。

## 功能

- UDP 顺序端口敲门
- 最后一步 `HMAC-SHA256 + timestamp + nonce` 校验
- 基于 `nftables` timeout set 的临时 IPv4 白名单
- 支持保护 TCP 和 UDP 端口
- 不重写 `/etc/nftables.conf`
- 不清空系统原防火墙规则
- systemd 服务管理
- 终端二维码导入客户端配置
- 提供 Linux `amd64` / `arm64` 预编译产物

## 保护端口写法

```text
2345      同时保护 2345/tcp 和 2345/udp
2345/tcp  只保护 TCP
2345/udp  只保护 UDP
```

敲门端口固定使用 UDP。

## 环境要求

服务端：

- Linux + systemd
- `nftables`
- `iproute2`
- `libpcap`
- `qrencode` 可选，用于终端二维码

支持的发行版系列：

- Debian / Ubuntu
- RHEL 系：Rocky Linux、AlmaLinux、CentOS Stream、Fedora
- Arch Linux

一键安装脚本会下载 GitHub Release 中的预编译产物，不会在目标服务器上编译 Go。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

Release 产物：

```text
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_arm64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate-knock.sh
https://github.com/leconio/knockport/releases/latest/download/knockgate-check.sh
```

服务端安装路径：

```text
/usr/local/bin/knockgate
/etc/knockgate/knockgate.conf
/etc/knockgate/knockgate.nft
/etc/knockgate/knockgate.apply.nft
/etc/systemd/system/knockgate.service
```

Shell 客户端脚本会作为 Release 独立资产发布，仓库路径为 `clients/shell/`。`install.sh` 不会把它们安装到服务器。

## 服务端用法

交互菜单：

```bash
sudo knockgate
```

常用命令：

```bash
sudo knockgate install
sudo knockgate reset
sudo knockgate update
sudo knockgate status
sudo knockgate logs
sudo knockgate allow 203.0.113.10
sudo knockgate flush
sudo knockgate clear
sudo knockgate qr
sudo knockgate uninstall
```

## 配置文件

配置文件路径：

```text
/etc/knockgate/knockgate.conf
```

示例：

```bash
PROTECTED_PORTS="5432,9092/tcp,51820/udp"
KNOCK_PORTS="45669,65075,31244,20035,64168,59462"
OPEN_TIMEOUT="12h"
SEQ_TIMEOUT=10
HMAC_WINDOW=60
SECRET="base64url-secret"
INTERFACE="eth0"
MODE="go_hmac_pcap_overlay"
```

修改配置后应用：

```bash
sudo knockgate update
```

## 防火墙模型

KnockGate 只管理：

```text
table inet knockgate
```

这个表的 input hook 使用 `policy accept`，只对配置的保护端口做提前 drop。未匹配 KnockGate 规则的流量会继续走系统原有防火墙逻辑。

例如保护端口写 `2345` 时，规则效果为：

```nft
ip saddr @knock_allow_temp_v4 tcp dport 2345 accept
tcp dport 2345 drop
ip saddr @knock_allow_temp_v4 udp dport 2345 accept
udp dport 2345 drop
```

敲门端口不会在 nftables 中放行。服务端通过 pcap 从网卡读取 UDP 包。

## 客户端用法

在服务端生成导入 URL 和二维码：

```bash
sudo knockgate qr
```

使用仓库中的 Shell 客户端：

```bash
clients/shell/knockgate-knock.sh --url 'knockgate://import/v1?...'
clients/shell/knockgate-knock.sh --secret BASE64URL_SECRET SERVER_IP 45669 65075 31244 20035 64168 59462
```

检查保护端口：

```bash
clients/shell/knockgate-check.sh SERVER_IP 5432
clients/shell/knockgate-check.sh SERVER_IP 5432/tcp 5432/udp
```

TCP 检查结果：

```text
OPEN      TCP 握手成功
REFUSED   主机可达，但端口没有服务监听
FILTERED  连接超时
```

UDP 没有通用可靠握手。`knockgate-check.sh` 对 UDP 只能发送探测包，不能证明 UDP 端口已开放。

## Flutter 客户端

Flutter 客户端位于 [`flutter/`](flutter/)，支持导入 URL、Android/iOS/macOS 扫码、手动编辑配置、UDP-HMAC 敲门和连通性检查。

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
```

## 卸载

```bash
sudo knockgate uninstall
```

其他清理命令：

```bash
sudo knockgate flush   # 清空临时白名单
sudo knockgate clear   # 删除 table inet knockgate
```

## 安全说明

- 导入 URL 和 HMAC secret 必须保密。
- 客户端和服务端时间应保持基本同步。
- 云厂商安全组需要允许 UDP 敲门包到达服务器。
- 端口敲门不是 VPN，也不能替代服务自身的认证机制。

## 协议

MIT License。详见 [LICENSE](LICENSE)。
