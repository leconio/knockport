# Quick Start

Get a server protected, import the profile on a client, then knock and check the port.

## 1. Install the server

Run on the Linux server:

```bash
curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh | sudo bash
```

If the server needs an HTTP or SOCKS proxy to reach GitHub or package mirrors:

```bash
export HTTPS_PROXY=http://127.0.0.1:7890
export HTTP_PROXY=http://127.0.0.1:7890
export ALL_PROXY=socks5://127.0.0.1:7890

curl -fsSL https://raw.githubusercontent.com/leconio/knockport/main/install.sh \
  | sudo --preserve-env=HTTP_PROXY,HTTPS_PROXY,ALL_PROXY,NO_PROXY,http_proxy,https_proxy,all_proxy,no_proxy bash
```

Start setup:

```bash
sudo knockgate install
```

Use these common values first:

```text
Protected ports: 5432/tcp
Protect hook: prerouting
Open timeout: 12h
Seq timeout: 10
HMAC window: 60
Interface: press Enter to use auto-detected value
```

Protected port format:

```text
5432        protects 5432/tcp and 5432/udp
5432/tcp    protects TCP only
5432/udp    protects UDP only
5432/tcp,9092/tcp,10521/udp
```

## 2. Get the import URL

Run on the server:

```bash
sudo knockgate qr
```

Copy the `knockgate://import/v1?...` URL.

If the printed `host=` is a private address such as `10.x`, `172.16-31.x`, or `192.168.x`, replace it with the public IP or domain clients will use.

## 3. Download the CLI client

Linux x86_64 example:

```bash
curl -fLO https://github.com/leconio/knockport/releases/latest/download/knockgate_client_cli_linux_amd64.tar.gz
tar -xzf knockgate_client_cli_linux_amd64.tar.gz
cd knockgate_client_cli_linux_amd64
```

Other architectures are listed in [CLI Client](cli-client.md).

## 4. Knock

Run on the client:

```bash
./knockgate-client --url 'knockgate://import/v1?...'
```

The client sends UDP packets in order. The last packet contains the HMAC proof.

## 5. Check the protected port

Before knocking:

```bash
./knockgate-client check SERVER_HOST 5432/tcp
```

After knocking:

```bash
./knockgate-client --url 'knockgate://import/v1?...' --check-ports 5432/tcp
```

Result meanings:

```text
OPEN      port is open, TCP handshake succeeded
REFUSED   port is open through firewall, but no service is listening
FILTERED  port is not open, packet timed out or was dropped
UDP-SENT  UDP packet was sent, open state is not proven
FAILED    local command or network lookup failed
```

## 6. Server checks

```bash
sudo knockgate status
sudo knockgate allowlist
sudo knockgate logs
```

Flush temporary allowlist:

```bash
sudo knockgate flush
```

Upgrade server binary:

```bash
sudo knockgate upgrade
```

Uninstall:

```bash
sudo knockgate uninstall
```

## 7. Mobile or desktop app

Use the Flutter client if you want QR import and a graphical UI.

See [Flutter Client](flutter-client.md).
