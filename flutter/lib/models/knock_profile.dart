import '../utils/crypto_codec.dart';
import '../utils/ports.dart';

class KnockProfile {
  const KnockProfile({
    required this.label,
    required this.host,
    required this.knockPorts,
    required this.protectedPorts,
    required this.protectedPortsText,
    required this.seqTimeoutSeconds,
    required this.hmacWindowSeconds,
    required this.openTimeout,
    required this.secret,
  });

  final String label;
  final String host;
  final List<int> knockPorts;
  final List<int> protectedPorts;
  final String protectedPortsText;
  final int seqTimeoutSeconds;
  final int hmacWindowSeconds;
  final String openTimeout;
  final String secret;

  factory KnockProfile.defaults() {
    return const KnockProfile(
      label: 'KnockGate',
      host: '',
      knockPorts: <int>[],
      protectedPorts: <int>[5432],
      protectedPortsText: '5432',
      seqTimeoutSeconds: 10,
      hmacWindowSeconds: 60,
      openTimeout: '12h',
      secret: '',
    );
  }

  factory KnockProfile.fromJson(Map<String, Object?> json) {
    return KnockProfile(
      label: (json['label'] as String?)?.trim().isNotEmpty == true
          ? (json['label'] as String).trim()
          : 'KnockGate',
      host: (json['host'] as String? ?? '').trim(),
      knockPorts: _parsePortList(json['knockPorts']),
      protectedPorts: _parsePortList(json['protectedPorts']),
      protectedPortsText: _protectedTextFromJson(json),
      seqTimeoutSeconds: json['seqTimeoutSeconds'] is int
          ? json['seqTimeoutSeconds'] as int
          : int.tryParse('${json['seqTimeoutSeconds'] ?? 10}') ?? 10,
      hmacWindowSeconds: json['hmacWindowSeconds'] is int
          ? json['hmacWindowSeconds'] as int
          : int.tryParse('${json['hmacWindowSeconds'] ?? 60}') ?? 60,
      openTimeout: (json['openTimeout'] as String? ?? '12h').trim(),
      secret: (json['secret'] as String? ?? '').trim(),
    );
  }

  factory KnockProfile.fromImportUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl.trim());
    if (uri.scheme != 'knockgate' || uri.host != 'import') {
      throw const FormatException('Not a KnockGate import URL.');
    }
    final params = uri.queryParameters;
    final scheme = params['scheme'] ?? 'udp-hmac';
    if (scheme != 'udp-hmac') {
      throw const FormatException(
        'Only UDP-HMAC KnockGate profiles are supported.',
      );
    }
    final host = (params['host'] ?? '').trim();
    if (host.isEmpty) {
      throw const FormatException('Missing host.');
    }
    final knockPorts = parsePorts(params['knock_ports'] ?? '');
    final protectedPortsRaw = params['protected_ports'] ?? '';
    validateProtectedPorts(protectedPortsRaw);
    final protectedPorts = parseProtectedTcpPorts(protectedPortsRaw);
    if (knockPorts.isEmpty) {
      throw const FormatException('Missing UDP knock ports.');
    }
    final secret = (params['secret'] ?? '').trim();
    if (secret.isEmpty) {
      throw const FormatException('Missing HMAC secret.');
    }
    decodeBase64Url(secret);
    return KnockProfile(
      label: (params['label'] ?? 'KnockGate').trim(),
      host: host,
      knockPorts: knockPorts,
      protectedPorts: protectedPorts,
      protectedPortsText: protectedPortsRaw,
      seqTimeoutSeconds: int.tryParse(params['seq_timeout'] ?? '') ?? 10,
      hmacWindowSeconds: int.tryParse(params['hmac_window'] ?? '') ?? 60,
      openTimeout: (params['open_timeout'] ?? '12h').trim(),
      secret: secret,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'host': host,
      'knockPorts': knockPorts,
      'protectedPorts': protectedPorts,
      'protectedPortsText': protectedPortsText,
      'seqTimeoutSeconds': seqTimeoutSeconds,
      'hmacWindowSeconds': hmacWindowSeconds,
      'openTimeout': openTimeout,
      'secret': secret,
    };
  }

  KnockProfile copyWith({
    String? label,
    String? host,
    List<int>? knockPorts,
    List<int>? protectedPorts,
    String? protectedPortsText,
    int? seqTimeoutSeconds,
    int? hmacWindowSeconds,
    String? openTimeout,
    String? secret,
  }) {
    return KnockProfile(
      label: label ?? this.label,
      host: host ?? this.host,
      knockPorts: knockPorts ?? this.knockPorts,
      protectedPorts: protectedPorts ?? this.protectedPorts,
      protectedPortsText: protectedPortsText ?? this.protectedPortsText,
      seqTimeoutSeconds: seqTimeoutSeconds ?? this.seqTimeoutSeconds,
      hmacWindowSeconds: hmacWindowSeconds ?? this.hmacWindowSeconds,
      openTimeout: openTimeout ?? this.openTimeout,
      secret: secret ?? this.secret,
    );
  }

  String get knockPortText => knockPorts.join(',');
  String get protectedPortText => protectedPortsText;

  static List<int> _parsePortList(Object? value) {
    if (value is List) {
      return value
          .map((item) => int.tryParse('$item'))
          .whereType<int>()
          .where(isValidPort)
          .toList();
    }
    return parsePorts('$value');
  }

  static String _protectedTextFromJson(Map<String, Object?> json) {
    final text = (json['protectedPortsText'] as String? ?? '').trim();
    if (text.isNotEmpty) {
      return text;
    }
    return _parsePortList(json['protectedPorts']).join(',');
  }
}
