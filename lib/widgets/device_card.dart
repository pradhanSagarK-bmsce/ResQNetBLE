import 'package:flutter/material.dart';
import '../models/adv_summary.dart';

class DeviceCard extends StatelessWidget {
  final String deviceId;
  final AdvSummary summary;

  const DeviceCard({required this.deviceId, required this.summary, super.key});

  Color _levelColor() {
    if (summary.urgent) return Colors.redAccent;
    if (summary.bpm > 0 && (summary.bpm < 60 || summary.bpm > 100)) {
      return Colors.orangeAccent;
    }
    return Colors.tealAccent;
  }

  @override
  Widget build(BuildContext context) {
    final col = _levelColor();

    // Prefer name if available, else fallback to ID
    final displayName = (summary.name != null && summary.name!.isNotEmpty)
        ? summary.name!
        : deviceId;

    return Card(
      color: const Color(0xFF1C1F26),
      elevation: 3,
      shadowColor: col.withOpacity(0.3),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: () {
          Navigator.pushNamed(context, '/detail', arguments: {'id': deviceId});
        },
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: col.withOpacity(0.25),
          child: Icon(
            summary.urgent
                ? Icons.warning_amber_rounded
                : Icons.sensors_rounded,
            color: col,
            size: 26,
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'BPM: ${summary.bpm}  |  SpO₂: ${summary.spo2}%  |  CO₂: ${summary.co2} ppm',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              summary.urgent ? Icons.error_rounded : Icons.check_circle_rounded,
              color: col,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              '${summary.rssi} dBm',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
