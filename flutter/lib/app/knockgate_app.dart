import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/home/home_controller.dart';
import '../features/home/home_page.dart';
import '../services/connectivity_service.dart';
import '../services/knock_service.dart';
import '../services/profile_store.dart';

class KnockGateApp extends StatelessWidget {
  const KnockGateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HomeController(
        store: ProfileStore(),
        knockService: KnockService(),
        connectivityService: ConnectivityService(),
      )..init(),
      child: MaterialApp(
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
      ),
    );
  }
}
