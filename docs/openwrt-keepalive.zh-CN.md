# OpenWrt 客户端与 KnockGate Server 保持互通指南

这篇文档说明如何在 OpenWrt 路由器上运行 `knockgate-client`，让它在公网 IP 变化或服务端白名单快过期时自动重新敲门，从而保持 OpenWrt 当前出口公网 IP 能访问 KnockGate Server 上的保护端口。

## 适用场景

OpenWrt 适合做 KnockGate 客户端常驻点：

- 家宽公网 IP 会变化，需要自动刷新服务端 allowlist。
- 内网设备很多，希望由路由器统一敲门；服务端看到的是路由器出口公网 IP。
- 客户端设备可能是手机、电脑、NAS，但真正访问服务端的出口都经过 OpenWrt。
- 不希望在 OpenWrt 上安装 Go、Python、OpenSSL、bash、nc 等额外运行时。

`knockgate-client` 是静态 Go 二进制。它作为客户端运行时不管理 OpenWrt 防火墙，也不需要在 OpenWrt 上开放入站端口。

## 工作原理

OpenWrt 客户端服务会按固定间隔执行一次检查，默认 300 秒。

每次检查时：

1. 访问公网 IP 查询接口，得到 OpenWrt 当前出口 IPv4。
2. 读取本地记录的上次公网 IP 和上次成功敲门时间。
3. 按导入 URL 里的 `open_timeout` 判断是否需要刷新。
4. 只有满足条件时才发送 UDP-HMAC 敲门序列。
5. 敲门成功后，服务端把来源公网 IPv4 写入 nftables 临时白名单。
6. OpenWrt 后面的设备通过同一个公网出口访问保护端口时，会被服务端放行。

不会每个周期都敲门。刷新条件是：

- 当前公网 IP 与上次记录不同：立即敲门。
- 当前公网 IP 不变，但距离上次成功敲门已经接近 `open_timeout`：敲门刷新。
- `open_timeout=0`：视为永久白名单，只在公网 IP 变化时重新敲门。

例如 `open_timeout=12h` 时，客户端大约会在上次成功敲门后 `11h55m` 刷新一次。

## 前提条件

服务端需要已经安装并配置 KnockGate Server：

```bash
sudo knockgate
```

在服务端菜单中完成：

- 设置保护端口，例如 `5432` 或 `5432/tcp,8443/tcp`。
- 选择保护 hook，默认推荐 `prerouting`。
- 生成导入 URL：

```bash
sudo knockgate qr
```

导入 URL 类似：

```text
knockgate://import/v1?scheme=udp-hmac&host=SERVER_HOST&knock_ports=58645%2C61037%2C57910%2C21030%2C26547%2C43223&protected_ports=5432&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=KnockGate
```

需要重点确认：

- `host=` 应该是 OpenWrt 能访问到的服务端公网 IP 或域名。
- 如果服务端生成的是 `10.x`、`172.16-31.x`、`192.168.x` 这类内网地址，而 OpenWrt 不在同一个内网，请先把 `host=` 改成公网 IP 或域名。
- `secret=` 必须保密。拿到这个 URL 的人可以在有效时间窗口内敲门。
- 服务端和 OpenWrt 时间需要同步。最后一个 UDP 包带 HMAC 时间戳，服务端会按 `hmac_window` 校验，通常是 60 秒。

## 选择 OpenWrt 架构

在 OpenWrt 上查看架构：

```sh
uname -m
```

常见选择：

```text
aarch64 / arm64                    knockgate_client_cli_linux_arm64.tar.gz
armv7 / armv7l                     knockgate_client_cli_linux_armv7.tar.gz
armv6                              knockgate_client_cli_linux_armv6.tar.gz
mipsel / mipsle                    knockgate_client_cli_linux_mipsle_softfloat.tar.gz
mips                               knockgate_client_cli_linux_mips_softfloat.tar.gz
x86_64                             knockgate_client_cli_linux_amd64.tar.gz
i386 / i686                        knockgate_client_cli_linux_386.tar.gz
```

不确定时先用：

```sh
opkg print-architecture
```

## 安装方式一：在 OpenWrt 上下载

如果 OpenWrt 能访问 GitHub Release：

```sh
cd /tmp
wget -O knockgate-client.tar.gz \
  https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_arm64.tar.gz
tar -xzf knockgate-client.tar.gz
find /tmp -name knockgate-client -type f
```

把命令里的 `linux_arm64` 换成你的架构。

如果系统没有 `wget`，可以安装：

```sh
opkg update
opkg install wget-ssl ca-bundle
```

如果不想在 OpenWrt 上安装下载工具，使用下一种方式。

## 安装方式二：在电脑下载后 scp 到 OpenWrt

在电脑上下载匹配架构的包并解压：

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_arm64.tar.gz
tar -xzf knockgate_client_cli_linux_arm64.tar.gz
cd knockgate_client_cli_linux_arm64
scp knockgate-client root@192.168.1.1:/tmp/knockgate-client
```

在 OpenWrt 上检查：

```sh
chmod +x /tmp/knockgate-client
/tmp/knockgate-client --help
```

## 一次性敲门测试

先不要安装服务，先做一次手动敲门：

```sh
/tmp/knockgate-client --url 'knockgate://import/v1?...'
```

如果只想发送敲门包，不做保护端口检测：

```sh
/tmp/knockgate-client --url 'knockgate://import/v1?...' --no-check
```

正常输出会显示每一步 UDP 端口：

```text
UDP HMAC knocking SERVER_HOST: 58645 61037 57910 21030 26547 43223
  -> step 0 58645/udp
  -> step 1 61037/udp
  -> step 2 57910/udp
  -> step 3 21030/udp
  -> step 4 26547/udp
  -> step 5 43223/udp
Knock sent.
```

然后在服务端查看白名单：

```bash
sudo knockgate
# 选择 Show temporary allowlist
```

或直接：

```bash
sudo nft list set inet knockgate knock_allow_temp_v4
```

白名单中应该能看到 OpenWrt 当前出口公网 IPv4。

## 安装为 OpenWrt procd 服务

确认一次性敲门正常后，再安装服务：

```sh
/tmp/knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --platform openwrt \
  --ip-check-url http://api.ipify.org \
  --ip-check-url http://checkip.amazonaws.com \
  --no-check
```

参数说明：

- `--url`：服务端生成的导入 URL。
- `--interval 300`：每 300 秒检查一次公网 IP 和刷新时间。
- `--platform openwrt`：明确使用 OpenWrt procd，不依赖自动识别。
- `--ip-check-url`：公网 IP 查询接口。可以传多个，失败时尝试下一个。
- `--no-check`：服务模式中只负责敲门，不额外检测保护端口。路由器常驻建议加上，减少不必要连接。

安装后写入：

```text
/usr/bin/knockgate-client
/etc/init.d/knockgate-client
/etc/knockgate-client/client.conf
/etc/knockgate-client/last_public_ip
/etc/knockgate-client/last_knock_unix
```

不会修改 OpenWrt 防火墙。

## 服务管理

查看状态：

```sh
knockgate-client status
/etc/init.d/knockgate-client status
```

查看日志：

```sh
knockgate-client logs
logread -e knockgate-client
```

重启服务：

```sh
/etc/init.d/knockgate-client restart
```

停止服务：

```sh
/etc/init.d/knockgate-client stop
```

开机自启：

```sh
/etc/init.d/knockgate-client enable
```

取消开机自启：

```sh
/etc/init.d/knockgate-client disable
```

卸载：

```sh
knockgate-client uninstall
```

卸载会删除客户端二进制、procd 脚本和 `/etc/knockgate-client` 配置目录。

## 自动刷新日志怎么看

公网 IP 变化时：

```text
refresh knock: public IP changed: - -> 203.0.113.10
UDP HMAC knocking SERVER_HOST: ...
Knock sent.
```

公网 IP 没变且还没到刷新时间：

```text
skip knock: public IP unchanged (203.0.113.10), next refresh in about 11h54m53s
```

`open_timeout=0` 时：

```text
skip knock: public IP unchanged (203.0.113.10), open_timeout is permanent
```

公网 IP 检测失败：

```text
public IPv4 check failed: ...
```

服务端地址是内网、fake-IP 或路由走 TUN/VPN 时：

```text
skip knock: route to SERVER_HOST uses tun0
```

这种情况客户端会跳过本轮，因为它无法确认服务端看到的来源 IP 是否就是当前公网 IP。

## 时间同步

HMAC 校验依赖时间。OpenWrt 和服务端时间差超过 `hmac_window`，默认 60 秒，敲门会失败。

OpenWrt 通常使用 `sysntpd`：

```sh
/etc/init.d/sysntpd status
/etc/init.d/sysntpd enable
/etc/init.d/sysntpd restart
date
```

如果系统没有 NTP：

```sh
opkg update
opkg install busybox-ntpd
```

也可以在 LuCI 中检查：

```text
System -> System -> Time Synchronization
```

服务端也需要同步时间：

```bash
timedatectl
```

## 公网 IP 查询接口

OpenWrt 客户端需要知道当前出口公网 IPv4。默认会尝试多个接口，但路由器上经常缺 CA 证书，所以建议显式使用 HTTP 接口：

```sh
--ip-check-url http://api.ipify.org
--ip-check-url http://checkip.amazonaws.com
```

如果你有自己的公网 IP 回显服务，也可以使用：

```sh
--ip-check-url http://your-ip-service.example.com
```

返回内容中只要包含一个公网 IPv4 即可。

不要使用返回内网、CGNAT、保留地址或 fake-IP 的接口。客户端会拒绝这些结果。

## OpenWrt 后面的设备如何受益

如果 OpenWrt 是出口网关，服务端看到的来源 IP 是 OpenWrt 的公网出口 IP。

OpenWrt 敲门成功后：

- OpenWrt 自己访问保护端口会被放行。
- 同一个出口下的手机、电脑、NAS 访问保护端口也会被放行。
- 如果运营商重新分配公网 IP，OpenWrt 客户端会检测到 IP 变化并重新敲门。

如果某台设备走了其他代理、VPN、旁路由或 TUN 出口，它访问服务端时的来源 IP 可能不是 OpenWrt 的公网 IP。这种设备不会因为 OpenWrt 敲门而自动被放行。

## 服务端防火墙注意事项

KnockGate Server 只管理自己的 nftables 表：

```text
table inet knockgate
```

客户端敲门成功后，服务端会把来源 IPv4 写入：

```text
set knock_allow_temp_v4
```

如果服务端还有其他防火墙，例如 firewalld、ufw、云厂商安全组或额外 nftables base chain，KnockGate 的 allowlist 可能不是最后一关。

现象：

- 服务端白名单里已经有 OpenWrt 公网 IP。
- 但保护端口仍然无法连接。

这通常说明后续防火墙或云安全组仍在拦截。需要让原防火墙允许该保护端口通过，或者把该端口完全交给 KnockGate 管理。

## 推荐配置

服务端：

```text
protected_ports=5432/tcp
protect_hook=prerouting
open_timeout=12h
seq_timeout=10
hmac_window=60
```

OpenWrt 客户端：

```sh
knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --platform openwrt \
  --ip-check-url http://api.ipify.org \
  --ip-check-url http://checkip.amazonaws.com \
  --no-check
```

时间同步：

```sh
/etc/init.d/sysntpd enable
/etc/init.d/sysntpd restart
```

## 故障排查

### 1. 服务没有运行

```sh
/etc/init.d/knockgate-client status
logread -e knockgate-client
```

如果没有 `/etc/init.d/knockgate-client`，说明没有安装服务或卸载过。

### 2. 能敲门但服务端白名单没有 IP

检查：

- 导入 URL 的 `host=` 是否是服务端公网 IP 或域名。
- OpenWrt 到服务端 UDP 敲门端口是否能出站。
- 服务端 `knockgate` 服务是否运行。
- 服务端和 OpenWrt 时间是否同步。
- `secret` 是否和服务端当前配置一致。
- 是否把旧 URL 导入到了客户端。

服务端查看日志：

```bash
sudo journalctl -u knockgate -n 100 --no-pager
```

### 3. 白名单有 IP，但端口还是不通

检查：

- 服务端保护端口是否真的有服务监听。
- 云厂商安全组是否允许该端口。
- 服务端是否还有其他 nftables/firewalld/ufw 规则继续 drop。
- KnockGate 的保护 hook 是否适合当前流量路径，默认推荐 `prerouting`。

### 4. 日志提示 TUN/VPN/fake-IP

如果 OpenWrt 上运行了代理、透明代理、fake-IP DNS、Tailscale、WireGuard、OpenVPN、ZeroTier 等，客户端可能检测到当前路径不可信。

解决方向：

- 确认访问 KnockGate Server 的路由是否走真实 WAN。
- 对服务端 IP 或域名配置直连规则。
- 如果使用 fake-IP DNS，把服务端域名加入真实解析或直连列表。
- 重新运行 `knockgate-client logs` 查看是否还跳过。

### 5. 公网 IP 检测失败

先手动测试：

```sh
wget -qO- http://api.ipify.org
wget -qO- http://checkip.amazonaws.com
```

如果失败：

- 检查 OpenWrt DNS。
- 检查 WAN 是否联网。
- 换一个 `--ip-check-url`。
- 如果只 HTTPS 失败，安装 `ca-bundle` 或改用 HTTP IP 查询接口。

### 6. 重新生成了服务端 URL

如果服务端 reset/reinstall 后重新生成了 `secret` 或敲门端口，OpenWrt 旧配置会失效。

重新安装客户端服务：

```sh
knockgate-client uninstall
/tmp/knockgate-client install \
  --url '新的 knockgate://import/v1?...' \
  --interval 300 \
  --platform openwrt \
  --ip-check-url http://api.ipify.org \
  --ip-check-url http://checkip.amazonaws.com \
  --no-check
```

## 安全边界

KnockGate 适合减少公网扫描噪声，不是强认证系统。

需要注意：

- 导入 URL 等同于客户端凭据，里面包含 HMAC secret。
- UDP 敲门序列可以被旁路观察；最后一个包有 HMAC、timestamp、nonce，不能简单重放过期包。
- 时间窗口越大，容忍时钟漂移越多，但重放窗口也越大。
- 保护端口上的应用仍然应该有自己的认证、TLS、密码或密钥机制。
- 云安全组和服务端防火墙要一起核对，不要只看 KnockGate allowlist。
