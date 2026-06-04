# Server Usage

This document is for the machine that protects ports.

## What the server does

KnockGate runs a Go service that captures UDP knock packets with libpcap. It does not listen on the knock ports.

When the UDP sequence is correct, the last packet is verified with HMAC, timestamp, and nonce. If verification passes, the source IPv4 is added to an nftables timeout set.

The nftables rules then allow that source IP to reach the configured protected ports until `open_timeout` expires.

## What the server does not do

KnockGate does not take over `/etc/nftables.conf`.

It does not edit SSH rules.

It does not manage exception ports.

It creates and manages only:

```text
table inet knockgate
set knock_allow_temp_v4
```

Only the protected ports are dropped for sources that have not knocked. Other traffic remains controlled by your existing firewall, cloud firewall, router, or service configuration.

## Supported server environments

The installer targets common systemd Linux distributions:

```text
Debian 11/12/13
Ubuntu 20.04/22.04/24.04
Rocky Linux 8/9
AlmaLinux 8/9
CentOS Stream 8/9
Fedora 38+
Arch Linux
```

Required runtime tools:

```text
nftables
libpcap runtime library
iproute2
systemd
curl
tar
ca-certificates
```

`qrencode` is optional. If missing, `knockgate qr` still prints the URL but not the terminal QR code.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
sudo knockgate install
```

Proxy example:

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

The server needs public network access only when installing packages, downloading the server binary, or running `knockgate upgrade`.

Normal knock handling does not require the server to connect out to the public network.

## Interactive setup fields

Run:

```bash
sudo knockgate install
```

Fields:

```text
Protected ports
Protect hook
UDP knock sequence
Open timeout
Sequence timeout
Timestamp/HMAC window
pcap capture interface
HMAC secret regeneration
```

Protected port syntax:

```text
5432                  protect TCP and UDP on port 5432
5432/tcp              protect TCP only
5432/udp              protect UDP only
5432/tcp,9092,10521/udp
```

Knock ports are UDP ports. They do not need to be open in the host firewall, but upstream cloud firewalls or routers must allow the UDP packets to reach the server.

## Protect hook

`prerouting` is the default.

Use `prerouting` when you want KnockGate to act before routing and DNAT. This is the earliest protection point and also works for forwarded or DNAT traffic. After a client knocks successfully, later firewall chains, router rules, cloud firewalls, or the target service must still allow that traffic.

Use `input` when you only want to protect services delivered to the local host. It is less aggressive and does not cover forwarded or DNAT traffic.

Changing the hook does not rewrite your existing firewall. It rebuilds only KnockGate's own table.

## Configuration files

Main config:

```text
/etc/knockgate/knockgate.conf
```

Generated nft files:

```text
/etc/knockgate/knockgate.nft
/etc/knockgate/knockgate.apply.nft
```

Systemd unit:

```text
/etc/systemd/system/knockgate.service
```

Use `sudo knockgate reset` instead of editing the config by hand. The config contains `SECRET`, so keep it root-only.

## Commands

Open the menu:

```bash
sudo knockgate
```

Install or repair:

```bash
sudo knockgate install
```

Apply current config and restart the service:

```bash
sudo knockgate update
```

`update` does not download a new version. It applies the existing local config.

Download the latest server binary from GitHub Release and restart:

```bash
sudo knockgate upgrade
```

Download a specific tag:

```bash
sudo knockgate upgrade v0.1.14
```

Reset protected ports, knock sequence, secret, and timings:

```bash
sudo knockgate reset
```

Show status:

```bash
sudo knockgate status
```

Show logs:

```bash
sudo knockgate logs
sudo knockgate logs-follow
```

Show temporary allowlist:

```bash
sudo knockgate allowlist
```

Manually allow an IPv4 address:

```bash
sudo knockgate allow 203.0.113.10
```

Flush the temporary allowlist:

```bash
sudo knockgate flush
```

Reload KnockGate nft rules and keep the allowlist:

```bash
sudo knockgate reload
```

Delete KnockGate's nft table:

```bash
sudo knockgate clear
```

Generate client import URL and terminal QR code:

```bash
sudo knockgate qr
```

Uninstall:

```bash
sudo knockgate uninstall
```

## Import URL

Generate:

```bash
sudo knockgate qr
```

Example shape:

```text
knockgate://import/v1?scheme=udp-hmac&host=SERVER_HOST&knock_ports=58645%2C61037%2C57910%2C21030%2C26547%2C43223&protected_ports=5432%2Ftcp&protect_hook=prerouting&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=KnockGate
```

If `host=` is private or reserved, replace it with the public IP or domain before importing on a remote client.

Keep this URL private. It contains the HMAC secret.

## Verify on the server

Check that the service is running:

```bash
systemctl status knockgate.service --no-pager
```

Check the nft table:

```bash
sudo nft list table inet knockgate
```

Check the temporary allowlist:

```bash
sudo nft list set inet knockgate knock_allow_temp_v4
```

The allowlist should show source IPs with nft timeout values after successful knocks.

## Troubleshooting

No allowlist entry after knocking:

```bash
sudo knockgate logs
```

Check:

```text
The client used UDP, not TCP.
The knock ports and order match the import URL.
All UDP knock packets arrive within seq_timeout.
The final packet HMAC window is valid.
Client and server clocks are close enough.
The server captures on the correct interface.
Cloud firewall or router allows UDP knock packets to reach the host.
```

Allowlist entry exists but the service is still unreachable:

```text
The original firewall, cloud firewall, router, DNAT rule, or service listener may still block traffic.
KnockGate only removes its own protected-port drop for allowlisted IPs.
```

`input` hook warns that a port cannot be confirmed open:

```text
KnockGate could not parse an explicit allow rule in the existing nft ruleset.
If the port is allowed through jump/goto, firewalld, ufw, iptables-nft, sets, or cloud firewall rules, this can be a false warning.
Use prerouting if you want KnockGate to act first.
Use input if you want a conservative local-service-only overlay.
```

QR host is private:

```text
Replace host= in the import URL with a public IP or domain before giving it to outside clients.
```

## Security notes

UDP-HMAC knock is meant to hide protected ports from ordinary scans and unauthenticated clients.

It is not a replacement for service authentication, TLS, SSH keys, database passwords, or application access control.

Keep client and server clocks synchronized. The final knock packet includes a timestamp and is rejected outside `hmac_window`.
