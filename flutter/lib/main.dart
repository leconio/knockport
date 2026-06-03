import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const KnockGateApp());
}

class KnockGateApp extends StatelessWidget {
  const KnockGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KnockGate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class KnockProfile {
  const KnockProfile({
    required this.label,
    required this.host,
    required this.knockPorts,
    required this.protectedPorts,
    required this.seqTimeoutSeconds,
    required this.openTimeout,
  });

  final String label;
  final String host;
  final List<int> knockPorts;
  final List<int> protectedPorts;
  final int seqTimeoutSeconds;
  final String openTimeout;

  factory KnockProfile.defaults() {
    return const KnockProfile(
      label: 'KnockGate',
      host: '',
      knockPorts: <int>[],
      protectedPorts: <int>[5432],
      seqTimeoutSeconds: 10,
      openTimeout: '12h',
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
      seqTimeoutSeconds: json['seqTimeoutSeconds'] is int
          ? json['seqTimeoutSeconds'] as int
          : int.tryParse('${json['seqTimeoutSeconds'] ?? 10}') ?? 10,
      openTimeout: (json['openTimeout'] as String? ?? '12h').trim(),
    );
  }

  factory KnockProfile.fromImportUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl.trim());
    if (uri.scheme != 'knockgate' || uri.host != 'import') {
      throw const FormatException('Not a KnockGate import URL.');
    }
    final params = uri.queryParameters;
    final scheme = params['scheme'] ?? 'udp';
    if (scheme != 'udp') {
      throw const FormatException('Only UDP KnockGate profiles are supported.');
    }
    final host = (params['host'] ?? '').trim();
    if (host.isEmpty) {
      throw const FormatException('Missing host.');
    }
    final knockPorts = parsePorts(params['knock_ports'] ?? '');
    final protectedPorts = parsePorts(params['protected_ports'] ?? '');
    if (knockPorts.isEmpty) {
      throw const FormatException('Missing UDP knock ports.');
    }
    if (protectedPorts.isEmpty) {
      throw const FormatException('Missing protected ports.');
    }
    return KnockProfile(
      label: (params['label'] ?? 'KnockGate').trim(),
      host: host,
      knockPorts: knockPorts,
      protectedPorts: protectedPorts,
      seqTimeoutSeconds: int.tryParse(params['seq_timeout'] ?? '') ?? 10,
      openTimeout: (params['open_timeout'] ?? '12h').trim(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'host': host,
      'knockPorts': knockPorts,
      'protectedPorts': protectedPorts,
      'seqTimeoutSeconds': seqTimeoutSeconds,
      'openTimeout': openTimeout,
    };
  }

  KnockProfile copyWith({
    String? label,
    String? host,
    List<int>? knockPorts,
    List<int>? protectedPorts,
    int? seqTimeoutSeconds,
    String? openTimeout,
  }) {
    return KnockProfile(
      label: label ?? this.label,
      host: host ?? this.host,
      knockPorts: knockPorts ?? this.knockPorts,
      protectedPorts: protectedPorts ?? this.protectedPorts,
      seqTimeoutSeconds: seqTimeoutSeconds ?? this.seqTimeoutSeconds,
      openTimeout: openTimeout ?? this.openTimeout,
    );
  }

  String get knockPortText => knockPorts.join(',');
  String get protectedPortText => protectedPorts.join(',');

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
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _storageKey = 'knockgate_profile_v1';

  final _labelController = TextEditingController();
  final _hostController = TextEditingController();
  final _knockPortsController = TextEditingController();
  final _protectedPortsController = TextEditingController();
  final _seqTimeoutController = TextEditingController();
  final _openTimeoutController = TextEditingController();
  final _importController = TextEditingController();
  final _logController = ScrollController();

  KnockProfile _profile = KnockProfile.defaults();
  StreamSubscription<Uri>? _linkSub;
  bool _busy = false;
  String _status = 'Ready';
  final List<String> _events = <String>[];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _listenForLinks();
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _labelController.dispose();
    _hostController.dispose();
    _knockPortsController.dispose();
    _protectedPortsController.dispose();
    _seqTimeoutController.dispose();
    _openTimeoutController.dispose();
    _importController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        _setProfile(
          KnockProfile.fromJson(jsonDecode(raw) as Map<String, Object?>),
        );
        return;
      } catch (_) {
        // Ignore corrupt local profile and fall back to defaults.
      }
    }
    _setProfile(KnockProfile.defaults());
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_profile.toJson()));
  }

  void _setProfile(KnockProfile profile) {
    _profile = profile;
    _labelController.text = profile.label;
    _hostController.text = profile.host;
    _knockPortsController.text = profile.knockPortText;
    _protectedPortsController.text = profile.protectedPortText;
    _seqTimeoutController.text = profile.seqTimeoutSeconds.toString();
    _openTimeoutController.text = profile.openTimeout;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _listenForLinks() async {
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await _importUrl(initial.toString(), source: 'Initial link');
      }
    } catch (error) {
      _append('Deep link init failed: $error');
    }
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) => _importUrl(uri.toString(), source: 'Deep link'),
      onError: (Object error) => _append('Deep link error: $error'),
    );
  }

  KnockProfile _readForm() {
    final host = _hostController.text.trim();
    final knockPorts = parsePorts(_knockPortsController.text);
    final protectedPorts = parsePorts(_protectedPortsController.text);
    final seqTimeout = int.tryParse(_seqTimeoutController.text.trim()) ?? 10;

    if (host.isEmpty) {
      throw const FormatException('Host is required.');
    }
    if (knockPorts.isEmpty) {
      throw const FormatException('At least one UDP knock port is required.');
    }
    if (protectedPorts.isEmpty) {
      throw const FormatException(
        'At least one protected TCP port is required.',
      );
    }
    if (seqTimeout < 1) {
      throw const FormatException('Sequence timeout must be positive.');
    }
    return KnockProfile(
      label: _labelController.text.trim().isEmpty
          ? 'KnockGate'
          : _labelController.text.trim(),
      host: host,
      knockPorts: knockPorts,
      protectedPorts: protectedPorts,
      seqTimeoutSeconds: seqTimeout,
      openTimeout: _openTimeoutController.text.trim().isEmpty
          ? '12h'
          : _openTimeoutController.text.trim(),
    );
  }

  Future<void> _saveFromForm() async {
    try {
      _setProfile(_readForm());
      await _saveProfile();
      _setStatus('Profile saved');
      _append('Saved ${_profile.label}');
    } catch (error) {
      _setStatus('Invalid profile');
      _showError(error);
    }
  }

  Future<void> _importUrl(String rawUrl, {String source = 'Import'}) async {
    try {
      final profile = KnockProfile.fromImportUrl(rawUrl);
      _setProfile(profile);
      await _saveProfile();
      _importController.clear();
      _setStatus('Imported ${profile.label}');
      _append('$source imported ${profile.host}');
    } catch (error) {
      _setStatus('Import failed');
      _showError(error);
    }
  }

  Future<void> _scanQr() async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _showError(
        'QR scanning is available on Android, iOS, and macOS. Paste the import URL on this platform.',
      );
      return;
    }
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (scanned != null && scanned.trim().isNotEmpty) {
      await _importUrl(scanned, source: 'QR');
    }
  }

  Future<void> _knock() async {
    await _runBusy('Knocking', () async {
      final profile = _readForm();
      _setProfile(profile);
      await _saveProfile();
      final address = await _resolveHost(profile.host);
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      try {
        for (final port in profile.knockPorts) {
          final payload = utf8.encode('knockgate\n');
          socket.send(payload, address, port);
          _append('UDP ${address.address}:$port');
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } finally {
        socket.close();
      }
      _setStatus('Knock sequence sent');
    });
  }

  Future<void> _checkConnectivity() async {
    await _runBusy('Checking', () async {
      final profile = _readForm();
      _setProfile(profile);
      await _saveProfile();
      for (final port in profile.protectedPorts) {
        final result = await checkTcp(profile.host, port);
        _append('${profile.host}:$port/tcp $result');
      }
      _setStatus('Connectivity check finished');
    });
  }

  Future<void> _runBusy(String status, Future<void> Function() work) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = status;
    });
    try {
      await work();
    } catch (error) {
      _setStatus('Failed');
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _setStatus(String status) {
    if (mounted) {
      setState(() => _status = status);
    }
  }

  void _append(String event) {
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _events.insert(0, '[$stamp] $event');
      if (_events.length > 80) {
        _events.removeRange(80, _events.length);
      }
    });
  }

  void _showError(Object error) {
    _append('Error: $error');
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildConfigPanel()),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildLogPanel()),
            ],
          )
        : ListView(
            children: [
              _buildConfigPanel(),
              const SizedBox(height: 16),
              _buildLogPanel(),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('KnockGate Client'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text(_status)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return ListView(
      shrinkWrap: true,
      children: [
        Text('Profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: _labelController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hostController,
          decoration: const InputDecoration(labelText: 'Server host or IP'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _knockPortsController,
          decoration: const InputDecoration(
            labelText: 'UDP knock ports',
            hintText: '37708,31114,25880',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _protectedPortsController,
          decoration: const InputDecoration(
            labelText: 'Protected TCP ports',
            hintText: '5432,9092',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _seqTimeoutController,
                decoration: const InputDecoration(labelText: 'Seq timeout'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _openTimeoutController,
                decoration: const InputDecoration(labelText: 'Open timeout'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _knock,
                icon: const Icon(Icons.key),
                label: const Text('Knock'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _checkConnectivity,
                icon: const Icon(Icons.sensors),
                label: const Text('Check'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Import', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        TextField(
          controller: _importController,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'knockgate:// import URL',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => _importUrl(_importController.text),
              icon: const Icon(Icons.download),
              label: const Text('Import URL'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _saveFromForm,
              icon: const Icon(Icons.save),
              label: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLogPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Activity', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: () => setState(_events.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          constraints: const BoxConstraints(minHeight: 220),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No activity yet.'),
                )
              : ListView.separated(
                  controller: _logController,
                  shrinkWrap: true,
                  itemCount: _events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text(_events[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan KnockGate QR')),
      body: MobileScanner(
        onDetect: (capture) {
          if (_done) {
            return;
          }
          final value = capture.barcodes
              .map((barcode) => barcode.rawValue)
              .whereType<String>()
              .firstWhere(
                (raw) => raw.startsWith('knockgate://'),
                orElse: () => '',
              );
          if (value.isNotEmpty) {
            _done = true;
            Navigator.of(context).pop(value);
          }
        },
      ),
    );
  }
}

Future<InternetAddress> _resolveHost(String host) async {
  final addresses = await InternetAddress.lookup(host);
  if (addresses.isEmpty) {
    throw FormatException('Cannot resolve host: $host');
  }
  return addresses.firstWhere(
    (address) => address.type == InternetAddressType.IPv4,
    orElse: () => addresses.first,
  );
}

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

bool isValidPort(int port) => port >= 1 && port <= 65535;

Future<String> checkTcp(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 3),
    );
    await socket.close();
    return 'OPEN';
  } on SocketException catch (error) {
    final message = error.message.toLowerCase();
    if (message.contains('refused')) {
      return 'REFUSED';
    }
    if (message.contains('timed out') || message.contains('timeout')) {
      return 'FILTERED';
    }
    return 'FAILED (${error.message})';
  } on TimeoutException {
    return 'FILTERED';
  }
}
