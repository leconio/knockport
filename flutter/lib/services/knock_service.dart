import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/knock_profile.dart';
import '../utils/crypto_codec.dart';

typedef KnockLogSink = void Function(String message);

class KnockService {
  Future<void> knock(KnockProfile profile, {KnockLogSink? onLog}) async {
    onLog?.call('Resolving ${profile.host}');
    final address = await _resolveHost(profile.host);
    onLog?.call('Resolved ${profile.host} -> ${address.address}');
    onLog?.call('Opening UDP socket');
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    try {
      for (var step = 0; step < profile.knockPorts.length; step++) {
        final port = profile.knockPorts[step];
        final isFinal = step == profile.knockPorts.length - 1;
        onLog?.call(
          'Step ${step + 1}/${profile.knockPorts.length}: ${address.address}:$port/udp${isFinal ? ' with HMAC' : ''}',
        );
        final payload = isFinal
            ? buildKnockPayload(profile.secret, port, step)
            : utf8.encode('KG0|$step');
        socket.send(payload, address, port);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      onLog?.call('Knock sequence sent');
    } finally {
      socket.close();
      onLog?.call('UDP socket closed');
    }
  }
}

Future<InternetAddress> _resolveHost(String host) async {
  final addresses = await InternetAddress.lookup(host);
  if (addresses.isEmpty) {
    throw FormatException('Cannot resolve host: $host');
  }
  return addresses.firstWhere(
    (address) => address.type == InternetAddressType.IPv4,
    orElse: () => addresses.first,
  );
}

List<int> buildKnockPayload(String secret, int port, int step) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final nonce = randomBytes(4);
  final message = <int>[
    0x4b,
    0x31,
    (port >> 8) & 0xff,
    port & 0xff,
    step & 0xff,
    (now >> 24) & 0xff,
    (now >> 16) & 0xff,
    (now >> 8) & 0xff,
    now & 0xff,
    ...nonce,
  ];
  final mac = Hmac(sha256, decodeBase64Url(secret)).convert(message);
  return <int>[
    0x4b,
    0x31,
    step & 0xff,
    (now >> 24) & 0xff,
    (now >> 16) & 0xff,
    (now >> 8) & 0xff,
    now & 0xff,
    ...nonce,
    ...mac.bytes.take(8),
  ];
}

List<int> randomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
