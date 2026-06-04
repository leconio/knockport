# KnockGate

![KnockGate 标志](docs/images/knockgate-logo.jpg)

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
- 只叠加自己的保护端口 drop 规则，不接管系统其他防火墙规则
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
- `qrencode` 可选，用于终端二维码；缺失时安装不会中断

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

如果服务器访问软件源或 GitHub 需要 HTTP/SOCKS 代理，进入 `sudo` 时需要保留代理环境变量：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

`HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY` 会被 `curl` 等工具使用。不同发行版的软件包管理器可能还需要单独配置代理。

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

客户端下载 Go CLI。请按客户端机器架构选择对应产物：

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
```

客户端敲门：

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

检查保护端口：

```bash
./knockgate-client check SERVER_IP 5432
./knockgate-client check SERVER_IP 5432/tcp 5432/udp
```

## 下载

Release 产物：

```text
服务端：
https://github.com/leconio/knockport/releases/latest/download/knockgate_server_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_server_linux_arm64.tar.gz

Go CLI 客户端：
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_386.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_arm64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_armv7.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_armv6.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_mips_softfloat.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_mipsle_softfloat.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_mips64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_mips64le.tar.gz
```

服务端安装路径：

```text
/usr/local/bin/knockgate
/etc/knockgate/knockgate.conf
/etc/knockgate/knockgate.nft
/etc/knockgate/knockgate.apply.nft
/etc/systemd/system/knockgate.service
```

Go CLI 客户端会作为 Release 独立资产发布。它和服务端安装脚本分开，`install.sh` 不会把客户端安装到服务器。

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
sudo knockgate upgrade       # 拉取最新 GitHub Release 服务端并重启服务
sudo knockgate upgrade v0.1.9 # 拉取指定版本服务端并重启服务
sudo knockgate status        # 查看服务状态、规则、白名单和配置
sudo knockgate logs          # 查看最近日志
sudo knockgate logs-follow   # 跟随日志
sudo knockgate qr            # 输出客户端导入 URL / 二维码
sudo knockgate allow IP      # 手动临时放行一个 IPv4
sudo knockgate flush         # 清空临时白名单
sudo knockgate reload        # 重建 KnockGate 自己的 nft 规则，保留临时白名单
sudo knockgate clear         # 删除 table inet knockgate
sudo knockgate uninstall     # 卸载
```

`update` 不下载新版本，它只应用当前 `/etc/knockgate/knockgate.conf` 并重启服务。升级服务端二进制请使用 `upgrade`。

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
PROTECT_HOOK="prerouting"
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

默认情况下，KnockGate 会创建 `prerouting` hook，使用 `priority raw` 和 `policy accept`。这是入站流量最早的保护点，适合公网入口端口、DNAT 和转发端口。如果保护的是本机服务，可以在安装/重置时选择 `input`。

保护位置区别：

```text
prerouting  默认值；路由判断和 DNAT/转发处理前影响入站包
input       只影响最终发往本机服务的包
```

例如保护端口写 `2345` 时，规则效果为：

```nft
chain prerouting {
    type filter hook prerouting priority raw; policy accept;

    ip saddr @knock_allow_temp_v4 tcp dport 2345 accept
    tcp dport 2345 drop
    ip saddr @knock_allow_temp_v4 udp dport 2345 accept
    udp dport 2345 drop
}
```

敲门端口不会在 nftables 中放行。服务端通过 pcap 从网卡读取 UDP 包，因此即使保护端口当前正在被 drop，KnockGate 仍然可以看到敲门包并写入临时白名单。

KnockGate 的 allow 规则不是对所有主机防火墙规则的旁路。早期 hook 里的 `accept` 只是让包继续进入后续 hook。如果其他 nftables base chain、firewalld、ufw 或云厂商防火墙在 KnockGate accept 之后继续 drop 保护服务，连接仍然会失败。需要让原防火墙允许已经进入 KnockGate 临时白名单的流量，或者把该服务端口只交给 KnockGate 保护。

上游防火墙不一样。云厂商安全组、机房防火墙或路由器必须允许 UDP 敲门包到达服务器。

## 代理、TUN 和 fake-IP 说明

服务端只有在安装依赖和升级二进制时需要访问公网，例如 `install.sh` 安装依赖，或 `knockgate upgrade` 从 GitHub Release 下载产物。正常敲门过程中，服务端不需要主动访问公网。

导入 URL 里的 `host` 默认来自服务端本机自动检测。云服务器上这个值可能是 `10.x`、`172.16-31.x`、`192.168.x` 这类内网地址。KnockGate 会在这种情况下打印提示。如果客户端不在同一个内网，请在导入前把 URL 里的 `host=` 手动替换成公网 IP 或域名。

Go CLI 和 Flutter 客户端检测到内网、CGNAT、保留地址、fake-IP 地址段，例如 `198.18.0.0/15`，或检测到 TUN/VPN 类网卡时，会给出提示。一次性敲门不会因此中止；自动刷新服务模式下，Go CLI 会跳过本轮，因为当前公网地址或路由路径不可信。

## 客户端用法

在服务端生成导入 URL 和二维码：

```bash
sudo knockgate qr
```

### Go CLI 客户端

路由器、小内存 Linux 主机、OpenWrt、华硕梅林和官改固件，优先使用 Go CLI 客户端。它是静态二进制，目标设备不需要安装 Go、OpenSSL、curl、nc、bash 或 Python。

OpenWrt 常驻保活、procd 服务安装、公网 IP 刷新逻辑、时间同步、日志和故障排查，请看 [OpenWrt 保持互通指南](docs/openwrt-keepalive.zh-CN.md)。

从最新 Release 下载匹配架构的产物：

```text
knockgate_client_cli_linux_amd64.tar.gz
knockgate_client_cli_linux_386.tar.gz
knockgate_client_cli_linux_arm64.tar.gz
knockgate_client_cli_linux_armv7.tar.gz
knockgate_client_cli_linux_armv6.tar.gz
knockgate_client_cli_linux_mips_softfloat.tar.gz
knockgate_client_cli_linux_mipsle_softfloat.tar.gz
knockgate_client_cli_linux_mips64.tar.gz
knockgate_client_cli_linux_mips64le.tar.gz
```

常见选择：

```text
OpenWrt aarch64/Filogic/现代 ARM64      linux_arm64
OpenWrt ARMv7                           linux_armv7
较老 ARM 路由器                          linux_armv6
很多较老华硕/MIPS 路由器                 linux_mipsle_softfloat
x86 软路由                               linux_amd64 或 linux_386
```

一次性敲门：

```bash
./knockgate-client --url 'knockgate://import/v1?...'
./knockgate-client --secret BASE64URL_SECRET --check-ports 5432 SERVER_IP 45669 65075 31244 20035 64168 59462
```

只检测，不敲门：

```bash
./knockgate-client check SERVER_IP 5432
./knockgate-client check SERVER_IP 5432/tcp 5432/udp
```

把 Go CLI 安装成自动刷新服务：

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --ip-check-url http://api.ipify.org \
  --ip-check-url http://checkip.amazonaws.com
```

安装器会自动识别宿主机服务管理方式，只写入匹配的平台服务：

```text
systemd              /etc/systemd/system/knockgate-client.service
OpenWrt procd        /etc/init.d/knockgate-client
Asuswrt-Merlin       /opt/etc/init.d/S99knockgate-client，需要 Entware 风格 /opt 目录
```

服务会按间隔检测当前公网 IPv4，但不会每轮都敲门。只有公网 IP 变化，或者本地记录的上次成功敲门时间接近导入 URL 里的 `open_timeout` 时，才会重新敲门。例如 `open_timeout=12h` 时，客户端会在上次成功敲门后大约 11h55m 刷新一次。如果 `open_timeout=0`，客户端会把白名单视为永久，只在公网 IP 变化时重新敲门。

如果地址是内网、CGNAT、保留地址、fake-IP，或者到 KnockGate 服务端的路由走 TUN/VPN 类网卡，服务会记录 warning 并跳过本轮。

最后一个 UDP 敲门包会用当前 Unix 时间戳参与 HMAC 签名。服务端会按导入 URL 里的 `hmac_window` 校验，通常是 60 秒，所以客户端和服务端时间需要保持同步。

服务命令：

```bash
knockgate-client status
knockgate-client logs
sudo knockgate-client uninstall
```

TCP 检查结果：

```text
OPEN      端口已开：TCP 握手成功
REFUSED   端口已开：防火墙/网络路径已到主机，但服务未监听
FILTERED  端口未开：超时，通常是防火墙或网络丢弃
FAILED    未知状态：本地工具或网络命令失败
```

UDP 没有通用可靠握手。客户端对 UDP 只能发送探测包，不能证明 UDP 端口已开放。

## Flutter 客户端

Flutter 客户端位于 [`flutter/`](flutter/)，支持导入 URL、Android/iOS/macOS 扫码、手动编辑配置、UDP-HMAC 敲门、连通性检查，以及可选的 App 打开时自动刷新。自动刷新会根据当前公网 IP 和 `open_timeout` 判断是否需要重新敲门。

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
- 客户端和服务端时间需要同步。最后一个 HMAC 包包含当前 Unix 时间戳，超过配置的 `hmac_window`，通常是 60 秒，会被服务端拒绝。
- 云厂商安全组需要允许 UDP 敲门包到达服务器。
- 端口敲门不是 VPN，也不能替代服务自身的认证机制。

## 协议

MIT License。详见 [LICENSE](LICENSE)。
