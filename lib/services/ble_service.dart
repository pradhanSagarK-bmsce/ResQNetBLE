import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import '../models/adv_summary.dart';

// ------------------ Data Classes ------------------

class MeshNode {
  final int id;
  DateTime lastSeen;
  int bpm;
  int spo2;
  bool isCritical;
  int lastHopCount;
  
  final double lat;
  final double lon;

  MeshNode({
    required this.id, 
    required this.lastSeen,
    this.bpm = 0,
    this.spo2 = 0,
    this.isCritical = false,
    this.lastHopCount = 0,
    required this.lat,
    required this.lon,
  });
}

class BeaconMessage {
  final int version;
  final int type;      
  final int sourceId;  
  final int seq;       
  final int ttl;       
  final int hopCount;  
  final int payload;   

  BeaconMessage({
    required this.version,
    required this.type,
    required this.sourceId,
    required this.seq,
    required this.ttl,
    required this.hopCount,
    required this.payload,
  });

  Uint8List toBytes() {
    final out = Uint8List(16);
    out[0] = 0xA5; 
    out[1] = 0x5A; 
    out[2] = version & 0xFF;
    out[3] = type & 0xFF;
    out[4] = (sourceId) & 0xFF;
    out[5] = (sourceId >> 8) & 0xFF;
    out[6] = (sourceId >> 16) & 0xFF;
    out[7] = (sourceId >> 24) & 0xFF;
    out[8] = seq & 0xFF;
    out[9] = (seq >> 8) & 0xFF;
    out[10] = ttl & 0xFF;
    out[11] = hopCount & 0xFF;
    out[12] = payload & 0xFF;
    out[13] = (payload >> 8) & 0xFF;
    out[14] = (payload >> 16) & 0xFF;
    out[15] = (payload >> 24) & 0xFF;
    return out;
  }

  static BeaconMessage? fromBytes(Uint8List b) {
    if (b.length < 16) return null;
    if (b[0] != 0xA5 || b[1] != 0x5A) return null;
    
    return BeaconMessage(
      version: b[2],
      type: b[3],
      sourceId: (b[4] & 0xFF) | ((b[5] & 0xFF) << 8) | ((b[6] & 0xFF) << 16) | ((b[7] & 0xFF) << 24),
      seq: (b[8] & 0xFF) | ((b[9] & 0xFF) << 8),
      ttl: b[10] & 0xFF,
      hopCount: b[11] & 0xFF,
      payload: (b[12] & 0xFF) | ((b[13] & 0xFF) << 8) | ((b[14] & 0xFF) << 16) | ((b[15] & 0xFF) << 24),
    );
  }

  String idKey() => '$sourceId:$seq';

  BeaconMessage copyForForwarding() {
    return BeaconMessage(
      version: version,
      type: type,
      sourceId: sourceId,
      seq: seq,
      ttl: ttl - 1, 
      hopCount: hopCount + 1, 
      payload: payload,
    );
  }
}

// ------------------ BleService Class ------------------
class BleService extends ChangeNotifier {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  // State
  bool scanning = false;
  bool advertising = false;
  String permissionStatus = 'unknown';
  
  final Map<int, MeshNode> nodes = {};

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  final Map<String, DateTime> _seenMsgIds = {};
  final int _maxTTL = 5;
  
  Timer? _sourceSimulationTimer;
  bool isSourceMode = false; 
  bool isGatewayMode = false; 
  int _simSeq = 0;
  final int _mySimulatedId = Random().nextInt(999999);

  final double _baseLat = 20.0;
  final double _baseLon = 78.0;

  Future<bool> init() async {
    return await _ensurePermissions();
  }

  Future<bool> _ensurePermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.locationWhenInUse,
    ].request();

    bool granted = statuses.values.every((status) => status.isGranted);
    permissionStatus = granted ? 'granted' : 'denied';
    return granted;
  }

  String getDisplayName(String deviceId) {
    return deviceId;
  }

  // ------------------ SOURCE MODE ------------------
  void startSimulatedSource() async {
    if (!await init()) return;
    isSourceMode = true;
    _addLog("🚨 STARTED SOURCE MODE");

    _sourceSimulationTimer?.cancel();
    _sourceSimulationTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      _simSeq++;
      
      int bpm = 60 + Random().nextInt(40);
      int spo2 = 95 + Random().nextInt(5);
      int status = (Random().nextDouble() > 0.9) ? 1 : 0; 
      
      int payload = (bpm) | (spo2 << 8) | (status << 16);

      final msg = BeaconMessage(
        version: 1,
        type: status == 1 ? 2 : 1, 
        sourceId: _mySimulatedId,
        seq: _simSeq,
        ttl: _maxTTL, 
        hopCount: 0,
        payload: payload,
      );

      _addLog("📢 Broadcasting #${msg.seq} (St:$status)");
      _updateNodeState(msg);
      await _advertiseMeshPacket(msg.toBytes());
    });
  }

  void stopSimulatedSource() {
    isSourceMode = false;
    _sourceSimulationTimer?.cancel();
    _stopAdvertising();
    _addLog("🛑 Stopped Source Mode");
  }

  // ------------------ RELAY MODE ------------------
  void startMeshNetwork() async {
    if (!await init()) return;
    _addLog("🌐 Starting Mesh Listener...");
    startScan(isMeshMode: true);
  }

  Future<void> _advertiseMeshPacket(Uint8List bytes) async {
    // Ensure we stop before starting to avoid state errors
    if (advertising) {
        await _peripheral.stop();
    }

    final advertiseData = AdvertiseData(
      includeDeviceName: false, 
      manufacturerId: 0x02E5, 
      manufacturerData: bytes,
    );

    try {
        await _peripheral.start(advertiseData: advertiseData);
        advertising = true;
        notifyListeners();
        
        // Broadcast for 5 seconds (Increased from 3s to help detection)
        Future.delayed(const Duration(seconds: 5), () {
          if (!isSourceMode) { 
            _stopAdvertising();
          }
        });
    } catch (e) {
        _addLog("❌ Advertise Error: $e");
    }
  }

  Future<void> _stopAdvertising() async {
    if (advertising) {
      try {
          await _peripheral.stop();
      } catch (_) {}
      advertising = false;
      notifyListeners();
    }
  }

  // ------------------ PACKET HANDLING (DEBUG MODE) ------------------
  void _handleAdvertForMesh(Uint8List manData, String deviceId) async {
    BeaconMessage? msg = BeaconMessage.fromBytes(manData);

    if (msg == null && manData.length >= 18) {
       msg = BeaconMessage.fromBytes(manData.sublist(2));
    }

    if (msg == null) return; 

    final key = msg.idKey();
    _updateNodeState(msg);

    // --- DEBUG LOGGING FOR DUPLICATES ---
    if (_seenMsgIds.containsKey(key)) {
        // If we are receiving Hop:1, but we already saw Hop:0, it means
        // we are hearing the Relay (Phone A). This PROVES hopping works.
        if (msg.hopCount > 0) {
             _addLog("ℹ️ Heard Relay from ${deviceId.substring(0,5)}.. (Hop:${msg.hopCount}) [Duplicate]");
        }
        return;
    }
    
    _seenMsgIds[key] = DateTime.now();
    
    int bpm = msg.payload & 0xFF;
    String alertType = msg.type == 2 ? "🚨 CRITICAL" : "ℹ️ Normal";
    
    _addLog("📥 RECV from ${deviceId.substring(0,5)}.. | Hop:${msg.hopCount} | $alertType");

    if (isGatewayMode) {
      _addLog("☁️ UPLOADING #${msg.sourceId}");
      return;
    }

    if (msg.ttl > 0) {
      final newMsg = msg.copyForForwarding();
      _addLog("⤴️ HOPPING (Delay 500ms)...");
      
      // Small random delay to prevent collisions if multiple phones relay at once
      await Future.delayed(Duration(milliseconds: 100 + Random().nextInt(500)));
      await _advertiseMeshPacket(newMsg.toBytes());
    } else {
      _addLog("💀 TTL Expired.");
    }
  }

  void _updateNodeState(BeaconMessage msg) {
    int bpm = msg.payload & 0xFF;
    int spo2 = (msg.payload >> 8) & 0xFF;
    bool critical = ((msg.payload >> 16) & 0xFF) == 1;

    if (nodes.containsKey(msg.sourceId)) {
      final node = nodes[msg.sourceId]!;
      node.lastSeen = DateTime.now();
      node.bpm = bpm;
      node.spo2 = spo2;
      node.isCritical = critical;
      node.lastHopCount = msg.hopCount;
    } else {
      final r = Random(msg.sourceId); 
      double latOffset = (r.nextDouble() - 0.5) * 0.1; 
      double lonOffset = (r.nextDouble() - 0.5) * 0.1;

      nodes[msg.sourceId] = MeshNode(
        id: msg.sourceId,
        lastSeen: DateTime.now(),
        bpm: bpm,
        spo2: spo2,
        isCritical: critical,
        lastHopCount: msg.hopCount,
        lat: _baseLat + latOffset,
        lon: _baseLon + lonOffset,
      );
      notifyListeners();
    }
  }

  // ------------------ SCANNER ------------------
  StreamSubscription? _scanSub;

  void startScan({bool isMeshMode = false}) {
    if (scanning) return;
    scanning = true;
    notifyListeners();
    
    _scanSub = _ble.scanForDevices(
      withServices: [], 
      scanMode: ScanMode.lowLatency,
    ).listen((device) {
      if (device.manufacturerData.isNotEmpty) {
         _handleAdvertForMesh(Uint8List.fromList(device.manufacturerData), device.id);
      }
    }, onError: (e) {
      _addLog("Scan Error: $e");
      scanning = false;
      notifyListeners();
    });
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    scanning = false;
    notifyListeners();
  }

  void _addLog(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    _logs.insert(0, "[$time] $msg");
    if (_logs.length > 100) _logs.removeLast();
    notifyListeners();
    developer.log(msg);
  }
  
  void setGatewayMode(bool enable) {
    isGatewayMode = enable;
    _addLog(enable ? "✅ Device became GATEWAY" : "Device is now RELAY");
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}