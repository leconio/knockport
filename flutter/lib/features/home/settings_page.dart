import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HomeController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.sync),
              title: const Text('Auto refresh allowlist'),
              subtitle: const Text(
                'When the app opens, check public IP and open_timeout before knocking.',
              ),
              value: controller.autoRefreshEnabled,
              onChanged: controller.busy
                  ? null
                  : (value) => controller.setAutoRefreshEnabled(value),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.public),
              title: const Text('Last public IP'),
              subtitle: Text(controller.lastAutoRefreshIP ?? 'Not recorded'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Last auto knock'),
              subtitle: Text(_formatDateTime(controller.lastAutoRefreshKnock)),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: controller.busy || !controller.autoRefreshEnabled
                  ? null
                  : () => controller.runAutoRefreshCheck(
                      trigger: 'Settings manual check',
                    ),
              icon: const Icon(Icons.refresh),
              label: const Text('Check now'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Auto refresh runs only while the app is open. It does not keep a background task alive on mobile systems.',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return 'Not recorded';
    }
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}
