import 'dart:convert';

List<int> decodeBase64Url(String value) {
  var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  while (normalized.length % 4 != 0) {
    normalized += '=';
  }
  final bytes = base64.decode(normalized);
  if (bytes.length < 32) {
    throw const FormatException('HMAC secret must be at least 32 bytes.');
  }
  return bytes;
}

String base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
