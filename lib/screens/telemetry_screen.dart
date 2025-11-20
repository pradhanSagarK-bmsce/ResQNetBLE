// lib/screens/telemetry_screen.dart
// Real-time telemetry screen for Mesh Nodes

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/ble_service.dart';

class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({super.key});

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  late AnimationController _pulseController;

  // Historical data for charts
  final List<double> _bpmHistory = [];
  final List<double> _spo2History = [];
  final int _maxHistoryLength = 60;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Update UI every 500ms to animate charts/timers
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _addToHistory(double bpm, double spo2) {
    // Only add if values are non-zero/valid
    if (bpm == 0 && spo2 == 0) return;

    setState(() {
      _bpmHistory.add(bpm);
      _spo2History.add(spo2);

      if (_bpmHistory.length > _maxHistoryLength) _bpmHistory.removeAt(0);
      if (_spo2History.length > _maxHistoryLength) _spo2History.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    // Handle both String (legacy) and Int IDs
    dynamic rawId = args?['id'];
    int? id;
    if (rawId is String) {
      id = int.tryParse(rawId);
    } else if (rawId is int) {
      id = rawId;
    }

    final ble = Provider.of<BleService>(context);
    final node = (id != null && ble.nodes.containsKey(id)) ? ble.nodes[id] : null;
    
    // "Live" means we heard from this node in the last 15 seconds
    final isLive = node != null && DateTime.now().difference(node.lastSeen).inSeconds < 15;

    // Update history if we have a node
    if (node != null) {
      // We use a post-frame callback or just check if the last value added differs
      // For simplicity in this demo, we add the current state every refresh 
      // to create a strip-chart effect, or strictly on change.
      // Here we'll just visualize the current state over time.
      if (_bpmHistory.isEmpty || _bpmHistory.last != node.bpm.toDouble()) {
         _addToHistory(node.bpm.toDouble(), node.spo2.toDouble());
      } else if (isLive && _bpmHistory.isNotEmpty) {
        // Repeat last known value to keep chart moving if live
        _addToHistory(node.bpm.toDouble(), node.spo2.toDouble());
      }
    }

    if (node == null) return _buildNotFound(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Node #${node.id}"),
            Row(
              children: [
                Container(
                  width: 8, 
                  height: 8,
                  decoration: BoxDecoration(
                    color: isLive ? Colors.greenAccent : Colors.redAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                         color: (isLive ? Colors.greenAccent : Colors.red).withOpacity(0.5),
                         blurRadius: 6,
                      )
                    ]
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isLive ? 'MESH ACTIVE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 11,
                    color: isLive ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildVitalCards(node),
            const SizedBox(height: 16),
            _buildChartCard(
              'Heart Rate (BPM)',
              _bpmHistory,
              Colors.redAccent,
              50,
              150,
            ),
            const SizedBox(height: 16),
            _buildChartCard(
              'Blood Oxygen (SpO₂)',
              _spo2History,
              Colors.blueAccent,
              80,
              100,
            ),
            const SizedBox(height: 16),
            _buildStatusCard(node),
            if (node.isCritical) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 30),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "CRITICAL ALERT BROADCAST\nPatient requires immediate assistance.",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: const Center(
        child: Text("Node not found or signal lost.", style: TextStyle(color: Colors.white54)),
      ),
    );
  }

  Widget _buildVitalCards(MeshNode node) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildVitalCard(
          'BPM',
          node.bpm.toString(),
          Icons.favorite,
          Colors.redAccent,
          node.bpm < 60 || node.bpm > 100,
        ),
        _buildVitalCard(
          'SpO₂',
          '${node.spo2}%',
          Icons.opacity,
          Colors.blueAccent,
          node.spo2 < 90,
        ),
      ],
    );
  }

  Widget _buildVitalCard(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isAlert,
  ) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final scale = isAlert ? 1.0 + (_pulseController.value * 0.03) : 1.0;
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.2), color.withOpacity(0.05)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isAlert ? Colors.redAccent : color.withOpacity(0.3),
                width: isAlert ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isAlert) ...[
                      const Spacer(),
                      const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                    ],
                  ],
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChartCard(
    String title,
    List<double> data,
    Color color,
    double minY,
    double maxY,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: data.isEmpty
                ? const Center(child: Text('Waiting for data...', style: TextStyle(color: Colors.white38)))
                : CustomPaint(
                    painter: LineChartPainter(
                      data: data,
                      color: color,
                      minY: minY,
                      maxY: maxY,
                    ),
                    size: Size.infinite,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(MeshNode node) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Network Diagnostics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 12),
          _statusRow('Last Seen', _timeSince(node.lastSeen), Icons.access_time),
          _statusRow('Hops to reach here', '${node.lastHopCount}', Icons.share),
          _statusRow('GPS (Simulated)', '${node.lat.toStringAsFixed(4)}, ${node.lon.toStringAsFixed(4)}', Icons.gps_fixed),
        ],
      ),
    );
  }

  Widget _statusRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.white60),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _timeSince(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    return '${diff.inMinutes}m ago';
  }
}

// Custom painter for line charts
class LineChartPainter extends CustomPainter {
  final List<double> data;
  final Color color;
  final double minY;
  final double maxY;

  LineChartPainter({
    required this.data,
    required this.color,
    required this.minY,
    required this.maxY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    // If we have more data points than width allows, we just step proportionally
    final stepX = size.width / (data.length - 1 > 0 ? data.length - 1 : 1);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      // Normalize Y between 0.0 and 1.0 based on min/max
      final normalizedY = ((data[i] - minY) / (maxY - minY)).clamp(0.0, 1.0);
      // Invert Y because canvas 0,0 is top-left
      final y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}