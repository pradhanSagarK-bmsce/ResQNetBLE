import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer<BleService>(
        builder: (ctx, ble, _) {
          return ListView(
            children: [
              _sectionHeader("General"),
              
              // 1. Main Scan Toggle (Fixed the await error)
              SwitchListTile(
                activeColor: Colors.tealAccent,
                value: ble.scanning,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  try {
                    if (v) {
                      // ERROR FIX: startScan is void, so we do NOT await it
                      ble.startMeshNetwork(); 
                      messenger.showSnackBar(const SnackBar(content: Text('Mesh Network Started')));
                    } else {
                      // stopScan returns Future, so we DO await it
                      await ble.stopScan();
                      messenger.showSnackBar(const SnackBar(content: Text('Scanning Stopped')));
                    }
                  } catch (e) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                title: const Text('Mesh Network Scan', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Listen for nearby nodes', style: TextStyle(color: Colors.white54)),
                secondary: Icon(
                  ble.scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                  color: ble.scanning ? Colors.tealAccent : Colors.grey,
                ),
              ),

              _sectionHeader("Mesh Roles"),

              // 2. Simulation Mode Toggle
              SwitchListTile(
                activeColor: Colors.redAccent,
                value: ble.isSourceMode,
                onChanged: (val) {
                  if (val) {
                    ble.startSimulatedSource();
                  } else {
                    ble.stopSimulatedSource();
                  }
                },
                title: const Text('Simulation Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Broadcast as a Hospital Bed (Source)', style: TextStyle(color: Colors.white54)),
                secondary: Icon(Icons.favorite, color: ble.isSourceMode ? Colors.redAccent : Colors.grey),
              ),

              // 3. Gateway Mode Toggle
              SwitchListTile(
                activeColor: Colors.blueAccent,
                value: ble.isGatewayMode,
                onChanged: (val) => ble.setGatewayMode(val),
                title: const Text('Gateway Mode', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Upload data to cloud (Stops Hopping)', style: TextStyle(color: Colors.white54)),
                secondary: Icon(Icons.cloud_upload, color: ble.isGatewayMode ? Colors.blueAccent : Colors.grey),
              ),

              _sectionHeader("System"),

              // 4. Permissions Logic (Restored from your old code)
              ListTile(
                leading: const Icon(Icons.security, color: Colors.white70),
                title: const Text('Permissions', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  'Status: ${ble.permissionStatus}',
                  style: TextStyle(
                    color: ble.permissionStatus == 'granted' ? Colors.green : Colors.orange,
                  ),
                ),
                trailing: TextButton(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(ctx);
                    await ble.init();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Permissions: ${ble.permissionStatus}'),
                        backgroundColor: ble.permissionStatus == 'granted' ? Colors.green : Colors.orange,
                      ),
                    );
                  },
                  child: const Text('Request'),
                ),
              ),

              // 5. Mini Log Viewer (Restored)
              ExpansionTile(
                leading: const Icon(Icons.terminal, color: Colors.white70),
                title: const Text('Recent logs', style: TextStyle(color: Colors.white)),
                children: [
                  Container(
                    height: 200,
                    color: Colors.black26,
                    child: ListView.builder(
                      itemCount: ble.logs.length,
                      itemBuilder: (c, i) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          ble.logs[i],
                          style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => ble.clearLogs(),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Clear logs'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.tealAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}