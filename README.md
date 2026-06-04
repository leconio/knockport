# KnockGate

![KnockGate dashboard illustration](docs/images/knockgate-hero.jpg)

[简体中文](README.zh-CN.md)

KnockGate is a Linux port-knocking service for temporarily opening protected ports to a verified IPv4 source address.

It uses UDP port sequences captured with `libpcap`, validates the final packet with HMAC, and stores successful source addresses in an `nftables` timeout set. KnockGate does not replace the host firewall and does not modify SSH rules.

## Features

- UDP sequence knocking with no listening socket on knock ports
- Final-step `HMAC-SHA256 + timestamp + nonce` verification
- Temporary IPv4 allowlist backed by an `nftables` timeout set
- Repeated successful knocks from the same source refresh the allowlist timeout
- Protected TCP and UDP ports
- Does not rewrite `/etc/nftables.conf`
- Does not flush existing firewall rules
- Adds its own protective drop rules without taking over the rest of the host firewall
- systemd service management
- Terminal QR code for client profile import
- Linux `amd64` and `arm64` release packages

## Usage

- Server quick start: [Quick Start](docs/quick-start.md)
- Server commands and maintenance: [Server Usage](docs/server-usage.md)
- Go CLI, routers, OpenWrt, and desktop clients: [CLI Client](docs/cli-client.md)
- OpenWrt always-on keepalive with public-IP refresh: [OpenWrt keepalive guide](docs/openwrt-keepalive.zh-CN.md)
- Flutter desktop and mobile client: [Flutter Client](docs/flutter-client.md)

## Port Syntax

Protected ports support protocol suffixes:

```text
2345      protect 2345/tcp and 2345/udp
2345/tcp  protect TCP only
2345/udp  protect UDP only
```

Multiple protected ports are separated with commas:

```text
5432,9092/tcp,51820/udp
```

Knock ports are always UDP destination ports.

## Requirements

Server:

- Linux with systemd
- `nftables`
- `iproute2`
- `libpcap`
- `qrencode` for terminal QR output, optional; install continues without it

Supported package families:

- Debian / Ubuntu
- RHEL family: Rocky Linux, AlmaLinux, CentOS Stream, Fedora
- Arch Linux

## Quick Start

Install on the server:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

If the server needs an HTTP/SOCKS proxy to reach package mirrors or GitHub, preserve proxy environment variables when entering `sudo`:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

`HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, and `NO_PROXY` are used by tools such as `curl`. Package managers may also need their own proxy configuration depending on the distribution.

During setup, enter:

```text
Protected ports: for example 5432,9092/tcp,51820/udp
Knock ports: use the generated UDP ports, or enter your own
Open timeout: default 12h
Interface: auto-detected by default
```

Print the client import URL / QR code:

```bash
sudo knockgate qr
```

Download the Go CLI client on a client machine. Choose the asset that matches the client machine architecture:

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
```

Open protected ports from the client:

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

Check a protected port:

```bash
./knockgate-client check SERVER_IP 5432
./knockgate-client check SERVER_IP 5432/tcp 5432/udp
```

The Go CLI client is published as release assets. It is separate from the server installer and is not installed on the server by `install.sh`.

## Server Usage

Interactive menu:

```bash
sudo knockgate
```

Common commands:

```bash
sudo knockgate install       # install or repair
sudo knockgate reset         # reset protected ports, knock ports, secret, and timings
sudo knockgate update        # apply the currently saved settings
sudo knockgate upgrade       # download latest GitHub Release server and restart service
sudo knockgate upgrade v0.1.9 # download a specific server version and restart service
sudo knockgate status        # show service, rules, allowlist, and config
sudo knockgate logs          # show recent logs
sudo knockgate logs-follow   # follow logs
sudo knockgate qr            # print client import URL / QR code
sudo knockgate allow IP      # manually allow one IPv4 temporarily
sudo knockgate flush         # flush temporary allowlist
sudo knockgate reload        # rebuild KnockGate's own nft rules; keep temporary allowlist
sudo knockgate clear         # delete table inet knockgate
sudo knockgate uninstall     # uninstall
```

`update` does not download a new version. It only applies the current `/etc/knockgate/knockgate.conf` and restarts the service. Use `upgrade` to update the server binary.

## Configuration Management

Use the interactive menu to change settings:

```bash
sudo knockgate reset
```

The configuration file is managed by KnockGate and normally does not need manual editing. The path and example below are mainly for troubleshooting or backup records.

Configuration file:

```text
/etc/knockgate/knockgate.conf
```

Example content:

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

If you manually edit the file, apply it with:

```bash
sudo knockgate update
```

## Firewall Model

KnockGate manages only this table:

```text
table inet knockgate
```

By default, KnockGate creates a `prerouting` hook with `priority raw` and `policy accept`. This is the earliest practical protection point for inbound traffic, including public ingress ports and DNAT/forwarded ports. During install/reset you can choose `input` instead when the protected ports are local services on the same machine.

Hook choices:

```text
prerouting  default; affects inbound packets before route decision and DNAT/forward handling
input       affects only packets delivered to local services on this host
```

For a protected bare port such as `2345`, the effective rules are:

```nft
chain prerouting {
    type filter hook prerouting priority raw; policy accept;

    ip saddr @knock_allow_temp_v4 tcp dport 2345 accept
    tcp dport 2345 drop
    ip saddr @knock_allow_temp_v4 udp dport 2345 accept
    udp dport 2345 drop
}
```

Knock ports are not accepted by nftables. The service reads UDP packets from the interface through pcap, so KnockGate can still see knock packets and update its temporary allowlist even when protected ports are currently dropped.

KnockGate's allow rule is not a bypass for every other host firewall rule. An `accept` verdict in an early hook only lets the packet continue through later hooks. If another nftables base chain, firewalld, ufw, or a provider firewall drops the protected service after KnockGate accepts it, the connection can still fail. Configure the existing firewall to allow traffic that KnockGate has already allowlisted, or use KnockGate as the only rule set protecting that specific service port.

Upstream firewalls are different. Cloud security groups, provider firewalls, or routers must allow the UDP knock packets to reach the server.

## Proxy, TUN, And Fake-IP Notes

The server only needs outbound network access during package installation and binary upgrades, for example when `install.sh` installs dependencies or `knockgate upgrade` downloads a release asset from GitHub. Normal knocking does not require the server to make outbound connections.

The generated import URL uses the server address detected locally. On cloud hosts this can be a private address such as `10.x`, `172.16-31.x`, or `192.168.x`. KnockGate will print a warning in that case. If clients are outside that private network, replace the `host=` value in the import URL with the public IP or domain before importing it.

The Go CLI and Flutter clients warn when the host resolves to a private, CGNAT, reserved, or fake-IP range such as `198.18.0.0/15`, or when a TUN/VPN-like interface is detected. This does not stop one-shot knocking. In auto-refresh service mode, the Go CLI skips that round because the public address/path cannot be trusted.

## Client Usage

Create an import URL on the server:

```bash
sudo knockgate qr
```

### Go CLI Client

For routers, small Linux hosts, OpenWrt, Asuswrt-Merlin, and modified router firmware, use the Go CLI client. It is a static binary and does not require Go, OpenSSL, curl, nc, bash, or Python on the target device.

For a full OpenWrt keepalive setup, including procd service installation, public-IP refresh behavior, time sync, logs, and troubleshooting, see [OpenWrt keepalive guide](docs/openwrt-keepalive.zh-CN.md).

Download the matching asset from the latest release:

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

Typical choices:

```text
OpenWrt aarch64/Filogic/modern ARM64     linux_arm64
OpenWrt ARMv7                            linux_armv7
older ARM routers                        linux_armv6
many older Asus/MIPS routers             linux_mipsle_softfloat
x86 router boxes                         linux_amd64 or linux_386
```

One-shot knock:

```bash
./knockgate-client --url 'knockgate://import/v1?...'
./knockgate-client --secret BASE64URL_SECRET --check-ports 5432 SERVER_IP 45669 65075 31244 20035 64168 59462
```

Check without knocking:

```bash
./knockgate-client check SERVER_IP 5432
./knockgate-client check SERVER_IP 5432/tcp 5432/udp
```

Install the Go CLI as an auto-refresh service on a client host:

```bash
sudo ./knockgate-client install \
  --url 'knockgate://import/v1?...' \
  --interval 300 \
  --ip-check-url http://api.ipify.org \
  --ip-check-url http://checkip.amazonaws.com
```

The installer auto-detects the host service manager and writes only the matching service:

```text
systemd              /etc/systemd/system/knockgate-client.service
OpenWrt procd        /etc/init.d/knockgate-client
Asuswrt-Merlin       /opt/etc/init.d/S99knockgate-client, requires Entware-style /opt layout
```

The service checks the current public IPv4 every interval. It sends a new knock only when the public IP changes, or when the local last-knock timer is close to the import URL `open_timeout`. For example, with `open_timeout=12h`, the client refreshes around 11h55m after the last successful knock. If `open_timeout=0`, the client treats the allowlist as permanent and refreshes only when the public IP changes.

If the address is private, CGNAT, reserved, fake-IP, or if the route to the KnockGate server uses a TUN/VPN-like interface, the service logs a warning and skips that round.

The final UDP knock packet is HMAC-signed with the current Unix timestamp. The server verifies it against the import URL `hmac_window`, usually 60 seconds, so client and server clocks must be reasonably synchronized.

Service commands:

```bash
knockgate-client status
knockgate-client logs
sudo knockgate-client uninstall
```

TCP results:

```text
OPEN      port open: TCP handshake succeeded
REFUSED   port open: firewall/path reached the host, but no service is listening
FILTERED  port not open: timed out or dropped by firewall/network
FAILED    unknown state: local tool or network command failed
```

UDP checks send a probe only. UDP has no handshake, so a generic client cannot reliably prove that a UDP port is open.

## Flutter Client

The Flutter client is in [`flutter/`](flutter/). It supports profile import URLs, QR scanning on Android/iOS/macOS, manual profile editing, UDP-HMAC knocking, connectivity checks, and optional app-open auto refresh based on public IP and `open_timeout`.

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
```

## Uninstall

```bash
sudo knockgate uninstall
```

Other cleanup commands:

```bash
sudo knockgate flush   # clear temporary allowlist
sudo knockgate clear   # delete table inet knockgate
```

## Security Notes

- Keep the import URL and HMAC secret private.
- Keep client and server clocks synchronized. The final HMAC packet includes the current Unix timestamp and is rejected outside the configured `hmac_window`, usually 60 seconds.
- Allow UDP knock traffic in upstream cloud firewalls.
- Port knocking is not a VPN and does not replace service-level authentication.

## License

MIT License. See [LICENSE](LICENSE).
