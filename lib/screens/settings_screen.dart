import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Use Consumer so this tile rebuilds when BleService notifies
          Consumer<BleService>(
            builder: (ctx, ble, _) {
              return SwitchListTile(
                value: ble.scanning,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(ctx);
                  try {
                    if (v) {
                      await ble.startScan();
                    } else {
                      await ble.stopScan();
                    }
                  } catch (e) {
                    // Surface any errors to the user
                    messenger.showSnackBar(
                      SnackBar(content: Text('Scan error: $e')),
                    );
                  }
                },
                title: const Text('BLE Scan'),
                subtitle: const Text('Start/stop Bluetooth scanning'),
              );
            },
          ),
          // Permission status and small log viewer
          Consumer<BleService>(
            builder: (ctx, ble, _) {
              return Column(
                children: [
                  ListTile(
                    title: const Text('Permissions'),
                    subtitle: Text(
                      'Bluetooth: ${ /* placeholder */ ''} ${ble.permissionStatus}',
                    ),
                    trailing: TextButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(ctx);
                        try {
                          final ok = await ble.init();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? 'Permissions granted'
                                    : 'Permissions denied',
                              ),
                            ),
                          );
                        } catch (e) {
                          messenger.showSnackBar(
                            SnackBar(content: Text('Permission error: $e')),
                          );
                        }
                      },
                      child: const Text('Request'),
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Recent logs'),
                    children: [
                      SizedBox(
                        height: 200,
                        child: ListView.builder(
                          itemCount: ble.logs.length,
                          itemBuilder: (c, i) => ListTile(
                            dense: true,
                            title: Text(
                              ble.logs[i],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              ble.clearLogs();
                            },
                            child: const Text('Clear logs'),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          ListTile(
            title: const Text('App Auth Token'),
            subtitle: const Text(
              'Configured token (edit source code to change)',
            ),
          ),
          ListTile(title: const Text('Firmware / BLE Info')),
        ],
      ),
    );
  }
}
