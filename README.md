# KnockGate

[简体中文](README.zh-CN.md)

## What This Is

KnockGate uses `knockd` to watch a sequential UDP knock sequence and uses an `nftables` timeout set to temporarily allow the source IP.

It does not take over your existing firewall. It only creates its own `table inet knockgate` and pre-filters the protected TCP ports you choose. All other ports keep the behavior of your current firewall, cloud security group, and services.

This is not a VPN, proxy, tunnel, or strong authentication system. Traditional port knocking can be observed and replayed by an on-path attacker. It helps reduce exposure to ordinary public scanning; it should not replace SSH keys, TLS, application authentication, VPN, or zero-trust access controls.

## How It Works

KnockGate installs a protective overlay:

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

The UDP knock ports are not opened in `nftables`; `knockd` observes UDP packets through packet capture.

Important behavior:

- Protected TCP ports are dropped unless the source IP is in the temporary allowlist.
- Successful UDP knocks add the source IP to the allowlist.
- Other traffic is not changed by KnockGate.
- `/etc/nftables.conf` is not rewritten.
- Existing firewall rules and cloud security groups still apply.

## Recommended Configuration

Use KnockGate as an extra protective layer in front of ports that are otherwise reachable:

- Keep SSH, web, VPN, and other public ports managed by your existing firewall or cloud security group.
- Make the protected service port reachable in your existing firewall, then let KnockGate hide it from unknown sources.
- Do not configure the protected port to be blocked by the original firewall, or KnockGate cannot make it reachable after knocking.
- Allow UDP knock packets to reach the server path. Host-level `nftables` does not need accept rules for knock ports, but upstream cloud firewalls must not block them before they reach the host.
- Use random high UDP knock ports and keep the import QR private.

Example:

- Existing firewall allows SSH `22` and app port `5432`.
- KnockGate protects `5432`.
- Before knock: `5432` is dropped by KnockGate.
- After knock: the client IP can reach `5432`, subject to the original firewall still allowing it.

## Requirements

Supported systems:

- Debian 11/12/13
- Ubuntu 20.04/22.04/24.04
- Rocky Linux 8/9
- AlmaLinux 8/9
- CentOS Stream 8/9
- Fedora 38+
- Arch Linux

Dependencies:

- `bash`
- `systemd`
- `nftables`
- `knockd`
- `iproute2`
- `qrencode`

The script can install missing packages on supported distributions. `qrencode` is used to render terminal QR codes for client import URLs.

## Files

Repository files:

- `knockgate.sh` - server-side installer and manager
- `rfcjp-knock.sh` - client-side UDP knock helper
- `rfcjp-check.sh` - client-side TCP connectivity checker
- `flutter/` - Flutter GUI client for Android, iOS, macOS, Windows, and Linux

Installed server paths:

- `/usr/local/bin/knockgate`
- `/etc/knockgate/knockgate.conf`
- `/etc/knockgate/knockgate.nft`
- `/etc/knockgate/backups`
- `/etc/knockgate/README`
- `/etc/knockd.conf`
- `/etc/systemd/system/knockgate-nft.service`
- `/etc/systemd/system/knockd.service.d/override.conf`

## Install

Manual install:

```bash
chmod +x knockgate.sh
sudo ./knockgate.sh
```

After install:

```bash
sudo knockgate
```

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport bash
```

Client helpers are not installed on the server unless explicitly requested. On a client machine:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport INSTALL_CLIENT_HELPERS=1 bash
```

## Menu

```text
KnockGate Manager

1. Install / Repair
2. Update config
3. Reset ports and timings
4. Show status
5. Show knockd logs
6. Show temporary allowlist
7. Add IP to temporary allowlist
8. Flush temporary allowlist
9. Reload KnockGate rules
10. Uninstall
11. Generate client import QR
12. Exit
```

## Client Unlock

Use UDP knocks in the exact order shown by `knockgate`:

```bash
./rfcjp-knock.sh SERVER_IP 38127 19452 47219 26083 50001 50002
```

Manual equivalent:

```bash
printf knockgate | nc -u -w1 SERVER_IP 38127 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 19452 || true
```

After knocking, check a protected TCP port:

```bash
./rfcjp-check.sh SERVER_IP 5432
```

Results:

- `OPEN`: firewall opened and a service is listening.
- `REFUSED`: firewall path is open, but no service is listening.
- `FILTERED`: still blocked or packet path is filtering.

## Client Import URL

Menu item 11 prints a QR code and the protocol URL below it:

```text
knockgate://import/v1?host=SERVER_IP&scheme=udp&knock_ports=38127%2C19452%2C47219&protected_ports=5432&seq_timeout=10&open_timeout=12h&label=KnockGate
```

The QR code contains the UDP knock sequence. Treat it like a secret and share it only with trusted clients.

## Flutter Client

The Flutter client in [`flutter/`](flutter/) can:

- import `knockgate://` URLs;
- scan import QR codes on Android, iOS, and macOS;
- edit host, UDP knock ports, protected TCP ports, and timing fields;
- send the UDP knock sequence with one button;
- check protected TCP port reachability.

Development:

```bash
cd flutter
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Windows and Linux GUI builds support manual profile entry and pasted import URLs. QR scanning is currently limited to Android, iOS, and macOS by the scanner plugin.

## Uninstall

The uninstall flow can:

- stop and disable `knockd`;
- stop and disable `knockgate-nft.service`;
- delete the live `inet knockgate` nft table;
- remove KnockGate's nft config and systemd files;
- restore `knockd.conf` backups if requested;
- delete `/usr/local/bin/knockgate`;
- optionally delete `/etc/knockgate`.

It does not restore or rewrite `/etc/nftables.conf` because KnockGate does not modify it.

## License

MIT License. See [LICENSE](LICENSE).
