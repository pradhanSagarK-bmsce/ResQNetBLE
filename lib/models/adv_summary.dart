// lib/models/adv_summary.dart
class AdvSummary {
  bool valid = false;
  bool urgent = false;
  bool gpsValid = false;

  // sensor / vitals
  int batt = 0;
  int bpm = 0;
  int spo2 = 0;
  int co2 = 0;
  double tempC = 0.0;

  // location / timestamp
  double lat = 0.0;
  double lon = 0.0;
  int ts = 0; // seconds (24-bit in adv)

  // radio/meta
  int rssi = 0;
  DateTime lastSeen = DateTime.now();

  /// Human-friendly names (filled from advertisement AD fields or GATT read)
  String? name; // full discovered name

  /// Derived flags (decoded from manufacturer flags byte)
  bool freefall = false;
  bool vibration = false;
  bool shock = false;
  bool fall = false;
  bool tilt = false;

  AdvSummary();

  /// Decode single flags byte (same semantics as the ESP32 server)
  /// Bits per server:
  /// bit0 = freefall
  /// bit1 = vibration
  /// bit2 = tilt
  /// bit3 = urgent / fall
  /// bit5 = abnormalVitals proxy (server also sets vibration into this)
  /// bit6 = gpsOK
  void decodeFlags(int flags) {
    freefall = (flags & (1 << 0)) != 0;
    vibration = (flags & (1 << 1)) != 0;
    tilt = (flags & (1 << 2)) != 0;
    fall = (flags & (1 << 3)) != 0;
    // server used bit5 as abnormalVitals proxy - keep a mapping to shock or leave as vibration-proxy
    shock =
        (flags & (1 << 4)) !=
        0; // bit4 isn't used by server currently, but keep it available
    // some server builds set bit5 as abnormalVitals indicator (we don't have a dedicated field)
    // but you can read bit5 if needed: (flags & (1<<5)) != 0
    gpsValid = (flags & (1 << 6)) != 0;
    urgent = (flags & (1 << 3)) != 0;
  }

  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : '<unknown>';

  String get shortName {
    if (name == null) return '<unk>';
    return name!.length > 12 ? name!.substring(0, 12) + '…' : name!;
  }

  @override
  String toString() {
    return 'AdvSummary(name=$name valid=$valid urgent=$urgent gpsValid=$gpsValid batt=$batt bpm=$bpm spo2=$spo2 co2=$co2 tempC=$tempC lat=$lat lon=$lon ts=$ts rssi=$rssi lastSeen=$lastSeen freefall=$freefall vibration=$vibration shock=$shock fall=$fall tilt=$tilt)';
  }
}
