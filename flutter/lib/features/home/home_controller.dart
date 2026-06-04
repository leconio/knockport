import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/knock_profile.dart';
import '../../services/connectivity_service.dart';
import '../../services/knock_service.dart';
import '../../services/network_warning_service.dart';
import '../../services/profile_store.dart';
import '../../utils/crypto_codec.dart';
import '../../utils/ports.dart';

class HomeController extends ChangeNotifier {
  HomeController({
    required this.store,
    required this.knockService,
    required this.connectivityService,
    NetworkWarningService? networkWarningService,
  }) : networkWarningService =
           networkWarningService ?? NetworkWarningService() {
    for (final controller in profileControllers) {
      controller.addListener(_markFormDirty);
    }
    hostController.addListener(_scheduleHostWarningRefresh);
  }

  final ProfileStore store;
  final KnockService knockService;
  final ConnectivityService connectivityService;
  final NetworkWarningService networkWarningService;

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
  bool knockDirty = false;
  bool checkDirty = false;
  String? lastError;
  String? hostWarning;
  int errorVersion = 0;
  List<String> checkResults = const <String>[];
  List<String> knockLogs = const <String>[];

  bool _syncingProfile = false;
  Timer? _hostWarningTimer;
  int _hostWarningGeneration = 0;

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

  List<TextEditingController> get _knockControllers => [
    labelController,
    hostController,
    knockPortsController,
    seqTimeoutController,
    hmacWindowController,
    secretController,
  ];

  List<TextEditingController> get _checkControllers => [
    hostController,
    protectedPortsController,
  ];

  Future<void> init() async {
    setProfile(await store.loadProfile(), notify: false);
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
    knockDirty = false;
    checkDirty = false;
    unawaited(refreshHostWarning());
    if (notify) {
      notifyListeners();
    }
  }

  KnockProfile readKnockForm() {
    final host = hostController.text.trim();
    final knockPorts = parsePorts(knockPortsController.text);
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
      protectedPorts: profile.protectedPorts,
      protectedPortsText: profile.protectedPortsText,
      seqTimeoutSeconds: seqTimeout,
      hmacWindowSeconds: hmacWindow,
      openTimeout: profile.openTimeout,
      secret: secret,
    );
  }

  KnockProfile readCheckForm() {
    final host = hostController.text.trim();
    final protectedPortsRaw = protectedPortsController.text.trim();
    validateProtectedPorts(protectedPortsRaw);
    final protectedPorts = parseProtectedTcpPorts(protectedPortsRaw);
    if (host.isEmpty) {
      throw const FormatException('Host is required.');
    }
    return profile.copyWith(
      host: host,
      protectedPorts: protectedPorts,
      protectedPortsText: protectedPortsRaw,
    );
  }

  Future<void> saveKnockFromForm() async {
    try {
      final nextProfile = readKnockForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      notifyListeners();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> saveCheckFromForm() async {
    try {
      final nextProfile = readCheckForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      notifyListeners();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> importUrl(String rawUrl, {String source = 'Import'}) async {
    try {
      final nextProfile = KnockProfile.fromImportUrl(rawUrl);
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      notifyListeners();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> knock({KnockLogSink? onLog}) async {
    await _runBusy(() async {
      final nextProfile = readKnockForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      await knockService.knock(nextProfile, onLog: onLog);
    }, rethrowErrors: onLog != null);
  }

  void addKnockLog(String message) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    knockLogs = <String>['[$stamp] $message', ...knockLogs].take(120).toList();
    notifyListeners();
  }

  void clearKnockLogs() {
    knockLogs = const <String>[];
    notifyListeners();
  }

  Future<void> checkConnectivity() async {
    await _runBusy(() async {
      final nextProfile = readCheckForm();
      setProfile(nextProfile, notify: false);
      await store.saveProfile(nextProfile);
      if (nextProfile.protectedPorts.isEmpty) {
        checkResults = const <String>['No TCP protected ports to check.'];
        return;
      }
      final results = <String>[];
      for (final port in nextProfile.protectedPorts) {
        final result = await connectivityService.checkTcp(
          nextProfile.host,
          port,
        );
        results.add('${nextProfile.host}:$port/tcp $result');
      }
      checkResults = results;
    });
  }

  Future<void> clearProfile() async {
    final defaults = KnockProfile.defaults();
    setProfile(defaults, notify: false);
    checkResults = const <String>[];
    knockLogs = const <String>[];
    await store.saveProfile(defaults);
    notifyListeners();
  }

  Future<void> _runBusy(
    Future<void> Function() work, {
    bool rethrowErrors = false,
  }) async {
    if (busy) {
      return;
    }
    busy = true;
    notifyListeners();
    try {
      await work();
    } catch (error) {
      _reportError(error, notify: false);
      if (rethrowErrors) {
        rethrow;
      }
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _markFormDirty() {
    if (_syncingProfile) {
      return;
    }
    final changed = _updateDirtyFlags();
    if (!changed) {
      return;
    }
    notifyListeners();
  }

  void _scheduleHostWarningRefresh() {
    if (_syncingProfile) {
      return;
    }
    _hostWarningTimer?.cancel();
    _hostWarningTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(refreshHostWarning()),
    );
  }

  Future<void> refreshHostWarning() async {
    final generation = ++_hostWarningGeneration;
    final host = hostController.text.trim();
    if (host.isEmpty) {
      _setHostWarning(null, generation);
      return;
    }
    final warnings = await networkWarningService.warningsForHost(host);
    if (generation != _hostWarningGeneration) {
      return;
    }
    _setHostWarning(_summarizeHostWarnings(warnings), generation);
  }

  void _setHostWarning(String? warning, int generation) {
    if (generation != _hostWarningGeneration || hostWarning == warning) {
      return;
    }
    hostWarning = warning;
    notifyListeners();
  }

  String? _summarizeHostWarnings(List<String> warnings) {
    if (warnings.isEmpty) {
      return null;
    }
    final hasAddressWarning = warnings.any(
      (warning) =>
          warning.contains('private') ||
          warning.contains('CGNAT') ||
          warning.contains('fake-IP') ||
          warning.contains('reserved'),
    );
    final hasTunWarning = warnings.any(
      (warning) => warning.contains('TUN') || warning.contains('VPN'),
    );
    if (hasAddressWarning && hasTunWarning) {
      return 'Private/fake-IP address and TUN/VPN detected; use the real public host or bypass proxy if results look wrong.';
    }
    if (hasAddressWarning) {
      return 'Private/fake-IP/reserved address detected; replace with public IP/domain for external clients.';
    }
    return 'TUN/VPN network detected; knock/check may use a proxy path.';
  }

  bool _updateDirtyFlags() {
    final nextKnockDirty = _knockControllers.any(_controllerChanged);
    final nextCheckDirty = _checkControllers.any(_controllerChanged);
    final changed =
        knockDirty != nextKnockDirty || checkDirty != nextCheckDirty;
    knockDirty = nextKnockDirty;
    checkDirty = nextCheckDirty;
    return changed;
  }

  bool _controllerChanged(TextEditingController controller) {
    if (controller == labelController) {
      return controller.text != profile.label;
    }
    if (controller == hostController) {
      return controller.text != profile.host;
    }
    if (controller == knockPortsController) {
      return controller.text != profile.knockPortText;
    }
    if (controller == protectedPortsController) {
      return controller.text != profile.protectedPortText;
    }
    if (controller == seqTimeoutController) {
      return controller.text != profile.seqTimeoutSeconds.toString();
    }
    if (controller == hmacWindowController) {
      return controller.text != profile.hmacWindowSeconds.toString();
    }
    if (controller == secretController) {
      return controller.text != profile.secret;
    }
    return false;
  }

  void _reportError(Object error, {bool notify = true}) {
    lastError = '$error';
    errorVersion++;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _hostWarningTimer?.cancel();
    for (final controller in profileControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
