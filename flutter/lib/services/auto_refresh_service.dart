import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AutoRefreshDecision {
  const AutoRefreshDecision({
    required this.shouldKnock,
    required this.reason,
    this.nextRefreshAfter,
  });

  final bool shouldKnock;
  final String reason;
  final Duration? nextRefreshAfter;
}

class AutoRefreshService {
  AutoRefreshService({List<String>? ipCheckUrls})
    : ipCheckUrls = ipCheckUrls ?? defaultIpCheckUrls;

  static const defaultIpCheckUrls = <String>[
    'https://api.ipify.org',
    'http://api.ipify.org',
    'https://checkip.amazonaws.com',
    'http://checkip.amazonaws.com',
    'https://ifconfig.me/ip',
    'http://ifconfig.me/ip',
    'https://cloudflare.com/cdn-cgi/trace',
  ];

  final List<String> ipCheckUrls;

  Future<String> detectPublicIPv4({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final errors = <String>[];
    for (final endpoint in ipCheckUrls) {
      final trimmed = endpoint.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      try {
        final ip = await _fetchIPv4(trimmed, timeout);
        if (ip != null && !_isSuspiciousIPv4(ip)) {
          return ip;
        }
        errors.add('$trimmed: no public IPv4');
      } catch (error) {
        errors.add('$trimmed: $error');
      }
    }
    throw StateError(
      errors.isEmpty ? 'no public IP endpoint' : errors.join('; '),
    );
  }

  AutoRefreshDecision shouldRefresh({
    required String currentIP,
    required String? lastIP,
    required DateTime? lastKnock,
    required String openTimeout,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    if (currentIP != lastIP) {
      return AutoRefreshDecision(
        shouldKnock: true,
        reason: 'public IP changed: ${_emptyDash(lastIP)} -> $currentIP',
      );
    }
    if (lastKnock == null) {
      return const AutoRefreshDecision(
        shouldKnock: true,
        reason: 'no previous successful knock recorded',
      );
    }

    final parsed = parseOpenTimeout(openTimeout);
    if (parsed == null) {
      return AutoRefreshDecision(
        shouldKnock: true,
        reason:
            'cannot parse open_timeout "$openTimeout"; refreshing defensively',
      );
    }
    if (parsed == Duration.zero) {
      return AutoRefreshDecision(
        shouldKnock: false,
        reason: 'public IP unchanged ($currentIP), open_timeout is permanent',
      );
    }

    final refreshAfter = refreshAfterDuration(parsed);
    final elapsed = currentTime.difference(lastKnock);
    if (elapsed >= refreshAfter) {
      return AutoRefreshDecision(
        shouldKnock: true,
        reason:
            'allowlist refresh threshold reached: elapsed=${_formatDuration(elapsed)} threshold=${_formatDuration(refreshAfter)} open_timeout=${_formatDuration(parsed)}',
      );
    }
    return AutoRefreshDecision(
      shouldKnock: false,
      reason:
          'public IP unchanged ($currentIP), next refresh in about ${_formatDuration(refreshAfter - elapsed)}',
      nextRefreshAfter: refreshAfter - elapsed,
    );
  }

  Future<String?> _fetchIPv4(String endpoint, Duration timeout) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final uri = Uri.parse(endpoint);
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final text = await response.transform(utf8.decoder).join();
      return firstIPv4(text);
    } finally {
      client.close(force: true);
    }
  }
}

Duration? parseOpenTimeout(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return const Duration(hours: 12);
  }
  if (trimmed == '0') {
    return Duration.zero;
  }
  final seconds = double.tryParse(trimmed);
  if (seconds != null) {
    if (seconds < 0) {
      return null;
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  final match = RegExp(
    r'^([0-9]+(?:\.[0-9]+)?)(ms|s|m|h|d|w)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (match == null) {
    return null;
  }
  final value = double.tryParse(match.group(1)!);
  if (value == null || value < 0) {
    return null;
  }
  final unit = match.group(2)!.toLowerCase();
  final milliseconds = switch (unit) {
    'ms' => value,
    's' => value * 1000,
    'm' => value * 60 * 1000,
    'h' => value * 60 * 60 * 1000,
    'd' => value * 24 * 60 * 60 * 1000,
    'w' => value * 7 * 24 * 60 * 60 * 1000,
    _ => -1,
  };
  if (milliseconds < 0) {
    return null;
  }
  return Duration(milliseconds: milliseconds.round());
}

Duration refreshAfterDuration(Duration openTimeout) {
  if (openTimeout <= Duration.zero) {
    return Duration.zero;
  }
  var margin = Duration(microseconds: openTimeout.inMicroseconds ~/ 10);
  if (margin > const Duration(minutes: 5)) {
    margin = const Duration(minutes: 5);
  }
  if (margin <= Duration.zero) {
    margin = const Duration(seconds: 1);
  }
  var refreshAfter = openTimeout - margin;
  final half = Duration(microseconds: openTimeout.inMicroseconds ~/ 2);
  if (refreshAfter < half) {
    refreshAfter = half;
  }
  return refreshAfter;
}

String? firstIPv4(String text) {
  final matches = RegExp(r'(?:\d{1,3}\.){3}\d{1,3}').allMatches(text);
  for (final match in matches) {
    final candidate = match.group(0)!;
    final parts = candidate.split('.');
    if (parts.length == 4 &&
        parts.every((part) {
          final value = int.tryParse(part);
          return value != null && value >= 0 && value <= 255;
        })) {
      return parts.map((part) => int.parse(part).toString()).join('.');
    }
  }
  return null;
}

bool _isSuspiciousIPv4(String ip) {
  final parts = ip.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((part) => part == null)) {
    return true;
  }
  final a = parts[0]!;
  final b = parts[1]!;
  return a == 0 ||
      a == 10 ||
      a == 127 ||
      (a == 100 && b >= 64 && b <= 127) ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 0) ||
      (a == 192 && b == 168) ||
      (a == 198 && (b == 18 || b == 19)) ||
      a >= 224;
}

String _emptyDash(String? value) {
  if (value == null || value.isEmpty) {
    return '-';
  }
  return value;
}

String _formatDuration(Duration duration) {
  if (duration.inSeconds < 1) {
    return '${duration.inMilliseconds}ms';
  }
  if (duration.inMinutes < 1) {
    return '${duration.inSeconds}s';
  }
  if (duration.inHours < 1) {
    return '${duration.inMinutes}m${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}s';
  }
  return '${duration.inHours}h${duration.inMinutes.remainder(60).toString().padLeft(2, '0')}m';
}
