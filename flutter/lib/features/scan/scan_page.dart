import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  bool _done = false;
  String? _error;
  MobileScannerController? _controller;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startScanner();
  }

  Future<void> _startScanner() async {
    // Prevent concurrent start attempts.
    if (_isStarting) return;
    _isStarting = true;
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
      await _controller!.start();
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isStarting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.stop();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only manage camera if controller is ready and we don't have an error.
    final controller = _controller;
    if (controller == null || _error != null) return;

    final isActive = state == AppLifecycleState.resumed;
    if (isActive) {
      controller.start();
    } else {
      controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR')),
      body: _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _startScanner(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_done || _error != null) return;
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
