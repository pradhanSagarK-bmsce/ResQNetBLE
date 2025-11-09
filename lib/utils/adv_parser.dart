import 'dart:typed_data';
import 'crc8.dart';
import '../models/adv_summary.dart';

/// Parse manufacturer data bytes (21 bytes) into AdvSummary.
/// This is defensive: handles Uint8List or List<int>.
AdvSummary parseManufacturerData(Uint8List data, int rssi) {
  final out = AdvSummary();
  try {
    if (data.length < 21) return out;
    // Check company id LE
    final company = (data[1] << 8) | data[0];
    if (company != 0x02E5) return out;
    final proto = data[2];
    // Validate CRC8 of bytes 0..19
    final crc = crc8Maxim(data.toList(), 20);
    if (crc != data[20]) return out;

    final flags = data[3];
    out.urgent = ((flags >> 3) & 1) == 1;
    out.gpsValid = ((flags >> 6) & 1) == 1;
    out.batt = data[4];
    out.bpm = data[5];
    out.spo2 = data[6];
    out.co2 = data[7] | (data[8] << 8);
    // temp signed int16 LE
    int tempRaw = (data[9] | (data[10] << 8));
    if (tempRaw & 0x8000 != 0) tempRaw = tempRaw - 0x10000;
    out.tempC = tempRaw / 100.0;
    int lat_e5 = (data[11] | (data[12] << 8) | (data[13] << 16));
    if ((lat_e5 & 0x800000) != 0) lat_e5 = lat_e5 - 0x1000000;
    out.lat = lat_e5 / 1e5;
    int lon_e5 = (data[14] | (data[15] << 8) | (data[16] << 16));
    if ((lon_e5 & 0x800000) != 0) lon_e5 = lon_e5 - 0x1000000;
    out.lon = lon_e5 / 1e5;
    out.ts = data[17] | (data[18] << 8) | (data[19] << 16);
    out.valid = true;
    out.rssi = rssi;
    out.lastSeen = DateTime.now();
  } catch (e) {
    // ignore parse errors
  }
  return out;
}
