import 'dart:io';

class NetworkWarningService {
  Future<List<String>> warningsForHost(
    String host, {
    InternetAddress? resolvedAddress,
  }) async {
    final warnings = <String>[];
    final address = resolvedAddress ?? await _resolveIPv4(host);
    if (address != null && _isSuspiciousAddress(address)) {
      warnings.add(
        'Warning: $host resolved to ${address.address}, a private/CGNAT/fake-IP/reserved address. '
        'If this is not the real server address, knock/check may use the wrong network path.',
      );
    }

    final tunInterfaces = await _tunLikeInterfaces();
    if (tunInterfaces.isNotEmpty) {
      warnings.add(
        'Warning: detected TUN/VPN-like interface(s): ${tunInterfaces.join(', ')}. '
        'If traffic to $host is routed through them or fake-IP DNS, check results may be unreliable.',
      );
    }
    return warnings;
  }

  Future<InternetAddress?> _resolveIPv4(String host) async {
    try {
      final addresses = await InternetAddress.lookup(host);
      for (final address in addresses) {
        if (address.type == InternetAddressType.IPv4) {
          return address;
        }
      }
      return addresses.isEmpty ? null : addresses.first;
    } on SocketException {
      return null;
    }
  }

  bool _isSuspiciousAddress(InternetAddress address) {
    if (address.isLoopback || address.isLinkLocal) {
      return true;
    }
    if (address.type != InternetAddressType.IPv4) {
      return false;
    }
    final bytes = address.rawAddress;
    if (bytes.length < 4) {
      return false;
    }
    final a = bytes[0];
    final b = bytes[1];
    return a == 10 ||
        a == 127 ||
        (a == 169 && b == 254) ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168) ||
        (a == 100 && b >= 64 && b <= 127) ||
        (a == 198 && (b == 18 || b == 19));
  }

  Future<List<String>> _tunLikeInterfaces() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLinkLocal: true,
        type: InternetAddressType.any,
      );
      final names = <String>{};
      for (final iface in interfaces) {
        final lower = iface.name.toLowerCase();
        if (_tunLikeName(lower)) {
          names.add(iface.name);
        }
      }
      final sorted = names.toList()..sort();
      return sorted;
    } on SocketException {
      return const <String>[];
    }
  }

  bool _tunLikeName(String name) {
    return name.startsWith('tun') ||
        name.startsWith('tap') ||
        name.startsWith('utun') ||
        name.startsWith('wg') ||
        name.startsWith('tailscale') ||
        name.startsWith('zt') ||
        name.startsWith('clash') ||
        name.startsWith('mihomo') ||
        name.startsWith('sing') ||
        name.startsWith('vpn');
  }
}
