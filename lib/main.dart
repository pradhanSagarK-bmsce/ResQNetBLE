import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Services
import 'services/ble_service.dart';

// Screens
import 'screens/scan_screen.dart';
import 'screens/map_screen.dart';
import 'screens/debug_logs_screen.dart';
import 'screens/telemetry_screen.dart';

// Placeholder for Settings (create if needed)
import 'screens/settings_screen.dart'; 

void main() {
  runApp(const ResQNetApp());
}

class ResQNetApp extends StatelessWidget {
  const ResQNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleService()),
      ],
      child: MaterialApp(
        title: 'ResQNet Mesh',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          primaryColor: Colors.tealAccent,
          scaffoldBackgroundColor: const Color(0xFF0D1117),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: false,
          ),
          colorScheme: const ColorScheme.dark(
            primary: Colors.tealAccent,
            secondary: Colors.orangeAccent,
            surface: Color(0xFF161B22),
          ),
        ),
        // We use a Tab Scaffold as the main entry point
        home: const MainTabScaffold(),
        routes: {
          '/telemetry': (ctx) => const TelemetryScreen(),
          '/settings': (ctx) => const SettingsScreen(),
        },
      ),
    );
  }
}

class MainTabScaffold extends StatefulWidget {
  const MainTabScaffold({super.key});

  @override
  State<MainTabScaffold> createState() => _MainTabScaffoldState();
}

class _MainTabScaffoldState extends State<MainTabScaffold> {
  int _currentIndex = 0;

  // The three main views of the application
  final List<Widget> _screens = [
    const ScanScreen(),
    const MapScreen(),
    const DebugLogsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0D1117),
        indicatorColor: Colors.tealAccent.withOpacity(0.2),
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_outlined), 
            selectedIcon: Icon(Icons.radar),
            label: 'Scanner',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined), 
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.terminal_outlined), 
            selectedIcon: Icon(Icons.terminal),
            label: 'Logs',
          ),
        ],
      ),
    );
  }
}