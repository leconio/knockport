import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:knockgate_client/features/home/home_controller.dart';
import 'package:knockgate_client/services/auto_refresh_service.dart';
import 'package:knockgate_client/services/connectivity_service.dart';
import 'package:knockgate_client/services/knock_service.dart';
import 'package:knockgate_client/services/network_warning_service.dart';
import 'package:knockgate_client/services/profile_store.dart';

void main() {
  const importUrl =
      'knockgate://import/v1'
      '?scheme=udp-hmac'
      '&host=example.com'
      '&knock_ports=45669%2C65075%2C31244'
      '&protected_ports=5432%2C9092%2Ftcp'
      '&seq_timeout=10'
      '&open_timeout=12h'
      '&hmac_window=60'
      '&secret=MTIzNDU2Nzg5MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI'
      '&label=Imported';

  HomeController buildController({NetworkWarningService? warningService}) {
    return HomeController(
      store: ProfileStore(),
      knockService: KnockService(),
      connectivityService: ConnectivityService(),
      autoRefreshService: AutoRefreshService(ipCheckUrls: const <String>[]),
      networkWarningService: warningService ?? _NoopNetworkWarningService(),
    );
  }

  test('import URL saves profile and fills Knock and Check fields', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.init();
    await controller.importUrl(importUrl);

    expect(controller.labelController.text, 'Imported');
    expect(controller.hostController.text, 'example.com');
    expect(controller.knockPortsController.text, '45669,65075,31244');
    expect(controller.protectedPortsController.text, '5432,9092/tcp');
    expect(controller.seqTimeoutController.text, '10');
    expect(controller.hmacWindowController.text, '60');

    final restored = buildController();
    addTearDown(restored.dispose);
    await restored.init();

    expect(restored.labelController.text, 'Imported');
    expect(restored.hostController.text, 'example.com');
    expect(restored.knockPortsController.text, '45669,65075,31244');
    expect(restored.protectedPortsController.text, '5432,9092/tcp');
  });

  test('knock logs keep newest item first', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.init();
    controller.addKnockLog('first');
    controller.addKnockLog('second');

    expect(controller.knockLogs.first, contains('second'));
    expect(controller.knockLogs.last, contains('first'));
  });

  test('host warning is exposed for the host field', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = buildController(
      warningService: _FixedNetworkWarningService([
        'Warning: example.com resolved to 198.18.0.1, a private/CGNAT/fake-IP/reserved address.',
      ]),
    );
    addTearDown(controller.dispose);

    await controller.init();
    controller.hostController.text = 'example.com';
    await controller.refreshHostWarning();

    expect(controller.hostWarning, contains('Private/fake-IP'));
  });

  test('auto refresh setting is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = buildController();
    addTearDown(controller.dispose);

    await controller.init();
    await controller.setAutoRefreshEnabled(true);

    final restored = buildController();
    addTearDown(restored.dispose);
    await restored.init();

    expect(restored.autoRefreshEnabled, isTrue);
  });
}

class _NoopNetworkWarningService extends NetworkWarningService {
  @override
  Future<List<String>> warningsForHost(
    String host, {
    InternetAddress? resolvedAddress,
  }) async {
    return const <String>[];
  }
}

class _FixedNetworkWarningService extends NetworkWarningService {
  _FixedNetworkWarningService(this.warnings);

  final List<String> warnings;

  @override
  Future<List<String>> warningsForHost(
    String host, {
    InternetAddress? resolvedAddress,
  }) async {
    return warnings;
  }
}
