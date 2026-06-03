# KnockGate

[简体中文](README.zh-CN.md)

## What This Is

KnockGate uses `knockd` to watch a sequential UDP knock sequence and uses an `nftables` timeout set to temporarily allow the source IP.

Its security model:

- take over inbound firewall rules;
- default-drop inbound traffic;
- keep ports already accepted by the current firewall open;
- automatically keep the current SSH port open;
- close protected ports by default;
- add successful knock source IPs to an `nftables` set;
- allow that source IP to access all protected ports until timeout;
- optionally allow an IP permanently, with warning and explicit confirmation.

This is not a VPN, proxy, tunnel, or strong authentication system. Traditional port knocking can be observed and replayed by an on-path attacker. It helps reduce exposure to ordinary public scanning; it should not replace SSH keys, TLS, application authentication, VPN, or zero-trust access controls.

## How It Works

KnockGate generates a full `nftables` inbound firewall:

```nft
table inet knockgate {
    set knock_allow_temp_v4 {
        type ipv4_addr
        flags timeout
    }

    chain input {
        type filter hook input priority filter; policy drop;

        iif lo accept
        ct state established,related accept
        ip protocol icmp accept

        tcp dport { CURRENT_FIREWALL_TCP_PORTS } accept
        ip saddr @knock_allow_temp_v4 tcp dport { PROTECTED_PORTS } accept
    }
}
```

The knock ports themselves are not opened in the firewall. `knockd` sees UDP packets through packet capture, so the knock ports do not need services listening on them.

## Requirements

Supported systems:

- Debian 11/12/13
- Ubuntu 20.04/22.04/24.04
- Rocky Linux 8/9
- AlmaLinux 8/9
- CentOS Stream 8/9
- Fedora 38+
- Arch Linux

Runtime dependencies:

- `bash`
- `systemd`
- `nftables`
- `knockd`
- `iproute2`

The script can install missing packages on supported distributions. If `knockd` is unavailable, it stops with a clear error.

## Files

Repository files:

- `knockgate.sh` - server-side installer and manager
- `rfcjp-knock.sh` - generic client-side knock helper
- `rfcjp-check.sh` - generic client-side TCP connectivity checker

Installed server paths:

- `/usr/local/bin/knockgate`
- `/etc/knockgate/knockgate.conf`
- `/etc/knockgate/backups`
- `/etc/knockgate/README`
- `/etc/nftables.conf`
- `/etc/knockd.conf`
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

One-line install after publishing to GitHub:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/knockgate.sh -o /tmp/knockgate.sh \
  && chmod +x /tmp/knockgate.sh \
  && sudo /tmp/knockgate.sh
```

Installer script form:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport bash
```

The installer installs only the server manager by default:

```text
/usr/local/bin/knockgate
```

Client helpers are not installed on the server unless explicitly requested. On a client machine:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo KNOCKGATE_REPO=leconio/knockport INSTALL_CLIENT_HELPERS=1 bash
```

For forks or self-hosted raw file URLs:

```bash
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sudo KNOCKGATE_RAW_BASE=https://raw.githubusercontent.com/OWNER/REPO/main bash
```

## First Run

On startup, choose a language:

```text
1. 中文
2. English
```

You can skip the language prompt:

```bash
sudo KNOCKGATE_LANG=zh knockgate
sudo KNOCKGATE_LANG=en knockgate
```

During install or reset, KnockGate will:

1. detect the current SSH port;
2. read current firewall `accept` rules;
3. keep currently accepted TCP/UDP ports open;
4. require confirmation that inbound policy will become `DROP`;
5. ask for protected ports;
6. roll 6 random knock ports;
7. show a final summary;
8. require uppercase `YES` before applying.

Random knock ports avoid:

- current always-open TCP/UDP firewall ports;
- user-provided protected ports;
- currently listening TCP/UDP ports;
- duplicate ports inside the knock sequence.

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
9. Restore firewall backup
10. Uninstall
11. Test config
12. Exit
```

Dangerous actions require confirmation. Applying firewall rules, restoring backups, uninstalling, flushing allowlists, and permanent IP allows all require explicit prompts.

## How To Unlock From A Client

KnockGate uses a UDP knock sequence. The client must send one UDP datagram to each knock port in the exact order shown by `knockgate`.

Rules:

- use UDP;
- send ports in the exact order;
- do not skip ports;
- do not reorder ports;
- do not insert other knock ports between them;
- finish the whole sequence within `SEQ_TIMEOUT`;
- use a short delay such as `0.2s` to `0.5s` between ports;
- after success, the client source IP is added to the temporary allowlist;
- that source IP can access all protected ports until `OPEN_TIMEOUT` expires.

Example server-side summary:

```text
Knock sequence: 38127 -> 19452 -> 47219 -> 26083 -> 50001 -> 50002
Seq timeout: 10s
Open timeout: 12h
Protected ports: 5432,9092
```

Unlock with the helper script:

```bash
./rfcjp-knock.sh SERVER_IP 38127 19452 47219 26083 50001 50002
```

UDP knocks do not require root privileges. You can adjust the delay between datagrams:

```bash
./rfcjp-knock.sh --delay 0.5 SERVER_IP 38127 19452 47219 26083 50001 50002
```

Equivalent manual UDP sequence:

```bash
printf knockgate | nc -u -w1 SERVER_IP 38127 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 19452 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 47219 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 26083 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 50001 || true
sleep 0.25
printf knockgate | nc -u -w1 SERVER_IP 50002 || true
```

After knocking, test a protected port:

```bash
./rfcjp-check.sh SERVER_IP 5432
```

Interpretation:

- `OPEN`: firewall opened and a service is listening;
- `REFUSED`: firewall opened, but no service is listening;
- `FILTERED/TIMEOUT`: knock did not open the allowlist, or the network path is filtering.

If the sequence fails, check:

- ports are in the exact order;
- all knocks finished within `SEQ_TIMEOUT`;
- knocking and protected access use the same public source IP;
- proxy, VPN, or NAT is not changing source IP;
- `knockd` is listening on the correct interface.

If a local proxy, VPN, or TUN device intercepts UDP traffic, the knock packets may never reach the server. In that case the helper may finish but the server allowlist stays empty. Test from a clean route, bypass the proxy for the server IP, or use another host as the client.

## Client Helpers

Knock:

```bash
./rfcjp-knock.sh SERVER_IP PORT1 PORT2 PORT3 PORT4 PORT5 PORT6
```

Check connectivity only:

```bash
./rfcjp-check.sh SERVER_IP
```

Check specific TCP ports:

```bash
./rfcjp-check.sh SERVER_IP 22 80 443 5432
```

Connectivity checks have a hard timeout. Default is `3s`; override it when needed:

```bash
./rfcjp-check.sh --timeout 5 SERVER_IP 5432
CHECK_TIMEOUT=5 ./rfcjp-check.sh SERVER_IP 5432
```

Override default check ports:

```bash
SSH_PORT=2222 PROTECTED_PORT=5432 ORDINARY_PORT=15555 ./rfcjp-check.sh SERVER_IP
```

Typical test flow:

```bash
./rfcjp-check.sh SERVER_IP
./rfcjp-knock.sh SERVER_IP PORT1 PORT2 PORT3 PORT4 PORT5 PORT6
./rfcjp-check.sh SERVER_IP
```

## Manual Allowlist

Menu option 7 manually allows an IP.

Supported durations:

- `30s`
- `10m`
- `12h`
- `1d`
- `0` for permanent

Permanent entries do not expire automatically. KnockGate warns and requires uppercase `YES` before adding a permanent allow.

Menu option 6 shows:

- allowed IP;
- protected ports it can access;
- remaining time;
- raw `nftables` set output.

## Backups And Restore

Before writing important files, KnockGate creates timestamped backups in:

```text
/etc/knockgate/backups
```

It backs up:

- `/etc/nftables.conf`
- `/etc/knockd.conf`
- `/etc/default/knockd`
- systemd overrides
- live `nft list ruleset`

For UFW or iptables-nft compatibility rules, direct `nft -f` replay may fail. When UFW is detected and configuration exists, KnockGate can fall back to:

```bash
nft flush ruleset
ufw --force reload
```

## Uninstall

Run:

```bash
sudo knockgate
```

Choose:

```text
10. Uninstall
```

The uninstall flow can:

- stop and disable `knockd`;
- delete the live `inet knockgate` nft table;
- restore `nftables.conf` backups;
- restore `knockd.conf` backups;
- remove the systemd override;
- delete `/usr/local/bin/knockgate`;
- optionally delete `/etc/knockgate`.

## Safety Notes

- Always confirm SSH remains open before applying.
- Keep cloud/provider console rescue access available for remote servers.
- Firewall takeover rewrites `/etc/nftables.conf`.
- The default inbound policy is `DROP`.
- Knock ports are not opened in nftables; `knockd` observes UDP packets through packet capture.
- This version is IPv4-focused.
- Do not treat port knocking as strong authentication.

## License

MIT License. See [LICENSE](LICENSE).
