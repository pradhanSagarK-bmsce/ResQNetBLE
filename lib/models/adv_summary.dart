// lib/models/adv_summary.dart
/// Represents a compact summary produced from advertisements and live telemetry.
/// This model contains:
///  - Manufacturer AD summary fields (batt, bpm, spo2, co2, temp, lat/lon, ts)
///  - Decoded flags and a raw `flags` byte
///  - Extended telemetry fields (acc/gyro, pressure/humidity, speed/altitude)
///  - Radio/meta (rssi, lastSeen)
class AdvSummary {
  // Basic validity/metadata
  bool valid = false;
  bool urgent = false;
  bool gpsValid = false;
  int flagsRaw = 0; // raw flags byte from manufacturer packet (if present)

  // sensor / vitals (from manufacturer adv or stream)
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

  // Human-friendly names (filled from advertisement AD fields or GATT read)
  String? name; // full discovered name

  // Derived flags (decoded from manufacturer flags byte)
  bool freefall = false;
  bool vibration = false;
  bool shock = false;
  bool fall = false;
  bool tilt = false;

  // Extended telemetry (from GATT streaming packets)
  // Accelerometer (m/s^2 or server units — keep as double)
  double accX = 0.0;
  double accY = 0.0;
  double accZ = 0.0;

  // Gyroscope (deg/s or server units)
  double gyrX = 0.0;
  double gyrY = 0.0;
  double gyrZ = 0.0;

  // Environmental / extra
  double pressure = 0.0; // hPa or server unit
  double humidity = 0.0; // %
  double speed = 0.0; // m/s or server unit
  double altitude = 0.0; // meters or server unit

  // Telemetry stream info
  int streamSeq = -1;
  DateTime? lastTelemetryTime;

  AdvSummary();

  /// Decode single flags byte (same semantics as the ESP32 server)
  /// Bits per server:
  /// bit0 = freefall
  /// bit1 = vibration
  /// bit2 = tilt
  /// bit3 = urgent / fall
  /// bit5 = abnormalVitals proxy (server may set this)
  /// bit6 = gpsOK
  void decodeFlags(int flags) {
    flagsRaw = flags & 0xFF;
    freefall = (flags & (1 << 0)) != 0;
    vibration = (flags & (1 << 1)) != 0;
    tilt = (flags & (1 << 2)) != 0;
    // server uses bit3 to indicate urgent/fall
    fall = (flags & (1 << 3)) != 0;
    // bit4 not used by server typically — keep shock mapping if you want
    shock = (flags & (1 << 4)) != 0;
    // bit5 used as abnormalVitals proxy on some server builds
    // we don't map it to a dedicated field, but it's available in flagsRaw
    gpsValid = (flags & (1 << 6)) != 0;
    // urgent = fall OR other server logic; server sets bit3 for urgent/fall
    urgent = (flags & (1 << 3)) != 0;
  }

  /// Update the AdvSummary with telemetry fields received from a streaming packet.
  /// Any parameter may be null; only non-null ones are applied.
  void updateFromTelemetry({
    int? seq,
    int? bpm,
    int? spo2,
    int? co2,
    int? batt,
    double? tempC,
    double? lat,
    double? lon,
    int? ts,
    int? rssi,
    int? flags,
    double? accX,
    double? accY,
    double? accZ,
    double? gyrX,
    double? gyrY,
    double? gyrZ,
    double? pressure,
    double? humidity,
    double? speed,
    double? altitude,
  }) {
    if (bpm != null) this.bpm = bpm;
    if (spo2 != null) this.spo2 = spo2;
    if (co2 != null) this.co2 = co2;
    if (batt != null) this.batt = batt;
    if (tempC != null) this.tempC = tempC;
    if (lat != null) this.lat = lat;
    if (lon != null) this.lon = lon;
    if (ts != null) this.ts = ts;
    if (rssi != null) this.rssi = rssi;
    if (flags != null) decodeFlags(flags);
    if (accX != null) this.accX = accX;
    if (accY != null) this.accY = accY;
    if (accZ != null) this.accZ = accZ;
    if (gyrX != null) this.gyrX = gyrX;
    if (gyrY != null) this.gyrY = gyrY;
    if (gyrZ != null) this.gyrZ = gyrZ;
    if (pressure != null) this.pressure = pressure;
    if (humidity != null) this.humidity = humidity;
    if (speed != null) this.speed = speed;
    if (altitude != null) this.altitude = altitude;
    if (seq != null) {
      streamSeq = seq;
      lastTelemetryTime = DateTime.now();
    }
    // update lastSeen as telemetry was just received
    lastSeen = DateTime.now();
  }

  /// Display helpers
  String get displayName =>
      (name != null && name!.isNotEmpty) ? name! : '<unknown>';

  String get shortName {
    if (name == null) return '<unk>';
    return name!.length > 12 ? name!.substring(0, 12) + '…' : name!;
  }

  /// Small map representation useful for debug printing or UI JSON view
  Map<String, Object?> toJson() {
    return {
      'name': name ?? '',
      'valid': valid,
      'urgent': urgent,
      'gpsValid': gpsValid,
      'flagsRaw': flagsRaw,
      'batt': batt,
      'bpm': bpm,
      'spo2': spo2,
      'co2': co2,
      'tempC': tempC,
      'lat': lat,
      'lon': lon,
      'ts': ts,
      'rssi': rssi,
      'lastSeen': lastSeen.toIso8601String(),
      'accX': accX,
      'accY': accY,
      'accZ': accZ,
      'gyrX': gyrX,
      'gyrY': gyrY,
      'gyrZ': gyrZ,
      'pressure': pressure,
      'humidity': humidity,
      'speed': speed,
      'altitude': altitude,
      'streamSeq': streamSeq,
      'lastTelemetryTime': lastTelemetryTime?.toIso8601String(),
      'freefall': freefall,
      'vibration': vibration,
      'shock': shock,
      'fall': fall,
      'tilt': tilt,
    };
  }

  /// Construct from map (useful for tests / debug)
  factory AdvSummary.fromJson(Map<String, dynamic> m) {
    final a = AdvSummary();
    try {
      a.name = (m['name'] as String?)?.isNotEmpty == true
          ? m['name'] as String?
          : a.name;
      a.valid = m['valid'] as bool? ?? a.valid;
      a.urgent = m['urgent'] as bool? ?? a.urgent;
      a.gpsValid = m['gpsValid'] as bool? ?? a.gpsValid;
      a.flagsRaw = m['flagsRaw'] as int? ?? a.flagsRaw;
      if (a.flagsRaw != 0) a.decodeFlags(a.flagsRaw);
      a.batt = m['batt'] as int? ?? a.batt;
      a.bpm = m['bpm'] as int? ?? a.bpm;
      a.spo2 = m['spo2'] as int? ?? a.spo2;
      a.co2 = m['co2'] as int? ?? a.co2;
      a.tempC = (m['tempC'] as num?)?.toDouble() ?? a.tempC;
      a.lat = (m['lat'] as num?)?.toDouble() ?? a.lat;
      a.lon = (m['lon'] as num?)?.toDouble() ?? a.lon;
      a.ts = m['ts'] as int? ?? a.ts;
      a.rssi = m['rssi'] as int? ?? a.rssi;
      a.lastSeen =
          DateTime.tryParse(m['lastSeen'] as String? ?? '') ?? a.lastSeen;
      a.accX = (m['accX'] as num?)?.toDouble() ?? a.accX;
      a.accY = (m['accY'] as num?)?.toDouble() ?? a.accY;
      a.accZ = (m['accZ'] as num?)?.toDouble() ?? a.accZ;
      a.gyrX = (m['gyrX'] as num?)?.toDouble() ?? a.gyrX;
      a.gyrY = (m['gyrY'] as num?)?.toDouble() ?? a.gyrY;
      a.gyrZ = (m['gyrZ'] as num?)?.toDouble() ?? a.gyrZ;
      a.pressure = (m['pressure'] as num?)?.toDouble() ?? a.pressure;
      a.humidity = (m['humidity'] as num?)?.toDouble() ?? a.humidity;
      a.speed = (m['speed'] as num?)?.toDouble() ?? a.speed;
      a.altitude = (m['altitude'] as num?)?.toDouble() ?? a.altitude;
      a.streamSeq = m['streamSeq'] as int? ?? a.streamSeq;
      a.lastTelemetryTime =
          DateTime.tryParse(m['lastTelemetryTime'] as String? ?? '') ??
          a.lastTelemetryTime;
      a.freefall = m['freefall'] as bool? ?? a.freefall;
      a.vibration = m['vibration'] as bool? ?? a.vibration;
      a.shock = m['shock'] as bool? ?? a.shock;
      a.fall = m['fall'] as bool? ?? a.fall;
      a.tilt = m['tilt'] as bool? ?? a.tilt;
    } catch (_) {
      // ignore malformed map
    }
    return a;
  }

  @override
  String toString() {
    return 'AdvSummary(name=$name valid=$valid urgent=$urgent gpsValid=$gpsValid flagsRaw=0x${flagsRaw.toRadixString(16)} batt=$batt bpm=$bpm spo2=$spo2 co2=$co2 tempC=$tempC lat=$lat lon=$lon ts=$ts rssi=$rssi lastSeen=$lastSeen freefall=$freefall vibration=$vibration shock=$shock fall=$fall tilt=$tilt acc=($accX,$accY,$accZ) gyr=($gyrX,$gyrY,$gyrZ) pressure=$pressure humidity=$humidity speed=$speed altitude=$altitude streamSeq=$streamSeq lastTelemetryTime=$lastTelemetryTime)';
  }
}
