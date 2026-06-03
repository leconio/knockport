import 'package:flutter/material.dart';

import 'app/knockgate_app.dart';

export 'app/knockgate_app.dart';
export 'models/knock_profile.dart';
export 'services/knock_service.dart' show buildKnockPayload;

void main() {
  runApp(const KnockGateApp());
}
