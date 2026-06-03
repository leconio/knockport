import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/knock_profile.dart';
import '../../services/connectivity_service.dart';
import '../../services/knock_service.dart';
import '../../services/profile_store.dart';
import '../../utils/crypto_codec.dart';
import '../../utils/ports.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required this.store,
    required this.knockService,
    required this.connectivityService,
  }) {
    for (final controller in profileControllers) {
      controller.addListener(_markFormDirty);
    }
  }

  final ProfileStore store;
  final KnockService knockService;
  final ConnectivityService connectivityService;

  final labelController = TextEditingController();
  final hostController = TextEditingController();
  final knockPortsController = TextEditingController();
  final protectedPortsController = TextEditingController();
  final seqTimeoutController = TextEditingController();
  final hmacWindowController = TextEditingController();
  final openTimeoutController = TextEditingController();
  final secretController = TextEditingController();

  KnockProfile profile = KnockProfile.defaults();
  bool busy = false;
  bool formDirty = false;
  String status = 'Ready';
  String? lastError;
  int errorVersion = 0;

  final List<String> events = <String>[];
  bool _syncingProfile = false;

  List<TextEditingController> get profileControllers => [
    labelController,
    hostController,
    knockPortsController,
    protectedPortsController,
    seqTimeoutController,
    hmacWindowController,
    openTimeoutController,
    secretController,
  ];

  Future<void> init() async {
    setProfile(await store.loadProfile(), notify: false);
    events
      ..clear()
      ..addAll((await store.loadHistory()).take(80));
    notifyListeners();
  }

  void setProfile(KnockProfile nextProfile, {bool notify = true}) {
    profile = nextProfile;
    _syncingProfile = true;
    labelController.text = nextProfile.label;
    hostController.text = nextProfile.host;
    knockPortsController.text = nextProfile.knockPortText;
    protectedPortsController.text = nextProfile.protectedPortText;
    seqTimeoutController.text = nextProfile.seqTimeoutSeconds.toString();
    hmacWindowController.text = nextProfile.hmacWindowSeconds.toString();
    openTimeoutController.text = nextProfile.openTimeout;
    secretController.text = nextProfile.secret;
    _syncingProfile = false;
    formDirty = false;
    if (notify) {
      notifyListeners();
    }
  }

  KnockProfile readForm() {
    final host = hostController.text.trim();
    final knockPorts = parsePorts(knockPortsController.text);
    final protectedPortsRaw = protectedPortsController.text.trim();
    validateProtectedPorts(protectedPortsRaw);
    final protectedPorts = parseProtectedTcpPorts(protectedPortsRaw);
    final seqTimeout = int.tryParse(seqTimeoutController.text.trim()) ?? 10;
    final hmacWindow = int.tryParse(hmacWindowController.text.trim()) ?? 60;
    final secret = secretController.text.trim();

    if (host.isEmpty) {
      throw const FormatException('Host is required.');
    }
    if (knockPorts.isEmpty) {
      throw const FormatException('At least one UDP knock port is required.');
    }
    if (seqTimeout < 1) {
      throw const FormatException('Sequence timeout must be positive.');
    }
    if (hmacWindow < 1) {
      throw const FormatException('HMAC window must be positive.');
    }
    if (secret.isEmpty) {
      throw const FormatException('HMAC secret is required.');
    }
    decodeBase64Url(secret);

    return KnockProfile(
      label: labelController.text.trim().isEmpty
          ? 'KnockGate'
          : labelController.text.trim(),
      host: host,
      knockPorts: knockPorts,
      protectedPorts: protectedPorts,
      protectedPortsText: protectedPortsRaw,
      seqTimeoutSeconds: seqTimeout,
      hmacWindowSeconds: hmacWindow,
      openTimeout: openTimeoutController.text.trim().isEmpty
          ? '12h'
          : openTimeoutController.text.trim(),
      secret: secret,
    );
  }

  Future<void> saveFromForm() async {
    try {
      final nextProfile = readForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      status = 'Profile saved';
      append('Saved ${nextProfile.label}', notify: false);
      notifyListeners();
    } catch (error) {
      _reportError('Invalid profile', error);
    }
  }

  Future<void> importUrl(String rawUrl, {String source = 'Import'}) async {
    try {
      final nextProfile = KnockProfile.fromImportUrl(rawUrl);
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      status = 'Imported ${nextProfile.label}';
      append('$source imported ${nextProfile.host}', notify: false);
      notifyListeners();
    } catch (error) {
      _reportError('Import failed', error);
    }
  }

  Future<void> knock() async {
    await _runBusy('Knocking', () async {
      final nextProfile = readForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      for (final event in await knockService.knock(nextProfile)) {
        append(event, notify: false);
      }
      status = 'Knock sequence sent';
    });
  }

  Future<void> checkConnectivity() async {
    await _runBusy('Checking', () async {
      final nextProfile = readForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      if (nextProfile.protectedPorts.isEmpty) {
        append(
          'No TCP protected ports to check. UDP-only ports cannot be confirmed by TCP check.',
          notify: false,
        );
        status = 'Connectivity check skipped';
        return;
      }
      for (final port in nextProfile.protectedPorts) {
        final result = await connectivityService.checkTcp(
          nextProfile.host,
          port,
        );
        append('${nextProfile.host}:$port/tcp $result', notify: false);
      }
      status = 'Connectivity check finished';
    });
  }

  Future<void> clearHistory() async {
    events.clear();
    await store.saveHistory(events);
    notifyListeners();
  }

  void append(String event, {bool notify = true}) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    events.insert(0, '[$stamp] $event');
    if (events.length > 80) {
      events.removeRange(80, events.length);
    }
    unawaited(store.saveHistory(events));
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _runBusy(String nextStatus, Future<void> Function() work) async {
    if (busy) {
      return;
    }
    busy = true;
    status = nextStatus;
    notifyListeners();
    try {
      await work();
    } catch (error) {
      _reportError('Failed', error, notify: false);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _markFormDirty() {
    if (_syncingProfile || formDirty) {
      return;
    }
    formDirty = true;
    notifyListeners();
  }

  void _reportError(String nextStatus, Object error, {bool notify = true}) {
    status = nextStatus;
    lastError = '$error';
    errorVersion++;
    append('Error: $error', notify: false);
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final controller in profileControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
