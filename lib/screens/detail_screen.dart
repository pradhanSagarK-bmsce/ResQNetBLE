// lib/screens/detail_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../models/adv_summary.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _busy = false;

  Future<void> _performWithBusy(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Operation failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoTile(String title, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF101214),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Icon(icon, size: 20, color: Colors.white70),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // convert 24-bit seconds ts -> human
  String _formatTs(int ts24) {
    if (ts24 == 0) return '—';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts24 * 1000);
      return dt.toLocal().toString();
    } catch (_) {
      return ts24.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map?;
    final id = args?['id'] as String?;
    final ble = Provider.of<BleService>(context);
    final adv = (id != null && ble.devices.containsKey(id))
        ? ble.devices[id]
        : null;
    final displayName = (id != null)
        ? (ble.deviceLocalNames[id] ?? adv?.name ?? id)
        : 'Unknown';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(child: Text(displayName, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            Text(
              id ?? '',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(36),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            width: double.infinity,
            color: Colors.black12,
            child: Row(
              children: [
                Chip(
                  backgroundColor: ble.status.contains('auth')
                      ? Colors.orange
                      : Colors.green,
                  label: Text(
                    ble.status,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                if (ble.connectedId == id)
                  Chip(
                    backgroundColor: ble.authorized
                        ? Colors.teal
                        : Colors.blueGrey,
                    label: Text(
                      ble.authorized ? 'Authorized' : 'Connected',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                const Spacer(),
                Text(
                  adv != null ? '${adv.rssi} dBm' : '',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
      body: adv == null
          ? _buildEmpty()
          : LayoutBuilder(
              builder: (ctx, constraints) {
                final isWide = constraints.maxWidth > 720;
                final padding = const EdgeInsets.all(12.0);
                return SingleChildScrollView(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flex(
                        direction: isWide ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: isWide ? 2 : 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Vitals card
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1114),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.favorite,
                                            color: Colors.redAccent,
                                          ),
                                          const SizedBox(width: 8),
                                          const Text(
                                            'Vitals',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const Spacer(),
                                          if (adv.urgent)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'URGENT',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _infoTile(
                                              'BPM',
                                              adv.bpm > 0
                                                  ? adv.bpm.toString()
                                                  : '—',
                                              icon: Icons.monitor_heart,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _infoTile(
                                              'SpO₂',
                                              adv.spo2 > 0
                                                  ? '${adv.spo2} %'
                                                  : '—',
                                              icon: Icons.opacity,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _infoTile(
                                              'CO₂',
                                              adv.co2 > 0
                                                  ? '${adv.co2} ppm'
                                                  : '—',
                                              icon: Icons.devices,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _infoTile(
                                              'Temperature',
                                              adv.tempC != 0.0
                                                  ? '${adv.tempC.toStringAsFixed(1)} °C'
                                                  : '—',
                                              icon: Icons.thermostat,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _infoTile(
                                              'Battery',
                                              adv.batt > 0
                                                  ? '${adv.batt} %'
                                                  : '—',
                                              icon: Icons.battery_charging_full,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Location
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1114),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: const [
                                          Icon(
                                            Icons.location_pin,
                                            color: Colors.orangeAccent,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Location',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        adv.gpsValid
                                            ? '${adv.lat.toStringAsFixed(6)}, ${adv.lon.toStringAsFixed(6)}'
                                            : 'No GPS Fix',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: [
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.pushNamed(
                                                context,
                                                '/map',
                                                arguments: {
                                                  'lat': adv.lat,
                                                  'lon': adv.lon,
                                                  'label': displayName,
                                                },
                                              );
                                            },
                                            icon: const Icon(Icons.map),
                                            label: const Text('Show on Map'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepPurple,
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Locate/Alert triggered',
                                                  ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.notifications_active,
                                            ),
                                            label: const Text('Alert Team'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isWide) const SizedBox(width: 12),
                          SizedBox(
                            width: isWide ? 360 : double.infinity,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1114),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Telemetry & Flags',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _infoTile(
                                        'Flags',
                                        _buildFlagsText(adv),
                                        icon: Icons.flag,
                                      ),
                                      const SizedBox(height: 8),
                                      _infoTile(
                                        'Last adv ts',
                                        adv.ts > 0 ? _formatTs(adv.ts) : '—',
                                        icon: Icons.access_time,
                                      ),
                                      const SizedBox(height: 8),
                                      _infoTile(
                                        'LastSeen (local)',
                                        adv.lastSeen.toLocal().toString(),
                                        icon: Icons.watch_later_outlined,
                                      ),
                                      const SizedBox(height: 8),
                                      _infoTile(
                                        'RSSI',
                                        '${adv.rssi} dBm',
                                        icon: Icons.signal_cellular_4_bar,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Connection actions
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F1114),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Text(
                                        'Connection',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _busy
                                                  ? null
                                                  : () async {
                                                      if (ble.connectedId ==
                                                          id) {
                                                        await _performWithBusy(
                                                          () async {
                                                            await ble
                                                                .disconnect();
                                                          },
                                                        );
                                                      } else {
                                                        await _performWithBusy(
                                                          () async {
                                                            await ble
                                                                .manualConnect(
                                                                  id!,
                                                                );
                                                          },
                                                        );
                                                      }
                                                    },
                                              icon: Icon(
                                                ble.connectedId == id
                                                    ? Icons.link_off
                                                    : Icons.link,
                                              ),
                                              label: Text(
                                                ble.connectedId == id
                                                    ? 'Disconnect'
                                                    : 'Connect & Subscribe',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () async {
                                                await _performWithBusy(() async {
                                                  await ble
                                                      .discoverServicesForDevice(
                                                        id!,
                                                      );
                                                });
                                              },
                                              icon: const Icon(Icons.search),
                                              label: const Text(
                                                'Discover services',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () async {
                                                await _performWithBusy(
                                                  () async {
                                                    await ble
                                                        .readGattDeviceName(
                                                          id!,
                                                        );
                                                  },
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.perm_device_information,
                                              ),
                                              label: const Text(
                                                'Read Device Name',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Stream status: seq=${ble.lastSeq} · missed=${ble.missedPackets} · last=${ble.lastPacketTime?.toLocal() ?? "—"}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F1114),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Raw / Parsed Data',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _smallChip('Valid', adv.valid),
                                _smallChip('Urgent', adv.urgent),
                                _smallChip('GPS', adv.gpsValid),
                                _smallChip('BPM', adv.bpm > 0),
                                _smallChip('SpO₂', adv.spo2 > 0),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _prettyAdv(adv),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Share not implemented'),
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.share,
                                color: Colors.white70,
                              ),
                              label: const Text(
                                'Share',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () {
                                // quick refresh
                                ble.readGattDeviceName(id!);
                                ble.discoverServicesForDevice(id);
                              },
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white70,
                              ),
                              label: const Text(
                                'Refresh',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 60, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'No device summary available yet.\nStart scanning or select a device that advertises.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back to Scan'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallChip(String label, bool on) {
    return Chip(
      backgroundColor: on ? Colors.green.withOpacity(0.18) : Colors.white10,
      label: Text(
        label,
        style: TextStyle(color: on ? Colors.greenAccent : Colors.white60),
      ),
    );
  }

  /// Build flags text by decoding:
  /// bit0=FREEFALL, bit1=VIBRATION, bit2=TILT, bit3=URGENT, bit5=ABNORMAL_VITALS, bit6=GPS_OK
  /// - first try to read adv.flags (raw byte) if present
  /// - otherwise, fallback to boolean properties if they exist on AdvSummary
  String _buildFlagsText(AdvSummary a) {
    final List<String> parts = [];

    // Try to get raw flags byte if AdvSummary contains it (defensive)
    int? flags;
    try {
      final dyn = a as dynamic;
      final f = dyn.flags;
      if (f is int)
        flags = f;
      else if (f is num)
        flags = f.toInt();
    } catch (_) {
      flags = null;
    }

    if (flags != null) {
      if ((flags & (1 << 0)) != 0) parts.add('FREEFALL');
      if ((flags & (1 << 1)) != 0) parts.add('VIBRATION');
      if ((flags & (1 << 2)) != 0) parts.add('TILT');
      if ((flags & (1 << 3)) != 0) parts.add('URGENT');
      if ((flags & (1 << 5)) != 0) parts.add('ABNORMAL_VITALS');
      if ((flags & (1 << 6)) != 0) parts.add('GPS_OK');
    } else {
      // Fallback: try boolean properties (if parse stored them)
      try {
        final dyn = a as dynamic;
        if (dyn.freefall == true) parts.add('FREEFALL');
        if (dyn.vibration == true) parts.add('VIBRATION');
        if (dyn.tilt == true) parts.add('TILT');
        if (dyn.fall == true) parts.add('FALL');
        if (dyn.shock == true) parts.add('SHOCK');
        // urgent/gps flags might be stored already
        if (dyn.urgent == true) parts.add('URGENT');
        if (dyn.gpsValid == true || dyn.gpsOK == true) parts.add('GPS_OK');
      } catch (_) {
        // nothing else to try
      }
    }

    if (parts.isEmpty) return 'None';
    return parts.join(', ');
  }

  String _prettyAdv(AdvSummary a) {
    // attempt to also include flags byte if present
    dynamic flagsVal;
    try {
      final dyn = a as dynamic;
      flagsVal = dyn.flags;
    } catch (_) {
      flagsVal = null;
    }

    final map = <String, Object?>{
      'valid': a.valid,
      'urgent': a.urgent,
      'gpsValid': a.gpsValid,
      'batt': a.batt,
      'bpm': a.bpm,
      'spo2': a.spo2,
      'co2': a.co2,
      'tempC': a.tempC,
      'lat': a.lat,
      'lon': a.lon,
      'ts': a.ts,
      'rssi': a.rssi,
      'lastSeen': a.lastSeen.toIso8601String(),
      'name': a.name ?? '',
      'flags': flagsVal ?? '<unknown>',
    };
    final entries = map.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    return entries;
  }
}
