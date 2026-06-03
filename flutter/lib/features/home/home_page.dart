import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../scan/scan_page.dart';
import 'home_controller.dart';
import 'settings_page.dart';

enum _HomeMenuAction { importUrl, scanQr, clearProfile, settings }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _importController = TextEditingController();
  StreamSubscription<Uri>? _linkSub;
  int _shownErrorVersion = 0;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenForLinks());
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _importController.dispose();
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
      _showSnack('$error');
    }
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) => controller.importUrl(uri.toString(), source: 'Deep link'),
      onError: (Object error) => _showSnack('$error'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    _showPendingError(controller);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        centerTitle: false,
        title: const Text('KnockGate'),
        actions: [
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
                value: _HomeMenuAction.clearProfile,
                child: ListTile(
                  leading: Icon(Icons.clear_all),
                  title: Text('Clear'),
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
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            _KnockTab(controller: controller),
            _CheckTab(controller: controller),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: 'Knock',
          ),
          NavigationDestination(
            icon: Icon(Icons.sensors_outlined),
            selectedIcon: Icon(Icons.sensors),
            label: 'Check',
          ),
        ],
      ),
    );
  }

  Future<void> _handleMenu(BuildContext context, _HomeMenuAction action) async {
    final controller = context.read<HomeController>();
    switch (action) {
      case _HomeMenuAction.importUrl:
        await _showImportDialog(controller);
      case _HomeMenuAction.scanQr:
        await _scanQr(controller);
      case _HomeMenuAction.clearProfile:
        await controller.clearProfile();
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

class _KnockTab extends StatelessWidget {
  const _KnockTab({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          controller: controller.seqTimeoutController,
          decoration: const InputDecoration(labelText: 'Seq timeout'),
          keyboardType: TextInputType.number,
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
        _PrimaryActionButton(
          controller: controller,
          dirty: controller.knockDirty,
          icon: Icons.key,
          label: 'Knock',
          onSave: controller.saveKnockFromForm,
          onPressed: controller.knock,
        ),
      ],
    );
  }
}

class _CheckTab extends StatelessWidget {
  const _CheckTab({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: controller.hostController,
          decoration: const InputDecoration(labelText: 'Server host or IP'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: controller.protectedPortsController,
          decoration: const InputDecoration(
            labelText: 'TCP ports to check',
            hintText: '5432,9092/tcp',
          ),
        ),
        const SizedBox(height: 16),
        _PrimaryActionButton(
          controller: controller,
          dirty: controller.checkDirty,
          icon: Icons.sensors,
          label: 'Check',
          onSave: controller.saveCheckFromForm,
          onPressed: controller.checkConnectivity,
        ),
        if (controller.checkResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final result in controller.checkResults)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(result),
            ),
        ],
      ],
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  const _PrimaryActionButton({
    required this.controller,
    required this.dirty,
    required this.icon,
    required this.label,
    required this.onSave,
    required this.onPressed,
  });

  final HomeController controller;
  final bool dirty;
  final IconData icon;
  final String label;
  final Future<void> Function() onSave;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: controller.busy ? null : (dirty ? onSave : onPressed),
      icon: Icon(dirty ? Icons.save : icon),
      label: Text(dirty ? 'Save' : label),
    );
  }
}
