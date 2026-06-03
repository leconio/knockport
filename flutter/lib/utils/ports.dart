List<int> parsePorts(String text) {
  final seen = <int>{};
  final ports = <int>[];
  for (final part in text.split(RegExp(r'[\s,]+'))) {
    if (part.trim().isEmpty) {
      continue;
    }
    final port = int.tryParse(part.trim());
    if (port == null || !isValidPort(port)) {
      throw FormatException('Invalid port: $part');
    }
    if (seen.add(port)) {
      ports.add(port);
    }
  }
  return ports;
}

List<int> parseProtectedTcpPorts(String text) {
  final seen = <int>{};
  final ports = <int>[];
  for (final rawPart in text.split(RegExp(r'[\s,]+'))) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      continue;
    }
    final pieces = part.split('/');
    if (pieces.length > 2) {
      throw FormatException('Invalid protected port: $part');
    }
    final port = int.tryParse(pieces.first);
    if (port == null || !isValidPort(port)) {
      throw FormatException('Invalid port: $part');
    }
    final proto = pieces.length == 2 ? pieces[1].toLowerCase() : 'both';
    if (proto != 'tcp' && proto != 'udp' && proto != 'both') {
      throw FormatException('Invalid protocol: $part');
    }
    if (proto == 'udp') {
      continue;
    }
    if (seen.add(port)) {
      ports.add(port);
    }
  }
  return ports;
}

void validateProtectedPorts(String text) {
  var count = 0;
  for (final rawPart in text.split(RegExp(r'[\s,]+'))) {
    final part = rawPart.trim();
    if (part.isEmpty) {
      continue;
    }
    count++;
    final pieces = part.split('/');
    if (pieces.length > 2) {
      throw FormatException('Invalid protected port: $part');
    }
    final port = int.tryParse(pieces.first);
    if (port == null || !isValidPort(port)) {
      throw FormatException('Invalid port: $part');
    }
    if (pieces.length == 2) {
      final proto = pieces[1].toLowerCase();
      if (proto != 'tcp' && proto != 'udp') {
        throw FormatException('Invalid protocol: $part');
      }
    }
  }
  if (count == 0) {
    throw const FormatException('At least one protected port is required.');
  }
}

bool isValidPort(int port) => port >= 1 && port <= 65535;
