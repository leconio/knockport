# KnockGate

[简体中文](README.zh-CN.md)

KnockGate is a Linux port-knocking service for temporarily opening protected ports to a verified IPv4 source address.

It uses UDP port sequences captured with `libpcap`, validates the final packet with HMAC, and stores successful source addresses in an `nftables` timeout set. KnockGate does not replace the host firewall and does not modify SSH rules.

## Features

- UDP sequence knocking with no listening socket on knock ports
- Final-step `HMAC-SHA256 + timestamp + nonce` verification
- Temporary IPv4 allowlist backed by an `nftables` timeout set
- Protected TCP and UDP ports
- Does not rewrite `/etc/nftables.conf`
- Does not flush existing firewall rules
- systemd service management
- Terminal QR code for client profile import
- Linux `amd64` and `arm64` release packages

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
- `qrencode` for terminal QR output, optional

Supported package families:

- Debian / Ubuntu
- RHEL family: Rocky Linux, AlmaLinux, CentOS Stream, Fedora
- Arch Linux

The installer downloads a prebuilt release package. It does not build Go on the target server.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

Release assets:

```text
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_amd64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate_linux_arm64.tar.gz
https://github.com/leconio/knockport/releases/latest/download/knockgate-knock.sh
https://github.com/leconio/knockport/releases/latest/download/knockgate-check.sh
```

Installed server files:

```text
/usr/local/bin/knockgate
/etc/knockgate/knockgate.conf
/etc/knockgate/knockgate.nft
/etc/knockgate/knockgate.apply.nft
/etc/systemd/system/knockgate.service
```

The shell client scripts are published as release assets and kept in this repository under `clients/shell/`. They are not installed on the server by `install.sh`.

## Server Usage

Interactive menu:

```bash
sudo knockgate
```

Common commands:

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

## Configuration

Configuration file:

```text
/etc/knockgate/knockgate.conf
```

Example:

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

Apply edited configuration:

```bash
sudo knockgate update
```

## Firewall Model

KnockGate manages only this table:

```text
table inet knockgate
```

The table has an input hook with `policy accept`. It only drops configured protected ports before the rest of the host firewall continues processing traffic.

For a protected bare port such as `2345`, the effective rules are:

```nft
ip saddr @knock_allow_temp_v4 tcp dport 2345 accept
tcp dport 2345 drop
ip saddr @knock_allow_temp_v4 udp dport 2345 accept
udp dport 2345 drop
```

Knock ports are not accepted by nftables. The service reads UDP packets from the interface through pcap.

## Client Usage

Create an import URL on the server:

```bash
sudo knockgate qr
```

Use the shell client from this repository:

```bash
clients/shell/knockgate-knock.sh --url 'knockgate://import/v1?...'
clients/shell/knockgate-knock.sh --secret BASE64URL_SECRET SERVER_IP 45669 65075 31244 20035 64168 59462
```

Check a protected port:

```bash
clients/shell/knockgate-check.sh SERVER_IP 5432
clients/shell/knockgate-check.sh SERVER_IP 5432/tcp 5432/udp
```

TCP results:

```text
OPEN      TCP handshake succeeded
REFUSED   host was reachable, but no service is listening
FILTERED  connection timed out
```

UDP checks send a probe only. UDP has no handshake, so a generic client cannot reliably prove that a UDP port is open.

## Flutter Client

The Flutter client is in [`flutter/`](flutter/). It supports profile import URLs, QR scanning on Android/iOS/macOS, manual profile editing, UDP-HMAC knocking, and connectivity checks.

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
- Keep client and server clocks reasonably synchronized.
- Allow UDP knock traffic in upstream cloud firewalls.
- Port knocking is not a VPN and does not replace service-level authentication.

## License

MIT License. See [LICENSE](LICENSE).
