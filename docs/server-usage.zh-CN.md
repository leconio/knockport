# 服务端用法

本文只讲部署在被保护机器上的服务端。

## 服务端做什么

KnockGate Go 服务通过 libpcap 抓 UDP 敲门包。它不监听敲门端口。

客户端按顺序发送 UDP 包后，服务端只在序列完整时校验最后一个包里的 HMAC、timestamp 和 nonce。校验通过后，把来源 IPv4 加入 nftables timeout set。

加入白名单的来源 IP 可以访问配置的保护端口，直到 `open_timeout` 过期。

## 服务端不做什么

KnockGate 不接管 `/etc/nftables.conf`。

KnockGate 不修改 SSH 规则。

KnockGate 不再管理例外端口。

它只创建和管理：

```text
table inet knockgate
set knock_allow_temp_v4
```

只有保护端口会被 KnockGate 拦截。其他端口继续由你原来的防火墙、云防火墙、路由器或服务自身决定。

## 支持的服务端环境

安装脚本面向常见 systemd Linux 发行版：

```text
Debian 11/12/13
Ubuntu 20.04/22.04/24.04
Rocky Linux 8/9
AlmaLinux 8/9
CentOS Stream 8/9
Fedora 38+
Arch Linux
```

运行依赖：

```text
nftables
libpcap 运行库
iproute2
systemd
curl
tar
ca-certificates
```

`qrencode` 是可选依赖。没有它时，`knockgate qr` 仍会输出 URL，只是不显示终端二维码。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

如果服务器访问 GitHub 或软件源需要代理：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

服务端只有安装依赖、下载二进制、执行 `knockgate upgrade` 时需要访问公网。

正常敲门过程中，服务端不需要主动访问公网。

## 交互配置项

执行：

```bash
sudo knockgate install
```

需要确认或输入：

```text
保护端口
保护位置
UDP 敲门序列
开门时长
序列超时
timestamp/HMAC 容忍窗口
pcap 抓包网卡
是否重新生成 HMAC 密钥
```

保护端口格式：

```text
5432                  同时保护 5432/tcp 和 5432/udp
5432/tcp              只保护 TCP
5432/udp              只保护 UDP
5432/tcp,9092,10521/udp
```

敲门端口都是 UDP 端口。主机 nftables 不需要开放这些端口，但云防火墙或上游路由必须允许 UDP 敲门包到达服务器。

## 保护位置

默认是 `prerouting`。

`prerouting` 会在路由和 DNAT 前处理入站包，位置更靠前，适合公网入口、转发端口和 DNAT 场景。客户端敲门成功后，后续防火墙链、路由器、云防火墙和目标服务仍然必须允许该流量。

`input` 只影响发往本机服务的流量。它更保守，不覆盖转发和 DNAT 流量。

修改保护位置不会重写原防火墙，只会重建 KnockGate 自己的 table。

## 配置文件

主配置：

```text
/etc/knockgate/knockgate.conf
```

生成的 nft 文件：

```text
/etc/knockgate/knockgate.nft
/etc/knockgate/knockgate.apply.nft
```

systemd 服务：

```text
/etc/systemd/system/knockgate.service
```

优先使用 `sudo knockgate reset` 修改配置，不推荐手动编辑配置文件。配置里有 `SECRET`，应保持 root-only。

## 命令

打开菜单：

```bash
sudo knockgate
```

安装或修复：

```bash
sudo knockgate install
```

应用当前配置并重启服务：

```bash
sudo knockgate update
```

`update` 不会下载新版本，只是应用本机现有配置。

从 GitHub Release 下载最新服务端并重启：

```bash
sudo knockgate upgrade
```

升级到指定 tag：

```bash
sudo knockgate upgrade v0.1.14
```

重置保护端口、敲门序列、密钥和时间：

```bash
sudo knockgate reset
```

查看状态：

```bash
sudo knockgate status
```

查看日志：

```bash
sudo knockgate logs
sudo knockgate logs-follow
```

查看临时白名单：

```bash
sudo knockgate allowlist
```

手动放行 IPv4：

```bash
sudo knockgate allow 203.0.113.10
```

清空临时白名单：

```bash
sudo knockgate flush
```

重新加载 KnockGate nft 规则并保留白名单：

```bash
sudo knockgate reload
```

删除 KnockGate 的 nft table：

```bash
sudo knockgate clear
```

生成客户端导入 URL 和终端二维码：

```bash
sudo knockgate qr
```

卸载：

```bash
sudo knockgate uninstall
```

## 导入 URL

生成：

```bash
sudo knockgate qr
```

格式示例：

```text
knockgate://import/v1?scheme=udp-hmac&host=SERVER_HOST&knock_ports=58645%2C61037%2C57910%2C21030%2C26547%2C43223&protected_ports=5432%2Ftcp&protect_hook=prerouting&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=KnockGate
```

如果 `host=` 是内网或保留地址，请在外部客户端导入前改成公网 IP 或域名。

这个 URL 包含 HMAC 密钥，不要公开。

## 服务端验证

检查服务：

```bash
systemctl status knockgate.service --no-pager
```

检查 nft table：

```bash
sudo nft list table inet knockgate
```

检查临时白名单：

```bash
sudo nft list set inet knockgate knock_allow_temp_v4
```

敲门成功后，白名单里应该能看到来源 IP 和 timeout。

## 排查

敲门后没有白名单：

```bash
sudo knockgate logs
```

重点检查：

```text
客户端发的是 UDP，不是 TCP。
敲门端口和顺序与导入 URL 一致。
所有 UDP 敲门包都在 seq_timeout 内到达。
最后一个包的 HMAC 窗口有效。
客户端和服务端时间差没有超过 hmac_window。
服务端抓包网卡正确。
云防火墙或路由器允许 UDP 敲门包到达主机。
```

白名单里有 IP，但服务仍然连不上：

```text
原防火墙、云防火墙、路由器、DNAT 规则或服务监听状态仍可能阻断连接。
KnockGate 只取消自己对保护端口的 drop。
```

`input` 模式提示无法确认端口已开放：

```text
KnockGate 没能从现有 nft ruleset 里解析到明确 accept 规则。
如果端口通过 jump/goto、firewalld、ufw、iptables-nft、set 或云防火墙放行，可能误报。
想让 KnockGate 最先处理，使用 prerouting。
只想保护本机服务，使用 input。
```

二维码里的 host 是内网地址：

```text
把导入 URL 里的 host= 改成公网 IP 或域名后再给外部客户端使用。
```

## 安全说明

UDP-HMAC 敲门用于隐藏保护端口，减少普通扫描和未授权来源访问。

它不能替代服务认证、TLS、SSH key、数据库密码或应用权限控制。

客户端和服务端时间必须同步。最后一个敲门包包含 timestamp，超过 `hmac_window` 会被拒绝。
