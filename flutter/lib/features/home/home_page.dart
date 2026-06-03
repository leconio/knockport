import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../scan/scan_page.dart';
import 'home_controller.dart';
import 'settings_page.dart';

enum _HomeMenuAction { importUrl, scanQr, clearHistory, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _importController = TextEditingController();
  final _logController = ScrollController();
  StreamSubscription<Uri>? _linkSub;
  int _shownErrorVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForLinks());
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _importController.dispose();
    _logController.dispose();
    super.dispose();
  }

  Future<void> _listenForLinks() async {
    if (!mounted) {
      return;
    }
    final controller = context.read<HomeController>();
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await controller.importUrl(initial.toString(), source: 'Initial link');
      }
    } catch (error) {
      controller.append('Deep link init failed: $error');
    }
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) => controller.importUrl(uri.toString(), source: 'Deep link'),
      onError: (Object error) => controller.append('Deep link error: $error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    _showPendingError(controller);

    final wide = MediaQuery.sizeOf(context).width >= 900;
    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SingleChildScrollView(
                  child: _buildConfigPanel(controller),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: _buildLogPanel(controller, fill: true)),
            ],
          )
        : ListView(
            children: [
              _buildConfigPanel(controller),
              const SizedBox(height: 16),
              _buildLogPanel(controller),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('KnockGate'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(child: Text(controller.status)),
          ),
          PopupMenuButton<_HomeMenuAction>(
            onSelected: (action) => _handleMenu(context, action),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _HomeMenuAction.importUrl,
                child: ListTile(
                  leading: Icon(Icons.download),
                  title: Text('Import URL'),
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.scanQr,
                child: ListTile(
                  leading: Icon(Icons.qr_code_scanner),
                  title: Text('Scan QR'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _HomeMenuAction.clearHistory,
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear history'),
                ),
              ),
              PopupMenuItem(
                value: _HomeMenuAction.settings,
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Settings'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      ),
    );
  }

  Widget _buildConfigPanel(HomeController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Profile', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextField(
          controller: controller.labelController,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.hostController,
          decoration: const InputDecoration(labelText: 'Server host or IP'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.knockPortsController,
          decoration: const InputDecoration(
            labelText: 'UDP knock ports',
            hintText: '37708,31114,25880',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.protectedPortsController,
          decoration: const InputDecoration(
            labelText: 'Protected ports',
            hintText: '5432,9092/tcp,51820/udp',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller.seqTimeoutController,
                decoration: const InputDecoration(labelText: 'Seq timeout'),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller.openTimeoutController,
                decoration: const InputDecoration(labelText: 'Open timeout'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.hmacWindowController,
          decoration: const InputDecoration(labelText: 'HMAC window seconds'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.secretController,
          decoration: const InputDecoration(labelText: 'HMAC secret'),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
        ),
        const SizedBox(height: 16),
        _buildActionTabs(controller),
      ],
    );
  }

  Widget _buildActionTabs(HomeController controller) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.key), text: 'Knock'),
              Tab(icon: Icon(Icons.sensors), text: 'Check'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildActionButton(
                  controller,
                  actionIcon: Icons.key,
                  actionLabel: 'Knock',
                  onAction: controller.knock,
                ),
                _buildActionButton(
                  controller,
                  actionIcon: Icons.sensors,
                  actionLabel: 'Check',
                  onAction: controller.checkConnectivity,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    HomeController controller, {
    required IconData actionIcon,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) {
    final icon = controller.formDirty ? Icons.save : actionIcon;
    final label = controller.formDirty ? 'Save' : actionLabel;
    return FilledButton.icon(
      onPressed: controller.busy
          ? null
          : (controller.formDirty ? controller.saveFromForm : onAction),
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildLogPanel(HomeController controller, {bool fill = false}) {
    final content = Container(
      constraints: fill ? null : const BoxConstraints(minHeight: 220),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: controller.events.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No activity yet.'),
            )
          : ListView.separated(
              controller: fill ? _logController : null,
              shrinkWrap: !fill,
              itemCount: controller.events.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(controller.events[index]),
              ),
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Activity', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            TextButton(
              onPressed: controller.clearHistory,
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        fill ? Expanded(child: content) : content,
      ],
    );
  }

  Future<void> _handleMenu(BuildContext context, _HomeMenuAction action) async {
    final controller = context.read<HomeController>();
    switch (action) {
      case _HomeMenuAction.importUrl:
        await _showImportDialog(controller);
      case _HomeMenuAction.scanQr:
        await _scanQr(controller);
      case _HomeMenuAction.clearHistory:
        await controller.clearHistory();
      case _HomeMenuAction.settings:
        _openSettings();
    }
  }

  Future<void> _showImportDialog(HomeController controller) async {
    final rawUrl = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import profile'),
        content: TextField(
          controller: _importController,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'knockgate:// import URL',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_importController.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (rawUrl != null && rawUrl.trim().isNotEmpty) {
      await controller.importUrl(rawUrl);
      _importController.clear();
    }
  }

  Future<void> _scanQr(HomeController controller) async {
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      _showSnack(
        'QR scanning is available on Android, iOS, and macOS. Paste the import URL on this platform.',
      );
      return;
    }
    final scanned = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));
    if (scanned != null && scanned.trim().isNotEmpty) {
      await controller.importUrl(scanned, source: 'QR');
    }
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  void _showPendingError(HomeController controller) {
    if (controller.errorVersion == _shownErrorVersion ||
        controller.lastError == null) {
      return;
    }
    _shownErrorVersion = controller.errorVersion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showSnack(controller.lastError!);
      }
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
