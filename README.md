# KnockGate

[简体中文](README.zh-CN.md)

## What This Is

KnockGate is a Go server that captures UDP knock packets with `libpcap`, validates every step with `HMAC-SHA256 + timestamp + nonce`, and temporarily adds the source IPv4 address to an `nftables` timeout set.

It does not listen on the knock ports, does not use `knockd`, and does not take over your existing firewall. KnockGate only manages its own `table inet knockgate` and only pre-filters the protected TCP ports you choose. SSH rules are not read, prompted for, or modified.

## How It Works

The server runs as:

```text
/usr/local/bin/knockgate serve
```

It captures UDP packets on the configured interface and validates:

```text
Payload:    KG1|step|unix_timestamp|nonce|hmac
HMAC input: KG1|udp_port|step|unix_timestamp|nonce
```

After the ordered sequence succeeds:

```bash
nft add element inet knockgate knock_allow_temp_v4 { IP timeout OPEN_TIMEOUT }
```

KnockGate's nft overlay:

```nft
table inet knockgate {
    set knock_allow_temp_v4 {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority -150; policy accept;

        ip saddr @knock_allow_temp_v4 tcp dport { PROTECTED_PORTS } accept
        tcp dport { PROTECTED_PORTS } drop
    }
}
```

Notes:

- `/etc/nftables.conf` is not rewritten.
- Existing firewall rules are not flushed.
- SSH port rules are not changed.
- `knockd` is not installed or used.
- The knock ports are not opened by a UDP socket, but upstream cloud firewalls must allow the UDP packets to reach the host so pcap can see them.

## Requirements

- Linux + systemd
- `nftables`
- `iproute2`
- `libpcap`
- optional `qrencode`

The installer builds the Go binary on the server and installs the needed build dependencies.

## Install

Manual source build:

```bash
go build -o knockgate ./cmd/knockgate
sudo ./knockgate install
```

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport bash
```

After install:

```bash
sudo knockgate
```

## Client Unlock

Using an import URL:

```bash
./rfcjp-knock.sh --url 'knockgate://import/v1?scheme=udp-hmac&host=SERVER_IP&knock_ports=37708%2C31114&protected_ports=5432&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=KnockGate'
```

Or manually:

```bash
./rfcjp-knock.sh --secret BASE64URL_SECRET SERVER_IP 37708 31114 25880 62009 61086 33854
```

Check a protected TCP port:

```bash
./rfcjp-check.sh SERVER_IP 5432
```

## Flutter Client

The [`flutter/`](flutter/) GUI client supports import URLs, QR scanning on Android/iOS/macOS, manual profile edits, UDP-HMAC knocking, and protected TCP port checks.

## Uninstall And Clear

```bash
sudo knockgate uninstall
sudo knockgate flush
sudo knockgate clear
```

These commands do not modify SSH rules and do not rewrite `/etc/nftables.conf`.

## License

MIT License. See [LICENSE](LICENSE).
