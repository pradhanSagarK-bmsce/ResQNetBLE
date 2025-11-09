// lib/services/ble_service.dart
// BLE client for ResQNetBLE — parses manufacturer blob, AD local name (0x08/0x09),
// discovers services, reads GATT device name (0x2A00), subscribes to telemetry.

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

  // Raw discovered device info
  final Map<String, DiscoveredDevice> _seenDevicesRaw = {};
  final Map<String, AdvSummary> devices = {}; // id → parsed summary

  // map deviceId -> best known local name (from adv / DiscoveredDevice.name / GATT read)
  final Map<String, String> deviceLocalNames = {};

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _notifySub;

  bool scanning = false;
  String permissionStatus = 'unknown';
  final List<String> logs = [];
  final int _maxLogs = 300;

  void _addLog(String msg, {String name = 'ble'}) {
    final ts = DateTime.now().toIso8601String();
    final entry = '[$ts] $msg';
    try {
      logs.insert(0, entry);
      if (logs.length > _maxLogs) logs.removeRange(_maxLogs, logs.length);
    } catch (_) {}
    try {
      developer.log(msg, name: name);
    } catch (_) {}
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // === UUIDs (must match server) ===
  final Uuid serviceUuid = Uuid.parse("0000A100-0000-1000-8000-00805F9B34FB");
  final Uuid streamUuid = Uuid.parse("0000A101-0000-1000-8000-00805F9B34FB");
  final Uuid controlUuid = Uuid.parse("0000A103-0000-1000-8000-00805F9B34FB");

  // GATT Device Name characteristic (0x2A00)
  final Uuid gapService = Uuid.parse("00001800-0000-1000-8000-00805f9b34fb");
  final Uuid deviceNameChar = Uuid.parse(
    "00002a00-0000-1000-8000-00805f9b34fb",
  );

  // Auth token
  static const int APP_AUTH_TOKEN = 0xA1B2C3D4;

  // Connection state
  String? connectedId;
  bool authorized = false;
  int lastSeq = -1;
  DateTime? lastPacketTime;
  int missedPackets = 0;

  DateTime? lastConnectAttempt;
  final Duration connectBackoff = const Duration(seconds: 6);

  Future<bool> init() async => await _ensurePermissions();

  Future<bool> _ensurePermissions() async {
    try {
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      bool allGranted = true;
      for (final s in statuses.values) {
        if (!(s.isGranted || s.isLimited)) {
          allGranted = false;
          break;
        }
      }

      permissionStatus = allGranted ? 'granted' : 'denied';
      _addLog('Permission check: $permissionStatus');
      return allGranted;
    } catch (e, st) {
      permissionStatus = 'error';
      _addLog('Permission check error: $e');
      developer.log('Permission error', error: e, stackTrace: st);
      return false;
    }
  }

  // -----------------------
  // AD (advertising) helper: parse AD-TLV to extract local name (0x08/0x09)
  // -----------------------
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

  /// Public helper for UI: return best known display name for a device
  String getDisplayName(String deviceId) {
    final nameFromMap = deviceLocalNames[deviceId];
    String bestName;
    if (nameFromMap != null && nameFromMap.isNotEmpty) {
      bestName = nameFromMap;
    } else {
      final adv = devices[deviceId];
      if (adv != null && adv.valid && (adv.name?.isNotEmpty ?? false)) {
        bestName = adv.name ?? deviceId;
      } else {
        final raw = _seenDevicesRaw[deviceId];
        if (raw != null && raw.name.isNotEmpty)
          bestName = raw.name;
        else
          bestName = deviceId;
      }
    }

    // keep AdvSummary in-sync with bestName so UI reading `devices` gets it
    try {
      if (devices.containsKey(deviceId) &&
          devices[deviceId]!.name != bestName) {
        devices[deviceId]!.name = bestName;
      }
    } catch (_) {}

    return bestName;
  }

  // -----------------------
  // Manufacturer blob parser (matches C++ layout)
  // layout (21 bytes):
  // 0-1: company id (LE)
  // 2: proto ver
  // 3: flags
  // 4: battery
  // 5: bpm
  // 6: spo2
  // 7-8: co2 (LE u16)
  // 9-10: temp (LE int16, centi)
  // 11-13: lat_e5 (LE int24)
  // 14-16: lon_e5 (LE int24)
  // 17-19: ts (LE 24-bit seconds)
  // 20: crc8_maxim over bytes 0..19
  // -----------------------
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

    // CRC check
    final calc = _crc8Maxim(man.sublist(0, 20));
    final crcByte = man[20];
    if (calc != crcByte) {
      adv.valid = false;
      if (advName != null) adv.name = advName;
      _addLog(
        'Manufacturer CRC mismatch (got 0x${crcByte.toRadixString(16)}, calc 0x${calc.toRadixString(16)})',
      );
      return adv;
    }

    final company = (man[0] & 0xFF) | ((man[1] & 0xFF) << 8);
    if (company != 0x02E5) {
      adv.valid = false;
      if (advName != null) adv.name = advName;
      return adv;
    }

    adv.valid = true;
    final proto = man[2];
    final flags = man[3];

    // decode flags into adv (this also sets adv.urgent & adv.gpsValid)
    adv.decodeFlags(flags);

    adv.batt = man[4] & 0xFF;
    adv.bpm = man[5] & 0xFF;
    adv.spo2 = man[6] & 0xFF;
    adv.co2 = (man[7] & 0xFF) | ((man[8] & 0xFF) << 8);

    // temp centi signed LE -> int16
    final tempCenti = ((man[10] << 8) | (man[9] & 0xFF));
    final signedTemp = tempCenti.toSigned(16);
    adv.tempC = signedTemp / 100.0;

    // parse 24-bit signed little-endian to int
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

    // 24-bit ts little-endian
    final ts =
        (man[17] & 0xFF) | ((man[18] & 0xFF) << 8) | ((man[19] & 0xFF) << 16);
    adv.ts = ts;

    if (advName != null && advName.isNotEmpty) adv.name = advName;

    return adv;
  }

  // CRC8/MAXIM (same polynomial) used by server
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

  // -----------------------
  // SCANNING
  // -----------------------
  Future<void> startScan({bool filterService = false}) async {
    final ok = await init();
    if (!ok) {
      _addLog('startScan aborted: permissions not granted');
      scanning = false;
      notifyListeners();
      throw Exception('Permissions not granted');
    }

    if (_scanSub != null) {
      try {
        await _scanSub!.cancel();
      } catch (e) {
        _addLog('Error cancelling existing scan: $e');
      }
      _scanSub = null;
    }

    if (scanning) return;
    scanning = true;
    _addLog('Scan started (filterService=${filterService ? "ON" : "OFF"})');
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
              if (d.manufacturerData.isNotEmpty)
                man = Uint8List.fromList(d.manufacturerData);
            } catch (_) {}

            _seenDevicesRaw[d.id] = d;

            // Try pick a name from AD bytes if those are there in manufacturer or serviceData
            String? nameFromAdv = _parseLocalNameFromAdBytes(man);

            // Some platforms may expose serviceData; try to search for a name there too
            if (nameFromAdv == null) {
              try {
                final dynamic maybeServiceData = (d as dynamic).serviceData;
                if (maybeServiceData is Map) {
                  maybeServiceData.forEach((k, v) {
                    if (nameFromAdv != null) return;
                    try {
                      final Uint8List bytes = v is Uint8List
                          ? v
                          : Uint8List.fromList(List<int>.from(v));
                      nameFromAdv = _parseLocalNameFromAdBytes(bytes);
                    } catch (_) {}
                  });
                }
              } catch (_) {}
            }

            final nameFromDeviceProp = (d.name.isNotEmpty ? d.name : null);
            final chosenName = nameFromAdv ?? nameFromDeviceProp;
            if (chosenName != null && chosenName.isNotEmpty) {
              deviceLocalNames[d.id] = chosenName;
            }

            // Parse manufacturer blob if present
            if (man != null && man.length >= 21) {
              final parsed = _parseManufacturerData(
                man,
                d.rssi,
                advName: chosenName,
              );
              parsed.rssi = d.rssi;
              parsed.lastSeen = DateTime.now();
              if (chosenName != null && chosenName.isNotEmpty)
                parsed.name = chosenName;
              devices[d.id] = parsed;
            } else {
              // ensure minimal entry so UI can show device card
              devices.putIfAbsent(d.id, () => AdvSummary());
              final advEntry = devices[d.id]!;
              advEntry.rssi = d.rssi;
              advEntry.lastSeen = DateTime.now();
              if (chosenName != null && chosenName.isNotEmpty)
                advEntry.name = chosenName;
            }

            // Ensure deviceLocalNames and devices[name] are in sync
            if (chosenName != null && chosenName.isNotEmpty) {
              try {
                deviceLocalNames[d.id] = chosenName;
                if (devices.containsKey(d.id)) devices[d.id]!.name = chosenName;
              } catch (_) {}
            }

            _addLog(
              'Discovered: ${chosenName ?? (d.name.isNotEmpty ? d.name : "<no-name>")} (${d.id}) RSSI=${d.rssi}',
            );
            notifyListeners();

            // Auto connect for urgent devices if manufacturer included urgent bit
            final advSummary = devices[d.id];
            if (advSummary != null && advSummary.urgent) {
              _addLog('Auto-connect candidate (urgent): ${d.id}');
              _tryAutoConnect(d.id);
            }
          },
          onError: (err) {
            scanning = false;
            _addLog('Scan error: $err');
            notifyListeners();
          },
        );
  }

  Future<void> stopScan() async {
    if (_scanSub != null) {
      try {
        await _scanSub!.cancel();
        _addLog('Scan subscription cancelled');
      } catch (e) {
        _addLog('Error cancelling scan subscription: $e');
      }
      _scanSub = null;
    }
    if (!scanning) return;
    scanning = false;
    _addLog('Scan stopped');
    notifyListeners();
  }

  // -----------------------
  // CONNECT / AUTO-CONNECT
  // -----------------------
  Future<void> manualConnect(String deviceId) async {
    _addLog('Manual connect requested: $deviceId');
    await stopScan();
    _cleanupConnection();

    try {
      _connSub = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 10),
          )
          .listen(
            (update) async {
              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  _addLog('Connected: $deviceId');
                  connectedId = deviceId;
                  authorized = false;
                  notifyListeners();
                  await _discoverAndLog(deviceId);
                  await _authorizeAndSubscribe(deviceId);
                  break;
                case DeviceConnectionState.disconnecting:
                  _addLog('Disconnecting: $deviceId');
                  break;
                case DeviceConnectionState.disconnected:
                  _addLog('Disconnected: $deviceId');
                  if (connectedId == deviceId) _cleanupConnection();
                  break;
                case DeviceConnectionState.connecting:
                  _addLog('Connecting: $deviceId');
                  break;
              }
            },
            onError: (err) {
              _addLog('Connection error: $err');
              _cleanupConnection();
            },
          );
    } catch (e) {
      _addLog('manualConnect exception: $e');
      _cleanupConnection();
    }
  }

  Future<void> _tryAutoConnect(String deviceId) async {
    if (connectedId != null) return;
    final now = DateTime.now();
    if (lastConnectAttempt != null &&
        now.difference(lastConnectAttempt!) < connectBackoff) {
      _addLog('Auto-connect backoff: ${deviceId}');
      return;
    }
    lastConnectAttempt = now;

    _addLog('Attempting auto-connect: $deviceId');

    try {
      _connSub = _ble
          .connectToDevice(
            id: deviceId,
            connectionTimeout: const Duration(seconds: 8),
          )
          .listen(
            (update) async {
              switch (update.connectionState) {
                case DeviceConnectionState.connected:
                  _addLog('Auto-connected: $deviceId');
                  connectedId = deviceId;
                  authorized = false;
                  notifyListeners();
                  await _discoverAndLog(deviceId);
                  await _authorizeAndSubscribe(deviceId);
                  break;
                case DeviceConnectionState.disconnected:
                  _addLog('Auto-connect disconnected: $deviceId');
                  if (connectedId == deviceId) _cleanupConnection();
                  break;
                default:
                  break;
              }
            },
            onError: (err) {
              _addLog('Auto-connect error: $err');
              _cleanupConnection();
            },
          );
    } catch (e) {
      _addLog('Auto-connect exception: $e');
      _cleanupConnection();
    }
  }

  // -----------------------
  // SERVICE DISCOVERY + READ DEVICE NAME
  // -----------------------
  Future<void> _discoverAndLog(String deviceId) async {
    _addLog('Discovering services for $deviceId ...');
    try {
      final services = await _ble.discoverServices(deviceId);
      _addLog('Discovered ${services.length} services for $deviceId');
      for (final s in services) {
        _addLog(' Service: ${s.serviceId.toString()}');
        for (final c in s.characteristics) {
          final props = <String>[];
          if (c.isReadable) props.add('READ');
          if (c.isWritableWithResponse) props.add('WRITE');
          if (c.isWritableWithoutResponse) props.add('WRITE_NO_RESP');
          if (c.isNotifiable) props.add('NOTIFY');
          if (c.isIndicatable) props.add('INDICATE');

          _addLog('  Char: ${c.characteristicId} props=${props.join(',')}');

          if (c.isReadable) {
            try {
              final val = await _ble.readCharacteristic(
                QualifiedCharacteristic(
                  serviceId: s.serviceId,
                  characteristicId: c.characteristicId,
                  deviceId: deviceId,
                ),
              );
              final hex = _hex(val);
              String text = '';
              try {
                text = utf8.decode(val);
              } catch (_) {}
              _addLog('   Read: $hex ${text.isNotEmpty ? '("$text")' : ''}');

              // If Device Name characteristic, store it
              if (s.serviceId.toString().toLowerCase() ==
                      gapService.toString().toLowerCase() &&
                  c.characteristicId.toString().toLowerCase() ==
                      deviceNameChar.toString().toLowerCase()) {
                final name = text.trim();
                if (name.isNotEmpty) {
                  deviceLocalNames[deviceId] = name;
                  if (devices.containsKey(deviceId))
                    devices[deviceId]!.name = name;
                  _addLog('   GATT Device Name read: $name');
                  notifyListeners();
                }
              }
            } catch (e) {
              _addLog('   Read failed: $e');
            }
          }
        }
      }
    } catch (e) {
      _addLog('Service discovery failed: $e');
    }
    notifyListeners();
  }

  // -----------------------
  // AUTH + SUBSCRIBE
  // -----------------------
  Future<void> _authorizeAndSubscribe(String deviceId) async {
    try {
      final token = ByteData(4)..setUint32(0, APP_AUTH_TOKEN, Endian.little);
      final ctrlChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: controlUuid,
        deviceId: deviceId,
      );

      _addLog('Writing auth token to control char...');
      await _ble.writeCharacteristicWithResponse(
        ctrlChar,
        value: token.buffer.asUint8List(),
      );

      // Try read back ack
      try {
        final ack = await _ble.readCharacteristic(ctrlChar);
        final ackStr = String.fromCharCodes(ack);
        _addLog(
          'Control read: ${_hex(ack)} ${ackStr.isNotEmpty ? ackStr : ''}',
        );
        if (ackStr == 'OK') {
          authorized = true;
          _addLog('Authorized via OK');
        } else {
          // some servers may not reply OK; treat write success as authorized
          authorized = true;
        }
      } catch (e) {
        _addLog('Control read failed (assuming write success): $e');
        authorized = true;
      }

      final streamChar = QualifiedCharacteristic(
        serviceId: serviceUuid,
        characteristicId: streamUuid,
        deviceId: deviceId,
      );

      _addLog('Subscribing to stream char...');
      _notifySub = _ble
          .subscribeToCharacteristic(streamChar)
          .listen(
            (data) {
              _handleStreamPacket(data);
            },
            onError: (err) {
              _addLog('Stream subscription error: $err');
              _cleanupConnection();
            },
          );

      notifyListeners();
    } catch (e, st) {
      _addLog('Authorize/subscribe failed: $e');
      developer.log('authorize error', error: e, stackTrace: st);
      authorized = false;
      _cleanupConnection();
      notifyListeners();
    }
  }

  // -----------------------
  // PACKET HANDLER
  // -----------------------
  void _handleStreamPacket(List<int> raw) async {
    try {
      if (raw.length < 15) {
        _addLog('Stream packet too small: ${raw.length}');
        return;
      }
      if (raw[0] != 0xA1 || raw[1] != 0xB2) {
        _addLog('Stream packet header mismatch: ${_hex(raw.sublist(0, 2))}');
        return;
      }

      final pktType = raw[2];
      final seq = raw[3];
      // ts = bytes 4..9 (6 bytes)
      final bpm = raw[10];
      final spo2 = raw[11];
      final co2 = raw[12] | (raw[13] << 8);
      final flags = raw[14];

      if (lastSeq != -1 && ((lastSeq + 1) & 0xFF) != seq) {
        missedPackets++;
        _addLog(
          'Packet gap detected: expected ${(lastSeq + 1) & 0xFF} got $seq (missed total $missedPackets)',
        );
      }
      lastSeq = seq;
      lastPacketTime = DateTime.now();

      _addLog(
        'Telemetry pkt seq=$seq bpm=$bpm spo2=$spo2 co2=$co2 flags=0x${flags.toRadixString(16)}',
      );

      // ACK back on control char: "ACK" + seq
      if (connectedId != null) {
        final ackChar = QualifiedCharacteristic(
          serviceId: serviceUuid,
          characteristicId: controlUuid,
          deviceId: connectedId!,
        );
        final Uint8List ack = Uint8List.fromList([
          0x41,
          0x43,
          0x4B,
          seq,
        ]); // 'A' 'C' 'K' seq
        try {
          await _ble.writeCharacteristicWithoutResponse(ackChar, value: ack);
          _addLog('Sent ACK seq=$seq');
        } catch (e) {
          _addLog('Failed to send ACK: $e');
        }
      }

      if (connectedId != null && devices.containsKey(connectedId)) {
        final cur = devices[connectedId]!;
        cur.bpm = bpm;
        cur.spo2 = spo2;
        cur.co2 = co2;
        // decode flags into adv entry as well (keeps UI consistent)
        cur.decodeFlags(flags);
        cur.lastSeen = DateTime.now();
        cur.rssi = _seenDevicesRaw[connectedId]?.rssi ?? cur.rssi;
        devices[connectedId!] = cur;
        notifyListeners();
      }
    } catch (e) {
      _addLog('handleStreamPacket exception: $e');
    }
  }

  // expose a public helper to read device name over GATT on demand
  Future<void> readGattDeviceName(String deviceId) async {
    try {
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
        _addLog('GATT read Device Name: $name');
        notifyListeners();
      }
    } catch (e) {
      _addLog('readGattDeviceName failed: $e');
    }
  }

  Future<void> discoverServicesForDevice(String deviceId) async {
    await _discoverAndLog(deviceId);
  }

  // -----------------------
  // CLEANUP
  // -----------------------
  void _cleanupConnection() {
    _notifySub?.cancel();
    _notifySub = null;
    _connSub?.cancel();
    _connSub = null;
    _addLog('Connection cleaned up');
    connectedId = null;
    authorized = false;
    lastSeq = -1;
    missedPackets = 0;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _addLog('Disconnect requested');
    _cleanupConnection();
    await stopScan();
  }

  String get status {
    if (connectedId == null) return scanning ? "Scanning..." : "Idle";
    if (!authorized) return "Connected (authenticating)";
    return "Connected (authorized)";
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
