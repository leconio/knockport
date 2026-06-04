# CLI 客户端

CLI 客户端用于发送 UDP-HMAC 敲门序列、检测保护端口，也可以在 Linux、OpenWrt、华硕 Merlin 类设备上安装成自动刷新服务。

一次性敲门不需要 root。

安装自动刷新服务需要 root。

## 下载

按客户端机器架构下载 Release 产物：

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

Linux x86_64 示例：

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
./knockgate-client --help
```

OpenWrt 常见架构：

```text
aarch64 / arm64     knockgate_client_cli_linux_arm64.tar.gz
armv7 / armv7l      knockgate_client_cli_linux_armv7.tar.gz
armv6               knockgate_client_cli_linux_armv6.tar.gz
mipsel / mipsle     knockgate_client_cli_linux_mipsle_softfloat.tar.gz
mips                knockgate_client_cli_linux_mips_softfloat.tar.gz
x86_64              knockgate_client_cli_linux_amd64.tar.gz
i386 / i686         knockgate_client_cli_linux_386.tar.gz
```

## 获取导入 URL

在服务端执行：

```bash
sudo knockgate qr
```

复制 `knockgate://import/v1?...`。

如果 `host=` 是内网地址，请改成客户端能访问到的公网 IP 或域名。

这个 URL 包含 HMAC 密钥，不要公开。

## 一次性敲门

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

这个命令会：

```text
解析 host
如果 host 或路由看起来是内网、fake-IP、TUN、VPN、代理路径，会给出提示
按顺序发送 UDP 包
只在最后一个包里加入 HMAC
敲门后检测 URL 里的保护端口
```

只敲门，不检测端口：

```bash
./knockgate-client --url 'knockgate://import/v1?...' --no-check
```

自定义包间隔：

```bash
./knockgate-client --url 'knockgate://import/v1?...' --delay 0.35
```

默认间隔是 `0.25s`。整组敲门必须在服务端 `seq_timeout` 内完成，通常是 10 秒。

## 只检测，不敲门

检测 TCP：

```bash
./knockgate-client check SERVER_HOST 5432/tcp
```

检测多个目标：

```bash
./knockgate-client check SERVER_HOST 5432/tcp 9092/tcp 10521/udp
```

设置超时时间：

```bash
./knockgate-client check SERVER_HOST --timeout 5 5432/tcp
```

UDP 普通发送无法证明端口已开放。UDP 检测通常返回 `UDP-SENT`，只表示本地 UDP 包已发出。

## 结果含义

```text
OPEN      端口已开，TCP 握手成功
REFUSED   端口已开到主机，但目标端口没有服务监听
FILTERED  端口未开，TCP 超时或被丢弃
UDP-SENT  UDP 包已发送，无法判断端口是否已开
FAILED    本地命令、DNS 或网络调用失败
```

做防火墙测试时，`REFUSED` 表示路径已经打开。它和 `FILTERED` 不一样。

## 手动模式

不用导入 URL 时可以手动传 secret 和端口：

```bash
./knockgate-client --secret BASE64URL_SECRET SERVER_HOST 58645 61037 57910 21030 26547 43223
```

手动模式仍然发送 UDP-HMAC。secret 必须和服务端配置一致。

日常使用优先用导入 URL。

## 自动刷新服务

安装客户端服务：

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300
```

默认会自动识别宿主机：

```text
systemd       Linux 桌面或服务器
openwrt       OpenWrt procd
asus-merlin   华硕 Merlin / Entware 类 init
```

指定平台：

```bash
sudo ./knockgate-client install --platform openwrt --url 'knockgate://import/v1?...'
sudo ./knockgate-client install --platform systemd --url 'knockgate://import/v1?...'
sudo ./knockgate-client install --platform asus-merlin --url 'knockgate://import/v1?...'
```

自定义公网 IP 检测接口：

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --ip-check-url https://api.ipify.org \
  --ip-check-url https://checkip.amazonaws.com
```

逗号分隔写法：

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --ip-check-urls https://api.ipify.org,https://ifconfig.me/ip
```

服务模式下不做端口检测：

```bash
sudo ./knockgate-client install --url 'knockgate://import/v1?...' --no-check
```

## 自动刷新逻辑

服务会按 interval 检测当前公网 IPv4。

只有这些情况会敲门：

```text
当前公网 IP 变化
或本地没有成功敲门记录
或距离上次成功敲门已经接近 open_timeout
```

`open_timeout=12h` 时，服务大约会在上次成功敲门后 `11h55m` 刷新。

`open_timeout=0` 时，客户端把服务端白名单视为永久，只在公网 IP 变化时刷新。

如果当前地址不是公网 IPv4，或者到服务端的路由经过可疑 TUN/VPN 网卡，服务模式会跳过本轮，避免用错误来源地址刷新白名单。

## 服务命令

查看状态：

```bash
./knockgate-client status
```

查看日志：

```bash
./knockgate-client logs
```

卸载服务：

```bash
sudo ./knockgate-client uninstall
```

## 安装路径

systemd：

```text
/usr/local/bin/knockgate-client
/etc/knockgate-client/client.conf
/etc/knockgate-client/last_public_ip
/etc/knockgate-client/last_knock_unix
/etc/systemd/system/knockgate-client.service
```

OpenWrt：

```text
/usr/bin/knockgate-client
/etc/knockgate-client/client.conf
/etc/knockgate-client/last_public_ip
/etc/knockgate-client/last_knock_unix
/etc/init.d/knockgate-client
```

华硕 Merlin / Entware：

```text
/opt/bin/knockgate-client
/opt/etc/knockgate-client/client.conf
/opt/etc/knockgate-client/last_public_ip
/opt/etc/knockgate-client/last_knock_unix
/opt/etc/init.d/S99knockgate-client
/opt/var/log/knockgate-client.log
```

## 时间同步

最后一个 UDP 包会使用当前 Unix timestamp 参与 HMAC 签名。

服务端只接受 `hmac_window` 内的包，通常是 60 秒。

如果端口顺序正确但敲不开，先检查两端时间：

```bash
date -u
```

OpenWrt 安装常驻服务前，先确认 NTP 可用。

## OpenWrt

如果需要让整个内网在 WAN IP 变化后仍然自动保持访问，建议在 OpenWrt 上安装自动刷新服务。

完整指南：

[OpenWrt 保持互通指南](openwrt-keepalive.zh-CN.md)

## 常见问题

敲门后还是 `FILTERED`：

```text
可能没有加入白名单，也可能还有其他防火墙阻断。
看服务端日志和白名单。
```

敲门后是 `REFUSED`：

```text
防火墙路径已经打开，但目标 TCP 端口没有服务监听。
```

没有白名单记录：

```text
URL 错误、端口顺序错误、UDP 包被上游拦截、抓包网卡错误、时间漂移或 HMAC 密钥不一致。
```

服务一直跳过：

```text
检测到的当前 IP 不是公网 IP，或者去服务端的路由经过 TUN/VPN/代理路径。
需要修正路由，或使用能反映真实出口的公网 IP 检测接口。
```
