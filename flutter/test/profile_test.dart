import 'package:flutter_test/flutter_test.dart';
import 'package:knockgate_client/main.dart';

void main() {
  test(
    'import URL keeps protected protocol text and checks TCP-capable ports',
    () {
      final profile = KnockProfile.fromImportUrl(
        'knockgate://import/v1'
        '?scheme=udp-hmac'
        '&host=example.com'
        '&knock_ports=45669%2C65075%2C31244'
        '&protected_ports=5432%2C9092%2Ftcp%2C51820%2Fudp'
        '&seq_timeout=10'
        '&open_timeout=12h'
        '&hmac_window=60'
        '&secret=MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI'
        '&label=KnockGate',
      );

      expect(profile.host, 'example.com');
      expect(profile.knockPorts, <int>[45669, 65075, 31244]);
      expect(profile.protectedPortsText, '5432,9092/tcp,51820/udp');
      expect(profile.protectedPorts, <int>[5432, 9092]);
    },
  );

  test('compact final payload matches server wire shape', () {
    final payload = buildKnockPayload(
      'MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI',
      31244,
      2,
    );

    expect(payload.length, 19);
    expect(payload[0], 0x4b);
    expect(payload[1], 0x31);
    expect(payload[2], 2);
  });
}
