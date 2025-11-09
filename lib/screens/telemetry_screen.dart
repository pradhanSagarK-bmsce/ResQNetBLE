// lib/screens/telemetry_screen.dart
// Real-time telemetry screen with live charts and data visualization

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/ble_service.dart';
import '../models/adv_summary.dart';

class TelemetryScreen extends StatefulWidget {
  const TelemetryScreen({super.key});

  @override
  State<TelemetryScreen> createState() => _TelemetryScreenState();
}

class _TelemetryScreenState extends State<TelemetryScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  late AnimationController _pulseController;

  // Historical data for charts (last 60 data points)
  final List<double> _bpmHistory = [];
  final List<double> _spo2History = [];
  final List<double> _co2History = [];
  final List<double> _tempHistory = [];
  final int _maxHistoryLength = 60;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Update every 500ms for smooth real-time feel
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

  void _addToHistory(double bpm, double spo2, double co2, double temp) {
    setState(() {
      _bpmHistory.add(bpm);
      _spo2History.add(spo2);
      _co2History.add(co2);
      _tempHistory.add(temp);

      if (_bpmHistory.length > _maxHistoryLength) _bpmHistory.removeAt(0);
      if (_spo2History.length > _maxHistoryLength) _spo2History.removeAt(0);
      if (_co2History.length > _maxHistoryLength) _co2History.removeAt(0);
      if (_tempHistory.length > _maxHistoryLength) _tempHistory.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final id = args?['id'] as String?;
    final ble = Provider.of<BleService>(context);
    final adv = (id != null && ble.devices.containsKey(id))
        ? ble.devices[id]
        : null;
    final displayName = (id != null) ? ble.getDisplayName(id) : 'Unknown';
    final isConnected = ble.connectedId == id;
    final isLive = isConnected && ble.isSubscribed;

    // Update history when new data arrives
    if (adv != null && isLive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _addToHistory(
          adv.bpm.toDouble(),
          adv.spo2.toDouble(),
          adv.co2.toDouble(),
          adv.tempC,
        );
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isLive)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(fontSize: 18),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              isLive ? 'LIVE STREAMING' : 'NOT CONNECTED',
              style: TextStyle(
                fontSize: 11,
                color: isLive ? Colors.greenAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          if (isLive)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.greenAccent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${ble.totalPacketsReceived} pkts',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: !isLive
          ? _buildNotConnected(context)
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildVitalCards(adv!),
                  const SizedBox(height: 16),
                  _buildChartCard(
                    'Heart Rate (BPM)',
                    _bpmHistory,
                    Colors.redAccent,
                    60,
                    100,
                  ),
                  const SizedBox(height: 16),
                  _buildChartCard(
                    'Blood Oxygen (SpO₂)',
                    _spo2History,
                    Colors.blueAccent,
                    90,
                    100,
                  ),
                  const SizedBox(height: 16),
                  _buildChartCard(
                    'CO₂ Level (ppm)',
                    _co2History,
                    Colors.orangeAccent,
                    400,
                    1000,
                  ),
                  const SizedBox(height: 16),
                  _buildChartCard(
                    'Temperature (°C)',
                    _tempHistory,
                    Colors.purpleAccent,
                    20,
                    30,
                  ),
                  const SizedBox(height: 16),
                  _buildStatusCard(ble, adv),
                  const SizedBox(height: 16),
                  _buildFlagsCard(adv),
                ],
              ),
            ),
    );
  }

  Widget _buildNotConnected(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.signal_wifi_off, size: 80, color: Colors.white24),
            const SizedBox(height: 24),
            const Text(
              'No Active Connection',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Connect to a device to view live telemetry data.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVitalCards(AdvSummary adv) {
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
          adv.bpm.toString(),
          Icons.favorite,
          Colors.redAccent,
          adv.bpm < 60 || adv.bpm > 100,
        ),
        _buildVitalCard(
          'SpO₂',
          '${adv.spo2}%',
          Icons.opacity,
          Colors.blueAccent,
          adv.spo2 < 90,
        ),
        _buildVitalCard(
          'CO₂',
          '${adv.co2}',
          Icons.cloud,
          Colors.orangeAccent,
          adv.co2 > 1000,
        ),
        _buildVitalCard(
          'Temp',
          '${adv.tempC.toStringAsFixed(1)}°C',
          Icons.thermostat,
          Colors.purpleAccent,
          false,
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
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (isAlert) ...[
                      const Spacer(),
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                    ],
                  ],
                ),
                Text(
                  value,
                  style: TextStyle(
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
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (data.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    data.last.toStringAsFixed(1),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 120,
            child: data.isEmpty
                ? Center(
                    child: Text(
                      'Waiting for data...',
                      style: TextStyle(color: Colors.white38),
                    ),
                  )
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

  Widget _buildStatusCard(BleService ble, AdvSummary adv) {
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
            'Connection Status',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          _statusRow('Duration', ble.connectionDuration, Icons.timer),
          _statusRow(
            'Total Packets',
            '${ble.totalPacketsReceived}',
            Icons.data_usage,
          ),
          _statusRow(
            'Missed Packets',
            '${ble.missedPackets}',
            Icons.warning_amber,
          ),
          _statusRow(
            'Last Packet',
            _timeSince(ble.lastPacketTime),
            Icons.access_time,
          ),
          _statusRow(
            'Signal (RSSI)',
            '${adv.rssi} dBm',
            Icons.signal_cellular_4_bar,
          ),
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
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlagsCard(AdvSummary adv) {
    final flags = [
      if (adv.freefall) ('Freefall', Icons.arrow_downward, Colors.purple),
      if (adv.vibration) ('Vibration', Icons.vibration, Colors.pink),
      if (adv.tilt) ('Tilt', Icons.screen_rotation, Colors.teal),
      if (adv.fall) ('Fall', Icons.person_off, Colors.red),
      if (adv.shock) ('Shock', Icons.flash_on, Colors.yellow),
      if (adv.urgent) ('Urgent', Icons.error, Colors.orange),
      if (adv.gpsValid) ('GPS OK', Icons.gps_fixed, Colors.green),
    ];

    if (flags.isEmpty) return const SizedBox.shrink();

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
            'Alert Flags',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: flags.map((flag) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: flag.$3.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: flag.$3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(flag.$2, size: 16, color: flag.$3),
                    const SizedBox(width: 6),
                    Text(
                      flag.$1,
                      style: TextStyle(
                        color: flag.$3,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _timeSince(DateTime? time) {
    if (time == null) return '—';
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
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

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (data.length - 1).clamp(1, double.infinity);

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = ((data[i] - minY) / (maxY - minY)).clamp(0.0, 1.0);
      final y = size.height - (normalizedY * size.height);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw data points
    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.length; i++) {
      final x = i * stepX;
      final normalizedY = ((data[i] - minY) / (maxY - minY)).clamp(0.0, 1.0);
      final y = size.height - (normalizedY * size.height);

      canvas.drawCircle(Offset(x, y), 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(LineChartPainter oldDelegate) {
    return oldDelegate.data != data;
  }
}
