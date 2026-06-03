# KnockGate Client

Flutter GUI client for KnockGate UDP port knocking.

The app imports a `knockgate://` profile, sends the UDP-HMAC knock sequence in order, and checks protected TCP ports after the firewall allowlist opens.

## Supported platforms

- Android
- iOS
- macOS
- Windows
- Linux

QR scanning is implemented for Android, iOS, and macOS. On Windows and Linux, paste the import URL or edit the profile manually.

## Import URL

Example:

```text
knockgate://import/v1?scheme=udp-hmac&host=example.com&knock_ports=37708,31114,25880&protected_ports=5432&seq_timeout=10&open_timeout=12h&hmac_window=60&secret=BASE64URL_SECRET&label=Home
```

Fields:

- `scheme=udp-hmac` is required.
- `host` is the server hostname or IP.
- `knock_ports` is the ordered UDP knock sequence.
- `protected_ports` are TCP ports to check after knocking.
- `seq_timeout` is the server-side ordered knock timeout.
- `open_timeout` is the nftables allowlist timeout.
- `hmac_window` is the timestamp tolerance in seconds.
- `secret` is the base64url HMAC secret.
- `label` is the local profile name.

## Usage

1. Import a profile by URL, scan a QR code, or enter the fields manually.
2. Press `Save`.
3. Press `Knock` to send UDP packets in the configured order.
4. Press `Check` to test protected TCP ports.

Check results:

- `OPEN`: TCP handshake succeeded.
- `REFUSED`: firewall path is open, but no service is listening.
- `FILTERED`: connection timed out, usually still blocked by firewall.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

Build examples:

```sh
flutter build apk
flutter build ios
flutter build macos
flutter build windows
flutter build linux
```

Windows and Linux custom protocol registration is packaging-specific. The app supports parsing `knockgate://` URLs after launch; installer-level protocol registration should be added when release packaging is introduced.
