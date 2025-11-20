import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';

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

    String statusText = "Idle";
    if (ble.isSourceMode) statusText = "Source (Broadcasting)";
    else if (ble.isGatewayMode) statusText = "Gateway (Cloud Upload)";
    else if (ble.scanning) statusText = "Relay (Scanning)";

    final nodeList = ble.nodes.values.toList()
      ..sort((a, b) {
        if (a.isCritical && !b.isCritical) return -1;
        if (!a.isCritical && b.isCritical) return 1;
        return b.lastSeen.compareTo(a.lastSeen);
      });

    return Scaffold(
      backgroundColor: const Color(0xFF0B1014),
      appBar: AppBar(
        title: const Text(
          'ResQ Mesh Network',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.8),
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
            onPressed: () => ble.clearLogs(),
            icon: const Icon(Icons.cleaning_services_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings, color: Colors.white),
          ),
        ],
      ),
      
      floatingActionButton: AnimatedBuilder(
        animation: _glowAnim,
        builder: (context, _) {
          return FloatingActionButton(
            onPressed: () async {
              if (ble.scanning) {
                await ble.stopScan();
              } else {
                ble.startMeshNetwork();
              }
            },
            backgroundColor: ble.scanning
                ? Colors.orange.shade600
                : Colors.tealAccent.shade700,
            child: Icon(
              ble.scanning ? Icons.stop_rounded : Icons.radar,
              color: Colors.white,
            ),
          );
        },
      ),

      body: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          children: [
            // Status Card
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
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
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        ble.scanning ? Icons.wifi_tethering : Icons.portable_wifi_off,
                        color: ble.scanning ? Colors.greenAccent : Colors.grey,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statusText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${ble.nodes.length} Nodes detected',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                       _ModeToggleButton(
                        label: "Simulation",
                        isActive: ble.isSourceMode,
                        activeColor: Colors.redAccent,
                        onTap: () {
                          if (ble.isSourceMode) ble.stopSimulatedSource();
                          else ble.startSimulatedSource();
                        },
                      ),
                      _ModeToggleButton(
                        label: "Gateway",
                        isActive: ble.isGatewayMode,
                        activeColor: Colors.blueAccent,
                        onTap: () {
                          ble.setGatewayMode(!ble.isGatewayMode);
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),

            // Node List
            Expanded(
              child: nodeList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.bluetooth_searching_rounded, size: 80, color: Colors.white12),
                          SizedBox(height: 12),
                          Text(
                            'No nodes found yet.\nEnable "Simulation" on another device\nor start Scanning.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: nodeList.length,
                      itemBuilder: (context, i) {
                        return _buildNodeCard(context, nodeList[i]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeCard(BuildContext context, MeshNode node) {
    final timeSince = DateTime.now().difference(node.lastSeen);
    final isStale = timeSince.inSeconds > 30;
    
    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Navigate to Telemetry Screen
          Navigator.pushNamed(context, '/telemetry', arguments: {'id': node.id});
        },
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: node.isCritical ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
            child: Icon(
              node.isCritical ? Icons.warning : Icons.health_and_safety,
              color: node.isCritical ? Colors.redAccent : Colors.greenAccent,
            ),
          ),
          title: Text(
            "Node #${node.id}",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "BPM: ${node.bpm} • SpO2: ${node.spo2}%",
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                "Hops: ${node.lastHopCount} • ${timeSince.inSeconds}s ago",
                style: TextStyle(color: isStale ? Colors.orange : Colors.grey, fontSize: 12),
              ),
            ],
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white24),
        ),
      ),
    );
  }
}

class _ModeToggleButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;
  final VoidCallback onTap;

  const _ModeToggleButton({
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? activeColor.withOpacity(0.2) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? activeColor : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.check : Icons.circle_outlined,
              size: 16,
              color: isActive ? activeColor : Colors.white54,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white54,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}