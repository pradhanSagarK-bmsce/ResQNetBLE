import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:resqnet_ble/services/ble_service.dart';
import 'package:resqnet_ble/screens/splash_screen.dart';
import 'package:resqnet_ble/screens/scan_screen.dart';
import 'package:resqnet_ble/screens/detail_screen.dart';
import 'package:resqnet_ble/screens/map_screen.dart';
import 'package:resqnet_ble/screens/alerts_screen.dart';
import 'package:resqnet_ble/screens/settings_screen.dart';

void main() {
  runApp(const ResQNetApp());
}

class ResQNetApp extends StatelessWidget {
  const ResQNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => BleService())],
      child: MaterialApp(
        title: 'ResQNetBLE',
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.tealAccent,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (ctx) => const SplashScreen(),
          '/scan': (ctx) => const ScanScreen(),
          '/detail': (ctx) => const DetailScreen(),
          '/map': (ctx) => const MapScreen(),
          '/alerts': (ctx) => const AlertsScreen(),
          '/settings': (ctx) => const SettingsScreen(),
        },
      ),
    );
  }
}
