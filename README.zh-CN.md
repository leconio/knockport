# KnockGate

[English](README.md)

KnockGate 是一个 Linux 端口敲门服务。客户端按 UDP 端口顺序发送敲门包后，服务端会把通过校验的来源 IPv4 临时加入 `nftables` 白名单，从而放行指定的保护端口。

KnockGate 使用 `libpcap` 抓包，不监听敲门端口；使用 HMAC 校验最后一个敲门包；只管理自己的 `table inet knockgate`。它不会接管系统防火墙，不会重写 `/etc/nftables.conf`，也不会修改 SSH 规则。

## 功能

- UDP 顺序端口敲门
- 最后一步 `HMAC-SHA256 + timestamp + nonce` 校验
- 基于 `nftables` timeout set 的临时 IPv4 白名单
- 同一来源 IP 重复敲门成功会刷新白名单时间，不会产生重复条目
- 支持保护 TCP 和 UDP 端口
- 不重写 `/etc/nftables.conf`
- 不清空系统原防火墙规则
- 保护端口被主机防火墙拦截时，仍可通过敲门放行
- systemd 服务管理
- 终端二维码导入客户端配置
- 提供 Linux `amd64` / `arm64` 预编译产物

## 保护端口写法

```text
2345      同时保护 2345/tcp 和 2345/udp
2345/tcp  只保护 TCP
2345/udp  只保护 UDP
```

多个保护端口用英文逗号分隔：

```text
5432,9092/tcp,51820/udp
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

## Quick Start

服务器安装：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

按提示设置：

```text
保护端口：例如 5432,9092/tcp,51820/udp
敲门端口：直接使用随机生成的一组 UDP 端口，或手动输入
开门时长：默认 12h
网卡：默认自动检测
```

安装完成后生成客户端导入 URL / 二维码：

```bash
sudo knockgate qr
```

客户端下载 Shell 脚本：

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate-knock.sh
chmod +x knockgate-knock.sh
```

客户端敲门：

```bash
./knockgate-knock.sh --url 'knockgate://import/v1?...'
```

检查保护端口：

```bash
./knockgate-knock.sh check SERVER_IP 5432
./knockgate-knock.sh check SERVER_IP 5432/tcp 5432/udp
```

## 下载

Release 产物：

```text
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_arm64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate-knock.sh
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
sudo knockgate install       # 首次安装或修复
sudo knockgate reset         # 重置保护端口、敲门端口、密钥和时间
sudo knockgate update        # 应用当前保存的设置
sudo knockgate status        # 查看服务状态、规则、白名单和配置
sudo knockgate logs          # 查看最近日志
sudo knockgate logs-follow   # 跟随日志
sudo knockgate qr            # 输出客户端导入 URL / 二维码
sudo knockgate allow IP      # 手动临时放行一个 IPv4
sudo knockgate flush         # 清空临时白名单
sudo knockgate reload        # 重建 KnockGate 自己的 nft 表，会清空临时白名单
sudo knockgate clear         # 删除 table inet knockgate
sudo knockgate uninstall     # 卸载
```

## 配置管理

推荐使用交互菜单修改配置：

```bash
sudo knockgate reset
```

配置文件由 KnockGate 管理，通常不需要手动编辑。下面的路径和示例主要用于排查问题或备份记录。

配置文件路径：

```text
/etc/knockgate/knockgate.conf
```

示例内容：

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

如果确实手动改了配置文件，可以执行：

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

敲门端口不会在 nftables 中放行。服务端通过 pcap 从网卡读取 UDP 包，因此即使主机防火墙正在 drop 保护端口，KnockGate 仍然可以看到敲门包并完成放行。

上游防火墙不一样。云厂商安全组、机房防火墙或路由器必须允许 UDP 敲门包到达服务器。

## 客户端用法

在服务端生成导入 URL 和二维码：

```bash
sudo knockgate qr
```

使用仓库中的 Shell 客户端：

```bash
clients/shell/knockgate-knock.sh --url 'knockgate://import/v1?...'
clients/shell/knockgate-knock.sh --secret BASE64URL_SECRET --check-ports 5432 SERVER_IP 45669 65075 31244 20035 64168 59462
```

导入 URL 包含 `protected_ports`，所以 URL 模式敲门完成后会自动检测保护端口。手动 secret 模式提供 `--check-ports` 后也会在敲门完成后检测。

只检测，不敲门：

```bash
clients/shell/knockgate-knock.sh check SERVER_IP 5432
clients/shell/knockgate-knock.sh check SERVER_IP 5432/tcp 5432/udp
```

TCP 检查结果：

```text
OPEN      TCP 握手成功
REFUSED   主机可达，但端口没有服务监听
FILTERED  连接超时
```

UDP 没有通用可靠握手。客户端对 UDP 只能发送探测包，不能证明 UDP 端口已开放。

## Flutter 客户端

Flutter 客户端位于 [`flutter/`](flutter/)，支持导入 URL、Android/iOS/macOS 扫码、手动编辑配置、UDP-HMAC 敲门和连通性检查。

![KnockGate 展示图](docs/images/knockgate-hero.jpg)

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
