import 'package:flutter/material.dart';

import 'app/knockgate_app.dart';
import 'features/scan/scan_page.dart';

export 'app/knockgate_app.dart';
export 'models/knock_profile.dart';
export 'services/knock_service.dart' show buildKnockPayload;

Future<String?> _openScanPage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
}

void main() {
  runApp(KnockGateApp(scanQr: _openScanPage));
}
