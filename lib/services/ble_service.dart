// lib/services/ble_service.dart
// FIXED: Proper GATT connection, service discovery, and notification subscription

import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/adv_summary.dart';

class BleService extends ChangeNotifier {
  final FlutterReactiveBle _ble = FlutterReactiveBle();

  final Map<String, DiscoveredDevice> _seenDevicesRaw = {};
  final Map<String, AdvSummary> devices = {};
  final Map<String, String> deviceLocalNames = {};

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  bool scanning = false;
  String permissionStatus = 'unknown';
  final List<String> _logs = [];
  final int _maxLogs = 300;

  String? connectedId;
  bool authorized = false;
  int lastSeq = -1;
  DateTime? lastPacketTime;
  int missedPackets = 0;
  int totalPacketsReceived = 0;
  DateTime? connectionTime;
  bool isSubscribed = false;

  final List<DiscoveredService> _discoveredServices = [];

  DateTime? lastConnectAttempt;
  final Duration connectBackoff = const Duration(seconds: 6);

  List<String> get logs => List.unmodifiable(_logs);
  List<DiscoveredService> get discoveredServices =>
      List.unmodifiable(_discoveredServices);

  void _addLog(String msg, {String name = 'ble'}) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final entry = '[$ts] $msg';
    try {
      _logs.insert(0, entry);
      if (_logs.length > _maxLogs) {
        _logs.removeRange(_maxLogs, _logs.length);
      }
    } catch (e) {
      developer.log('Log error: $e');
    }
    try {
      developer.log(msg, name: name);
    } catch (_) {}
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    _addLog('🗑️ Logs cleared');
  }

  final Uuid serviceUuid = Uuid.parse("0000A100-0000-1000-8000-00805F9B34FB");
  final Uuid streamUuid = Uuid.parse("0000A101-0000-1000-8000-00805F9B34FB");
  final Uuid controlUuid = Uuid.parse("0000A103-0000-1000-8000-00805F9B34FB");
  final Uuid gapService = Uuid.parse("00001800-0000-1000-8000-00805f9b34fb");
  final Uuid deviceNameChar = Uuid.parse(
    "00002a00-0000-1000-8000-00805f9b34fb",
  );

  static const int APP_AUTH_TOKEN = 0xA1B2C3D4;

  Future<bool> init() async => await _ensurePermissions();

  Future<bool> _ensurePermissions() async {
    try {
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      bool allGranted = statuses.values.every(
        (s) => s.isGranted || s.isLimited,
      );
      permissionStatus = allGranted ? 'granted' : 'denied';
      _addLog('Permissions: $permissionStatus');
      return allGranted;
    } catch (e, st) {
      permissionStatus = 'error';
      _addLog('Permission error: $e');
      developer.log('Permission error', error: e, stackTrace: st);
      return false;
    }
  }

  String? _parseLocalNameFromAdBytes(Uint8List? advBytes) {
    if (advBytes == null || advBytes.isEmpty) return null;

    int i = 0;
    while (i < advBytes.length) {
      final len = advBytes[i];
      if (len == 0) break;
      final tIndex = i + 1;
      if (tIndex >= advBytes.length) break;
      final type = advBytes[tIndex];
      final payloadStart = tIndex + 1;
      final payloadLen = len - 1;
      if (payloadStart + payloadLen > advBytes.length) break;

      if (type == 0x08 || type == 0x09) {
        try {
          final nameBytes = advBytes.sublist(
            payloadStart,
            payloadStart + payloadLen,
          );
          final name = utf8.decode(nameBytes, allowMalformed: true).trim();
          if (name.isNotEmpty) return name;
        } catch (_) {}
      }
      i = payloadStart + payloadLen;
    }
    return null;
  }

  String getDisplayName(String deviceId) {
    final nameFromMap = deviceLocalNames[deviceId];
    String bestName;

    if (nameFromMap != null && nameFromMap.isNotEmpty) {
      bestName = nameFromMap;
    } else {
      final adv = devices[deviceId];
      if (adv != null && adv.valid && (adv.name?.isNotEmpty ?? false)) {
        bestName = adv.name!;
      } else {
        final raw = _seenDevicesRaw[deviceId];
        bestName = (raw != null && raw.name.isNotEmpty) ? raw.name : deviceId;
      }
    }

    if (devices.containsKey(deviceId) && devices[deviceId]!.name != bestName) {
      devices[deviceId]!.name = bestName;
    }

    return bestName;
  }

  AdvSummary _parseManufacturerData(
    Uint8List man,
    int rssi, {
    String? advName,
  }) {
    final adv = AdvSummary();
    adv.rssi = rssi;
    adv.lastSeen = DateTime.now();

    if (man.length < 21) {
      adv.valid = false;
      if (advName != null) adv.name = advName;
      return adv;
    }

    final calc = _crc8Maxim(man.sublist(0, 20));
    final crcByte = man[20];
    if (calc != crcByte) {
      adv.valid = false;
      if (advName != null) adv.name = advName;
      return adv;
    }

    final company = (man[0] & 0xFF) | ((man[1] & 0xFF) << 8);
    if (company != 0x02E5) {
      adv.valid = false;
      if (advName != null) adv.name = advName;
      return adv;
    }

    adv.valid = true;
    final flags = man[3];
    adv.decodeFlags(flags);

    adv.batt = man[4] & 0xFF;
    adv.bpm = man[5] & 0xFF;
    adv.spo2 = man[6] & 0xFF;
    adv.co2 = (man[7] & 0xFF) | ((man[8] & 0xFF) << 8);

    final tempCenti = ((man[10] << 8) | (man[9] & 0xFF));
    final signedTemp = tempCenti.toSigned(16);
    adv.tempC = signedTemp / 100.0;

    int readInt24LE(Uint8List arr, int idx) {
      int v =
          (arr[idx] & 0xFF) |
          ((arr[idx + 1] & 0xFF) << 8) |
          ((arr[idx + 2] & 0xFF) << 16);
      if ((v & 0x800000) != 0) v |= 0xFF000000;
      return v;
    }

    final lat_e5 = readInt24LE(man, 11);
    final lon_e5 = readInt24LE(man, 14);
    adv.lat = lat_e5 / 1e5;
    adv.lon = lon_e5 / 1e5;

    final ts =
        (man[17] & 0xFF) | ((man[18] & 0xFF) << 8) | ((man[19] & 0xFF) << 16);
    adv.ts = ts;

    if (advName != null && advName.isNotEmpty) adv.name = advName;

    return adv;
  }

  int _crc8Maxim(Uint8List data) {
    int crc = 0x00;
    for (int b in data) {
      crc ^= (b & 0xFF);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x01) != 0) {
          crc = ((crc >> 1) ^ 0x8C) & 0xFF;
        } else {
          crc = (crc >> 1) & 0xFF;
        }
      }
    }
    return crc & 0xFF;
  }

  Future<void> startScan({bool filterService = false}) async {
    final ok = await init();
    if (!ok) {
      _addLog('Scan aborted: permissions denied');
      scanning = false;
      notifyListeners();
      throw Exception('Permissions not granted');
    }

    if (_scanSub != null) {
      try {
        await _scanSub!.cancel();
      } catch (e) {
        _addLog('Error cancelling scan: $e');
      }
      _scanSub = null;
    }

    if (scanning) return;
    scanning = true;
    _addLog('▶ Scan started (filter=${filterService ? "ON" : "OFF"})');
    notifyListeners();

    _scanSub = _ble
        .scanForDevices(
          withServices: filterService ? [serviceUuid] : [],
          scanMode: ScanMode.lowLatency,
        )
        .listen(
          (d) {
            Uint8List? man;
            try {
              if (d.manufacturerData.isNotEmpty) {
                man = Uint8List.fromList(d.manufacturerData);
              }
            } catch (_) {}

            _seenDevicesRaw[d.id] = d;

            String? nameFromAdv = _parseLocalNameFromAdBytes(man);
            final nameFromDeviceProp = (d.name.isNotEmpty ? d.name : null);
            final chosenName = nameFromAdv ?? nameFromDeviceProp;

            if (chosenName != null && chosenName.isNotEmpty) {
              deviceLocalNames[d.id] = chosenName;
            }

            if (man != null && man.length >= 21) {
              final parsed = _parseManufacturerData(
                man,
                d.rssi,
                advName: chosenName,
              );
              devices[d.id] = parsed;
            } else {
              devices.putIfAbsent(d.id, () => AdvSummary());
              final advEntry = devices[d.id]!;
              advEntry.rssi = d.rssi;
              advEntry.lastSeen = DateTime.now();
              if (chosenName != null) advEntry.name = chosenName;
            }

            if (chosenName != null && chosenName.isNotEmpty) {
              deviceLocalNames[d.id] = chosenName;
              if (devices.containsKey(d.id)) devices[d.id]!.name = chosenName;
            }

            notifyListeners();

            final advSummary = devices[d.id];
            if (advSummary != null && advSummary.urgent) {
              _addLog('🚨 Urgent device detected: ${d.id}');
              _tryAutoConnect(d.id);
            }
          },
          onError: (err) {
            scanning = false;
            _addLog('❌ Scan error: $err');
            notifyListeners();
          },
        );
  }

  Future<void> stopScan() async {
    if (_scanSub != null) {
      try {
        await _scanSub!.cancel();
      } catch (e) {
        _addLog('Error stopping scan: $e');
      }
      _scanSub = null;
    }
    if (!scanning) return;
    scanning = false;
    _addLog('⏸ Scan stopped');
    notifyListeners();
  }

  // FIXED: Improved connection flow with proper timing
  Future<void> manualConnect(String deviceId) async {
    _addLog('========================================');
    _addLog('🔗 Manual connect to: ${getDisplayName(deviceId)}');
    _addLog('========================================');
    await stopScan();
    _cleanupConnection();

    try {
      connectionTime = DateTime.now();
      _connSub = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 20),
          )
          .listen(
            (update) async {
              _addLog('Connection state: ${update.connectionState}');

              switch (update.connectionState) {
                case DeviceConnectionState.connecting:
                  _addLog('⏳ Connecting...');
                  break;

                case DeviceConnectionState.connected:
                  _addLog('✅ CONNECTED!');
                  connectedId = deviceId;
                  authorized = false;
                  isSubscribed = false;
                  notifyListeners();

                  // FIXED: Proper sequencing with delays
                  _addLog('⏳ Waiting 800ms before discovery...');
                  await Future.delayed(const Duration(milliseconds: 800));

                  _addLog('🔍 Starting service discovery...');
                  await _discoverAndLog(deviceId);

                  _addLog('⏳ Waiting 500ms before auth...');
                  await Future.delayed(const Duration(milliseconds: 500));

                  _addLog('🔐 Starting auth & subscribe...');
                  await _authorizeAndSubscribe(deviceId);

                  _addLog('========================================');
                  _addLog('✅ Connection sequence complete!');
                  _addLog('Subscribed: $isSubscribed');
                  _addLog('========================================');
                  break;

                case DeviceConnectionState.disconnecting:
                  _addLog('⏳ Disconnecting...');
                  break;

                case DeviceConnectionState.disconnected:
                  _addLog('❌ Disconnected');
                  if (connectedId == deviceId) _cleanupConnection();
                  break;
              }
            },
            onError: (err) {
              _addLog('❌ Connection error: $err');
              _cleanupConnection();
            },
          );
    } catch (e, st) {
      _addLog('❌ Connect exception: $e');
      developer.log('Connect error', error: e, stackTrace: st);
      _cleanupConnection();
    }
  }

  Future<void> _tryAutoConnect(String deviceId) async {
    if (connectedId != null) return;

    final now = DateTime.now();
    if (lastConnectAttempt != null &&
        now.difference(lastConnectAttempt!) < connectBackoff) {
      _addLog('⏳ Auto-connect backoff');
      return;
    }
    lastConnectAttempt = now;

    _addLog('🔗 Auto-connecting...');

    try {
      connectionTime = DateTime.now();
      _connSub = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 15),
          )
          .listen(
            (update) async {
              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  _addLog('✅ Auto-connected');
                  connectedId = deviceId;
                  authorized = false;
                  isSubscribed = false;
                  notifyListeners();
                  await Future.delayed(const Duration(milliseconds: 800));
                  await _discoverAndLog(deviceId);
                  await Future.delayed(const Duration(milliseconds: 500));
                  await _authorizeAndSubscribe(deviceId);
                  break;

                case DeviceConnectionState.disconnected:
                  _addLog('❌ Auto-connect disconnected');
                  if (connectedId == deviceId) _cleanupConnection();
                  break;

                default:
                  break;
              }
            },
            onError: (err) {
              _addLog('❌ Auto-connect error: $err');
              _cleanupConnection();
            },
          );
    } catch (e) {
      _addLog('❌ Auto-connect exception: $e');
      _cleanupConnection();
    }
  }

  // FIXED: Better service discovery
  Future<void> _discoverAndLog(String deviceId) async {
    _addLog('🔍 Discovering services...');
    try {
      final services = await _ble.discoverServices(deviceId);
      _discoveredServices.clear();
      _discoveredServices.addAll(services);
      _addLog('📋 Found ${services.length} services');

      for (final s in services) {
        _addLog('  📦 Service: ${s.serviceId}');
        for (final c in s.characteristics) {
          final props = <String>[];
          if (c.isReadable) props.add('R');
          if (c.isWritableWithResponse) props.add('W');
          if (c.isWritableWithoutResponse) props.add('Wn');
          if (c.isNotifiable) props.add('N');
          if (c.isIndicatable) props.add('I');

          _addLog('    📝 Char: ${c.characteristicId} [${props.join(',')}]');

          // Read Device Name if available
          if (s.serviceId.toString().toLowerCase() ==
                  gapService.toString().toLowerCase() &&
              c.characteristicId.toString().toLowerCase() ==
                  deviceNameChar.toString().toLowerCase() &&
              c.isReadable) {
            try {
              final val = await _ble.readCharacteristic(
                QualifiedCharacteristic(
                  serviceId: s.serviceId,
                  characteristicId: c.characteristicId,
                  deviceId: deviceId,
                ),
              );
              final name = utf8.decode(val).trim();
              if (name.isNotEmpty) {
                deviceLocalNames[deviceId] = name;
                if (devices.containsKey(deviceId))
                  devices[deviceId]!.name = name;
                _addLog('      📛 Device Name: "$name"');
                notifyListeners();
              }
            } catch (e) {
              _addLog('      ⚠️ Read Device Name failed: $e');
            }
          }
        }
      }

      _addLog('✅ Service discovery complete');
    } catch (e, st) {
      _addLog('❌ Service discovery failed: $e');
      developer.log('Discovery error', error: e, stackTrace: st);
    }
    notifyListeners();
  }

  // FIXED: Improved auth and subscription
  Future<void> _authorizeAndSubscribe(String deviceId) async {
    try {
      // Write auth token (even though it's disabled on ESP32, good practice)
      final token = ByteData(4)..setUint32(0, APP_AUTH_TOKEN, Endian.little);
      final ctrlChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: controlUuid,
        deviceId: deviceId,
      );

      _addLog('🔑 Writing auth token...');
      try {
        await _ble.writeCharacteristicWithResponse(
          ctrlChar,
          value: token.buffer.asUint8List(),
        );
        _addLog('✅ Auth token written');
      } catch (e) {
        _addLog('⚠️ Auth write failed (may be OK): $e');
      }

      // Try read ACK
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        final ack = await _ble.readCharacteristic(ctrlChar);
        final ackStr = String.fromCharCodes(ack);
        _addLog('📥 Control ACK: "$ackStr"');
        authorized = (ackStr == 'OK');
      } catch (e) {
        _addLog('⚠️ No ACK read (assuming authorized): $e');
        authorized = true;
      }

      // FIXED: Subscribe to stream characteristic
      final streamChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: streamUuid,
        deviceId: deviceId,
      );

      _addLog('========================================');
      _addLog('📡 Subscribing to telemetry stream...');
      _addLog('Service: ${serviceUuid.toString()}');
      _addLog('Char: ${streamUuid.toString()}');
      _addLog('========================================');

      // Cancel any existing subscription
      if (_notifySub != null) {
        await _notifySub!.cancel();
        _notifySub = null;
      }

      // Subscribe with better error handling
      _notifySub = _ble
          .subscribeToCharacteristic(streamChar)
          .listen(
            (data) {
              _addLog('📦 Received ${data.length} bytes');
              _handleStreamPacket(data);
            },
            onError: (err) {
              _addLog('❌ Stream error: $err');
              isSubscribed = false;
              notifyListeners();
            },
            onDone: () {
              _addLog('⚠️ Stream subscription closed');
              isSubscribed = false;
              notifyListeners();
            },
          );

      isSubscribed = true;
      _addLog('========================================');
      _addLog('✅✅✅ SUBSCRIBED TO TELEMETRY STREAM!');
      _addLog('========================================');
      notifyListeners();
    } catch (e, st) {
      _addLog('========================================');
      _addLog('❌❌❌ Auth/subscribe FAILED: $e');
      _addLog('========================================');
      developer.log('Auth error', error: e, stackTrace: st);
      authorized = false;
      isSubscribed = false;
      notifyListeners();
    }
  }

  // FIXED: Better packet handler
  void _handleStreamPacket(List<int> raw) async {
    try {
      if (raw.length < 15) {
        _addLog('⚠️ Packet too small: ${raw.length} bytes');
        return;
      }

      if (raw[0] != 0xA1 || raw[1] != 0xB2) {
        _addLog('⚠️ Bad header: ${_hex(raw.sublist(0, 2))}');
        return;
      }

      final seq = raw[3];
      final bpm = raw[10];
      final spo2 = raw[11];
      final co2 = raw[12] | (raw[13] << 8);
      final flags = raw[14];

      // Check for missed packets
      if (lastSeq != -1 && ((lastSeq + 1) & 0xFF) != seq) {
        missedPackets++;
        _addLog(
          '⚠️ Gap: expected ${(lastSeq + 1) & 0xFF}, got $seq (total missed: $missedPackets)',
        );
      }

      lastSeq = seq;
      lastPacketTime = DateTime.now();
      totalPacketsReceived++;

      _addLog(
        '📊 Pkt#$seq: BPM=$bpm SpO2=$spo2 CO2=$co2 flags=0x${flags.toRadixString(16).padLeft(2, '0')}',
      );

      // Send ACK
      if (connectedId != null) {
        final ackChar = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: controlUuid,
          deviceId: connectedId!,
        );
        final ack = Uint8List.fromList([0x41, 0x43, 0x4B, seq]); // 'ACK' + seq
        try {
          await _ble.writeCharacteristicWithoutResponse(ackChar, value: ack);
        } catch (e) {
          _addLog('⚠️ ACK send failed: $e');
        }
      }

      // Update device data
      if (connectedId != null && devices.containsKey(connectedId)) {
        devices[connectedId]!.updateFromTelemetry(
          seq: seq,
          bpm: bpm,
          spo2: spo2,
          co2: co2,
          flags: flags,
        );
        notifyListeners();
      }
    } catch (e, st) {
      _addLog('❌ Packet handler error: $e');
      developer.log('Packet error', error: e, stackTrace: st);
    }
  }

  Future<void> readGattDeviceName(String deviceId) async {
    try {
      _addLog('📛 Reading device name...');
      final char = QualifiedCharacteristic(
        serviceId: gapService,
        characteristicId: deviceNameChar,
        deviceId: deviceId,
      );
      final val = await _ble.readCharacteristic(char);
      final name = utf8.decode(val).trim();
      if (name.isNotEmpty) {
        deviceLocalNames[deviceId] = name;
        if (devices.containsKey(deviceId)) devices[deviceId]!.name = name;
        _addLog('✅ Device Name: "$name"');
        notifyListeners();
      }
    } catch (e) {
      _addLog('❌ Read Device Name failed: $e');
    }
  }

  Future<void> discoverServicesForDevice(String deviceId) async {
    await _discoverAndLog(deviceId);
  }

  void _cleanupConnection() {
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
    connectedId = null;
    authorized = false;
    isSubscribed = false;
    lastSeq = -1;
    missedPackets = 0;
    totalPacketsReceived = 0;
    connectionTime = null;
    _discoveredServices.clear();
    _addLog('🧹 Connection cleaned up');
    notifyListeners();
  }

  Future<void> disconnect() async {
    _addLog('🔌 Disconnect requested');
    _cleanupConnection();
    await stopScan();
  }

  String get status {
    if (connectedId == null) return scanning ? "Scanning..." : "Idle";
    if (!authorized) return "Connected (auth...)";
    if (!isSubscribed) return "Connected (subscribing...)";
    return "Connected & Streaming";
  }

  String get connectionDuration {
    if (connectionTime == null) return "—";
    final duration = DateTime.now().difference(connectionTime!);
    final mins = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return "${mins}m ${secs}s";
  }

  String _hex(List<int> data) {
    return data
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join('-')
        .toUpperCase();
  }

  @override
  void dispose() {
    stopScan();
    _cleanupConnection();
    super.dispose();
  }
}
