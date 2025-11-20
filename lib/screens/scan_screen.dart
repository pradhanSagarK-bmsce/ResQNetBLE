import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../widgets/device_card.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _glowAnim = Tween<double>(
      begin: 0.3,
      end: 0.9,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = Provider.of<BleService>(context);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B1014),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Nearby ResQ Devices',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: 0.8,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF00B4DB), Color(0xFF0083B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () async => await ble.startScan(),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
          ),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: ble.scanning
                      ? Colors.orangeAccent.withOpacity(_glowAnim.value)
                      : Colors.tealAccent.withOpacity(_glowAnim.value),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: FloatingActionButton(
              onPressed: () async {
                if (ble.scanning) {
                  await ble.stopScan();
                } else {
                  await ble.startScan();
                }
              },
              backgroundColor: ble.scanning
                  ? Colors.orange.shade600
                  : Colors.tealAccent.shade700,
              child: Icon(
                ble.scanning ? Icons.stop_rounded : Icons.search_rounded,
                size: 30,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Consumer<BleService>(
          builder: (ctx, s, _) {
            final list = s.devices.entries.toList()
              ..sort(
                (a, b) => b.value.urgent.toString().compareTo(
                  a.value.urgent.toString(),
                ),
              );

            return Column(
              children: [
                // 🔹 BLE Status Card
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF16222A), Color(0xFF3A6073)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 16,
                    ),
                    leading: Icon(
                      s.scanning
                          ? Icons.wifi_tethering_rounded
                          : Icons.usb_rounded,
                      color: s.scanning ? Colors.tealAccent : Colors.grey[300],
                      size: 28,
                    ),
                    title: Text(
                      s.status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Permissions: ${s.permissionStatus}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 13),
                    ),
                    trailing: TextButton(
                      onPressed: () async =>
                          s.scanning ? await s.stopScan() : await s.startScan(),
                      style: TextButton.styleFrom(
                        backgroundColor: s.scanning
                            ? Colors.orange
                            : Colors.tealAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        s.scanning ? 'Stop' : 'Start',
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                ),

                // 🔹 Device List
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(
                                Icons.bluetooth_searching_rounded,
                                size: 80,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No devices found.\nStart scanning to discover nearby nodes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          physics: const BouncingScrollPhysics(),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final id = list[i].key;
                            final adv = list[i].value;
                            return DeviceCard(deviceId: id, summary: adv);
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
