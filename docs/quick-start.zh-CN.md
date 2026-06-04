# 快速开始

目标：服务端保护端口，客户端导入配置，敲门后检查端口。

## 1. 安装服务端

在 Linux 服务端执行：

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
```

如果服务器访问 GitHub 或软件源需要 HTTP / SOCKS 代理：

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

开始配置：

```bash
sudo knockgate install
```

第一次建议这样填：

```text
保护端口：5432/tcp
保护位置：prerouting
开门时长：12h
序列超时：10
HMAC 窗口：60
抓包网卡：直接回车使用自动检测值
```

保护端口格式：

```text
5432        同时保护 5432/tcp 和 5432/udp
5432/tcp    只保护 TCP
5432/udp    只保护 UDP
5432/tcp,9092/tcp,10521/udp
```

## 2. 获取导入 URL

在服务端执行：

```bash
sudo knockgate qr
```

复制输出里的 `knockgate://import/v1?...`。

如果 `host=` 是 `10.x`、`172.16-31.x`、`192.168.x` 这种内网地址，请把它改成客户端能访问到的公网 IP 或域名。

## 3. 下载 CLI 客户端

Linux x86_64 示例：

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
```

其他架构看 [CLI 客户端](cli-client.zh-CN.md)。

## 4. 敲门

在客户端执行：

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

客户端会按顺序发送 UDP 包，最后一个包携带 HMAC 校验。

## 5. 检查保护端口

敲门前：

```bash
./knockgate-client check SERVER_HOST 5432/tcp
```

敲门后：

```bash
./knockgate-client --url 'knockgate://import/v1?...' --check-ports 5432/tcp
```

结果含义：

```text
OPEN      端口已开，TCP 握手成功
REFUSED   端口已开到主机，但目标端口没有服务监听
FILTERED  端口未开，超时或被丢弃
UDP-SENT  UDP 包已发送，无法证明端口已开
FAILED    本地命令、DNS 或网络调用失败
```

## 6. 服务端检查

```bash
sudo knockgate status
sudo knockgate allowlist
sudo knockgate logs
```

清空临时白名单：

```bash
sudo knockgate flush
```

升级服务端二进制：

```bash
sudo knockgate upgrade
```

卸载：

```bash
sudo knockgate uninstall
```

## 7. 手机或桌面图形客户端

需要扫码导入和图形界面时，用 Flutter 客户端。

看 [Flutter 客户端](flutter-client.zh-CN.md)。
