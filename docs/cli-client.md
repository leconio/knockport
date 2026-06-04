# CLI Client

The CLI client sends UDP-HMAC knock sequences, checks protected ports, and can run as an auto-refresh service on Linux, OpenWrt, and ASUS Merlin style hosts.

One-shot knocking does not require root.

Installing the auto-refresh service requires root.

## Download

Download a Release asset that matches the client machine:

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

Linux x86_64 example:

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
./knockgate-client --help
```

OpenWrt examples:

```text
aarch64 / arm64     knockgate_client_cli_linux_arm64.tar.gz
armv7 / armv7l      knockgate_client_cli_linux_armv7.tar.gz
armv6               knockgate_client_cli_linux_armv6.tar.gz
mipsel / mipsle     knockgate_client_cli_linux_mipsle_softfloat.tar.gz
mips                knockgate_client_cli_linux_mips_softfloat.tar.gz
x86_64              knockgate_client_cli_linux_amd64.tar.gz
i386 / i686         knockgate_client_cli_linux_386.tar.gz
```

## Get an import URL

On the server:

```bash
sudo knockgate qr
```

Copy the `knockgate://import/v1?...` URL.

If `host=` is private, replace it with the public IP or domain reachable from the client.

Keep the URL private. It contains the HMAC secret.

## One-shot knock

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

This command:

```text
resolves the host
warns if the host or route looks like private, fake-IP, TUN, VPN, or proxy routing
sends UDP packets in order
signs only the final packet with HMAC
checks protected ports from the URL after knocking
```

Disable the post-knock check:

```bash
./knockgate-client --url 'knockgate://import/v1?...' --no-check
```

Use a custom packet delay:

```bash
./knockgate-client --url 'knockgate://import/v1?...' --delay 0.35
```

The default delay is `0.25s`. Keep the total sequence inside the server `seq_timeout`, usually 10 seconds.

## Check without knocking

Check TCP:

```bash
./knockgate-client check SERVER_HOST 5432/tcp
```

Check multiple targets:

```bash
./knockgate-client check SERVER_HOST 5432/tcp 9092/tcp 10521/udp
```

Set timeout:

```bash
./knockgate-client check SERVER_HOST --timeout 5 5432/tcp
```

UDP cannot prove that a port is open with a normal client-side send. UDP checks return `UDP-SENT` unless the local send fails.

## Result meanings

```text
OPEN      port is open, TCP handshake succeeded
REFUSED   port is open through firewall, but no service is listening
FILTERED  port is not open, TCP timed out or was dropped
UDP-SENT  UDP packet was sent, open state is unknown
FAILED    local command, DNS, or network operation failed
```

For firewall testing, `REFUSED` means KnockGate opened the path. It is different from `FILTERED`.

## Manual mode

Manual mode is useful for debugging without an import URL:

```bash
./knockgate-client --secret BASE64URL_SECRET SERVER_HOST 58645 61037 57910 21030 26547 43223
```

Manual mode still sends UDP-HMAC. The secret must be the same as the server config.

Prefer the import URL for normal use.

## Auto-refresh service

Install a client-side service:

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300
```

The service detects the host type by default:

```text
systemd       Linux desktop/server
openwrt       OpenWrt procd
asus-merlin   ASUS Merlin / Entware style init
```

Force a platform:

```bash
sudo ./knockgate-client install --platform openwrt --url 'knockgate://import/v1?...'
sudo ./knockgate-client install --platform systemd --url 'knockgate://import/v1?...'
sudo ./knockgate-client install --platform asus-merlin --url 'knockgate://import/v1?...'
```

Custom public-IP endpoint:

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --ip-check-url https://api.ipify.org \
  --ip-check-url https://checkip.amazonaws.com
```

Comma-separated endpoint form:

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --ip-check-urls https://api.ipify.org,https://ifconfig.me/ip
```

Skip post-knock port checks in service mode:

```bash
sudo ./knockgate-client install --url 'knockgate://import/v1?...' --no-check
```

## Auto-refresh behavior

The service checks the current public IPv4 every interval.

It knocks only when:

```text
current public IP changed
or no previous successful knock is recorded
or local refresh time is close to open_timeout
```

With `open_timeout=12h`, the service refreshes around `11h55m` after the previous successful knock.

With `open_timeout=0`, the service treats the server allowlist as permanent and refreshes only when the public IP changes.

If the current address is not public IPv4, or the route to the server uses a suspicious TUN/VPN interface, service mode skips that round. This avoids refreshing the allowlist with the wrong source address.

## Service commands

Status:

```bash
./knockgate-client status
```

Logs:

```bash
./knockgate-client logs
```

Uninstall service:

```bash
sudo ./knockgate-client uninstall
```

## Installed paths

systemd:

```text
/usr/local/bin/knockgate-client
/etc/knockgate-client/client.conf
/etc/knockgate-client/last_public_ip
/etc/knockgate-client/last_knock_unix
/etc/systemd/system/knockgate-client.service
```

OpenWrt:

```text
/usr/bin/knockgate-client
/etc/knockgate-client/client.conf
/etc/knockgate-client/last_public_ip
/etc/knockgate-client/last_knock_unix
/etc/init.d/knockgate-client
```

ASUS Merlin / Entware:

```text
/opt/bin/knockgate-client
/opt/etc/knockgate-client/client.conf
/opt/etc/knockgate-client/last_public_ip
/opt/etc/knockgate-client/last_knock_unix
/opt/etc/init.d/S99knockgate-client
/opt/var/log/knockgate-client.log
```

## Time sync

The final UDP packet is signed with the current Unix timestamp.

The server accepts it only inside `hmac_window`, usually 60 seconds.

If knocking fails but the sequence is correct, check time sync on both sides:

```bash
date -u
```

On OpenWrt, make sure NTP is working before installing always-on service.

## OpenWrt

Use the auto-refresh service on OpenWrt when a LAN needs to keep access open after WAN IP changes.

Full guide:

[OpenWrt keepalive guide](openwrt-keepalive.zh-CN.md)

## Common failures

`FILTERED` after knocking:

```text
No allowlist entry was added, or another firewall still blocks the port.
Check server logs and allowlist.
```

`REFUSED` after knocking:

```text
The firewall path opened, but no service is listening on that TCP port.
```

No allowlist entry:

```text
Wrong URL, wrong knock order, UDP packets blocked upstream, wrong capture interface, clock drift, or HMAC secret mismatch.
```

Service keeps skipping:

```text
The detected current IP is not public, or the route to server goes through TUN/VPN/proxy path.
Fix routing or use a public-IP check endpoint that reflects the real egress path.
```
