// lib/screens/debug_logs_screen.dart
// Real-time debug logs screen to monitor BLE connection process

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/ble_service.dart';

class DebugLogsScreen extends StatefulWidget {
  const DebugLogsScreen({super.key});

  @override
  State<DebugLogsScreen> createState() => _DebugLogsScreenState();
}

class _DebugLogsScreenState extends State<DebugLogsScreen> {
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // Auto-refresh every 100ms for real-time updates
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
      if (_autoScroll && _scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ble = Provider.of<BleService>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('🔍 Debug Logs'),
        actions: [
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
              color: _autoScroll ? Colors.greenAccent : Colors.grey,
            ),
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
            tooltip: _autoScroll ? 'Disable Auto-scroll' : 'Enable Auto-scroll',
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.blueAccent),
            onPressed: () {
              final allLogs = ble.logs.reversed.join('\n');
              Clipboard.setData(ClipboardData(text: allLogs));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📋 Logs copied to clipboard'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            tooltip: 'Copy all logs',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            onPressed: () {
              ble.clearLogs();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🗑️ Logs cleared'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(ble),
          Expanded(
            child: ble.logs.isEmpty ? _buildEmptyState() : _buildLogsList(ble),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BleService ble) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _statusCard(
                  'Status',
                  ble.status,
                  ble.connectedId != null && ble.isSubscribed
                      ? Colors.green
                      : ble.connectedId != null
                      ? Colors.orange
                      : Colors.grey,
                  Icons.info_outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statusCard(
                  'Logs',
                  '${ble.logs.length}',
                  Colors.blue,
                  Icons.article,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statusCard(
                  'Connected',
                  ble.connectedId != null ? '✅ Yes' : '❌ No',
                  ble.connectedId != null ? Colors.green : Colors.red,
                  Icons.cable,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statusCard(
                  'Subscribed',
                  ble.isSubscribed ? '✅ Yes' : '❌ No',
                  ble.isSubscribed ? Colors.green : Colors.red,
                  Icons.notifications_active,
                ),
              ),
            ],
          ),
          if (ble.connectedId != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _statusCard(
                    'Packets',
                    '${ble.totalPacketsReceived}',
                    Colors.purple,
                    Icons.data_usage,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _statusCard(
                    'Missed',
                    '${ble.missedPackets}',
                    ble.missedPackets > 0 ? Colors.orange : Colors.green,
                    Icons.warning_amber,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white60,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.article_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'No logs yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.white54,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start scanning or connecting to see logs',
            style: TextStyle(fontSize: 14, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsList(BleService ble) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: ble.logs.length,
      itemBuilder: (context, index) {
        final log = ble.logs[index];
        return _buildLogEntry(log, index);
      },
    );
  }

  Widget _buildLogEntry(String log, int index) {
    // Parse log entry
    Color backgroundColor = const Color(0xFF0F0F0F);
    Color textColor = Colors.white70;
    IconData? icon;
    Color? iconColor;

    if (log.contains('✅') ||
        log.contains('COMPLETE') ||
        log.contains('SUCCESS')) {
      backgroundColor = Colors.green.withOpacity(0.1);
      textColor = Colors.greenAccent;
      icon = Icons.check_circle;
      iconColor = Colors.greenAccent;
    } else if (log.contains('❌') ||
        log.contains('ERROR') ||
        log.contains('FAILED')) {
      backgroundColor = Colors.red.withOpacity(0.1);
      textColor = Colors.redAccent;
      icon = Icons.error;
      iconColor = Colors.redAccent;
    } else if (log.contains('⚠️') || log.contains('WARNING')) {
      backgroundColor = Colors.orange.withOpacity(0.1);
      textColor = Colors.orangeAccent;
      icon = Icons.warning;
      iconColor = Colors.orangeAccent;
    } else if (log.contains('🔗') || log.contains('CONNECT')) {
      backgroundColor = Colors.blue.withOpacity(0.1);
      textColor = Colors.blueAccent;
      icon = Icons.cable;
      iconColor = Colors.blueAccent;
    } else if (log.contains('📡') ||
        log.contains('📦') ||
        log.contains('SUBSCRIB')) {
      backgroundColor = Colors.purple.withOpacity(0.1);
      textColor = Colors.purpleAccent;
      icon = Icons.wifi;
      iconColor = Colors.purpleAccent;
    } else if (log.contains('🔍') || log.contains('DISCOVER')) {
      backgroundColor = Colors.cyan.withOpacity(0.1);
      textColor = Colors.cyanAccent;
      icon = Icons.search;
      iconColor = Colors.cyanAccent;
    } else if (log.contains('╔') || log.contains('═')) {
      backgroundColor = Colors.indigo.withOpacity(0.1);
      textColor = Colors.white;
      icon = Icons.info;
      iconColor = Colors.indigoAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: (iconColor ?? Colors.white).withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Icon(icon, size: 16, color: iconColor),
            ),
          Expanded(
            child: SelectableText(
              log,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
