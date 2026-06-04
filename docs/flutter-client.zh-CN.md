# Flutter 客户端

Flutter 客户端是 KnockGate 的图形客户端。

它支持导入配置、可用平台扫码、手动修改、一键 UDP-HMAC 敲门、端口检测、日志，以及可选的 App 打开时自动刷新。

## 支持平台

Release 会构建这些平台：

```text
Android
Windows
Linux
macOS
```

iOS 可以在配置好 Apple 开发环境后从源码构建。

扫码支持情况：

```text
Android    支持
iOS        本地构建并授权相机后支持
macOS      有相机权限时支持
Windows    手动导入 URL
Linux      手动导入 URL
```

## 下载

到最新 GitHub Release 下载对应平台客户端：

```text
knockgate_client_android.apk
knockgate_client_windows_x64.zip
knockgate_client_linux_x64.tar.gz
knockgate_client_macos.zip
```

## 导入配置

在服务端执行：

```bash
sudo knockgate qr
```

在 App 里：

```text
点击右上角菜单
选择 Import URL 或 Scan QR
粘贴或扫描 knockgate://import/v1?... URL
确认导入
```

导入后会保存到本地。下次启动 App 会自动读取上一次保存的配置。

如果 URL 里的 host 是内网地址，请把 host 字段改成当前设备能访问到的公网 IP 或域名。

## 配置字段

Knock 页字段：

```text
Name
Server host or IP
UDP knock ports
Seq timeout
HMAC window seconds
HMAC secret
```

Check 页字段：

```text
Server host or IP
Protected ports
```

保护端口格式：

```text
5432        UI 默认按 TCP 检测
5432/tcp    TCP 目标
5432/udp    UDP 目标，无法证明端口已开
5432/tcp,9092/tcp,10521/udp
```

修改字段后，下面的按钮会变成 Save。先保存，再 Knock 或 Check。

## Knock 页

点击 `Knock`。

App 会弹出黑色日志框，显示：

```text
host 解析
网络路径提示
UDP socket 状态
每一步敲门日志
最后一步 HMAC 包
成功或失败结果
```

最新日志在最上面。

成功后会显示成功提示，并在约 3 秒后自动收起。

失败后不会自动收起，方便查看错误。

也可以从右上角菜单打开日志框。

## Check 页

点击 `Check` 可以在不敲门的情况下检测保护端口。

TCP 结果含义：

```text
OPEN      端口已开，TCP 握手成功
REFUSED   端口已开到主机，但目标端口没有服务监听
FILTERED  端口未开，TCP 超时或被丢弃
FAILED    本地、DNS 或网络操作失败
```

UDP 普通发送无法证明端口已开。UDP 检测结果只能作为路径提示。

## 自动刷新

打开：

```text
右上角菜单
Settings
Auto refresh allowlist
```

开启后，App 每次打开时会检查：

```text
当前公网 IPv4
是否和上次保存的公网 IP 一致
上次成功敲门时间是否接近 open_timeout
只有 IP 变化或接近刷新时间才敲门
```

`open_timeout=12h` 时，大约会在上次成功敲门后 `11h55m` 刷新。

`open_timeout=0` 时，App 把服务端白名单视为永久，只在公网 IP 变化时刷新。

移动系统可能会挂起后台 App。这个功能是 App 打开时刷新，不是可靠的后台常驻服务。

如果需要路由器长期保持互通，用 OpenWrt 上的 CLI 客户端服务。

## 网络提示

App 会在这些情况提示：

```text
host 解析到内网、CGNAT、保留地址或 fake-IP
检测到 TUN/VPN 类网卡
```

提示不一定代表失败，只表示当前检测或敲门路径可能不是你以为的公网来源 IP。

如果服务端二维码里的 `host=` 是内网地址，在外网使用前先改成公网 IP 或域名。

## 时间同步

最后一个 UDP 敲门包包含 timestamp 和 HMAC。

服务端和客户端时间差必须在 `hmac_window` 内，通常是 60 秒。

如果顺序正确但服务端没有把 IP 加入白名单，先检查两端时间。

## 清空配置

右上角菜单可以清空本地保存的配置。

这只影响 App 本地，不会修改服务端。

## 从源码运行

安装 Flutter 后：

```bash
cd flutter
flutter pub get
flutter run
```

构建示例：

```bash
flutter build apk --release
flutter build macos --release
flutter build linux --release -t lib/main_no_scanner.dart
flutter build windows --release -t lib/main_no_scanner.dart
```

Windows 和 Linux 使用 `main_no_scanner.dart`，因为这些平台没有启用扫码插件入口。

## 什么时候用 CLI

这些场景用 CLI 客户端：

```text
路由器或 OpenWrt 常驻刷新
system service 模式
脚本化检测
无图形界面的机器
```

这些场景用 Flutter 客户端：

```text
手机手动开锁
二维码导入
桌面图形界面
快速可视化检测
```
