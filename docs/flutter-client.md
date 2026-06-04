# Flutter Client

The Flutter client is the graphical client for KnockGate.

It supports profile import, QR scan where available, manual editing, one-tap UDP-HMAC knocking, port checks, logs, and optional app-open auto refresh.

## Supported platforms

Release builds are produced for:

```text
Android
Windows
Linux
macOS
```

iOS can be built from source with a configured Apple development environment.

QR scanning availability:

```text
Android    supported
iOS        supported when built locally with camera permission
macOS      supported when camera permission is available
Windows    import URL manually
Linux      import URL manually
```

## Download

Go to the latest GitHub Release and download the client package for your platform:

```text
knockgate_client_android.apk
knockgate_client_windows_x64.zip
knockgate_client_linux_x64.tar.gz
knockgate_client_macos.zip
```

## Import a profile

On the server:

```bash
sudo knockgate qr
```

In the app:

```text
Open the top-right menu
Choose Import URL or Scan QR
Paste or scan the knockgate://import/v1?... URL
Confirm import
```

Import saves the profile locally. The app reloads the last saved profile on next launch.

If the URL host is a private address, edit the host field to the public IP or domain the device can reach.

## Profile fields

Knock tab fields:

```text
Name
Server host or IP
UDP knock ports
Seq timeout
HMAC window seconds
HMAC secret
```

Check tab fields:

```text
Server host or IP
Protected ports
```

Protected port format:

```text
5432        check TCP by default in the UI
5432/tcp    TCP target
5432/udp    UDP target, state cannot be proven open
5432/tcp,9092/tcp,10521/udp
```

After you edit a field, the action button changes to Save. Save first, then Knock or Check.

## Knock tab

Tap `Knock`.

The app opens a dark log sheet showing:

```text
host resolution
network path warnings
UDP socket status
each knock step
final HMAC packet step
success or failure
```

Newest log lines appear at the top.

On success, the sheet shows a success message and closes after about 3 seconds.

On failure, the sheet stays open so you can read the error.

You can also open the log sheet from the top-right menu.

## Check tab

Tap `Check` to check configured protected ports without knocking.

TCP result meanings:

```text
OPEN      port is open, TCP handshake succeeded
REFUSED   port is open through firewall, but no service is listening
FILTERED  port is not open, TCP timed out or was dropped
FAILED    local, DNS, or network operation failed
```

UDP checks cannot prove a port is open with a normal send. Treat UDP check results as path hints only.

## Auto refresh

Open:

```text
Top-right menu
Settings
Auto refresh allowlist
```

When enabled, the app checks conditions when the app opens:

```text
detect current public IPv4
compare it with the last saved public IP
compare last successful knock time with open_timeout
knock only when the IP changed or refresh time is close
```

With `open_timeout=12h`, refresh happens around `11h55m` after the last successful knock.

With `open_timeout=0`, the app treats the server allowlist as permanent and refreshes only when the public IP changes.

Mobile operating systems may suspend the app in the background. This feature is app-open refresh, not a guaranteed background daemon.

For always-on router refresh, use the CLI client service on OpenWrt.

## Network warnings

The app warns when:

```text
host resolves to private, CGNAT, reserved, or fake-IP address
TUN/VPN-like interfaces are detected
```

These warnings do not always mean failure. They mean the check or knock path may not represent the real public source IP.

If a server QR URL uses an internal `host=`, edit it to the public IP or domain before using the app outside that private network.

## Time sync

The final UDP knock packet contains a timestamp and HMAC.

Server and client time must stay inside `hmac_window`, usually 60 seconds.

If the sequence looks correct but the server does not add your IP to the allowlist, check the time on both sides.

## Clear profile

Use the top-right menu to clear the saved profile.

This removes local app settings only. It does not change the server.

## Build from source

Install Flutter, then:

```bash
cd flutter
flutter pub get
flutter run
```

Build examples:

```bash
flutter build apk --release
flutter build macos --release
flutter build linux --release -t lib/main_no_scanner.dart
flutter build windows --release -t lib/main_no_scanner.dart
```

Windows and Linux builds use `main_no_scanner.dart` because QR scanner plugin support is not available there.

## When to use CLI instead

Use the CLI client when you need:

```text
router or OpenWrt always-on refresh
system service mode
scripted checks
headless machines
```

Use the Flutter client when you need:

```text
manual mobile unlock
QR import
desktop GUI
quick visual checks
```
