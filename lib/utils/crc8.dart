int crc8Maxim(List<int> data, int length) {
  var crc = 0;
  for (var i = 0; i < length; i++) {
    var inb = data[i] & 0xFF;
    crc ^= inb;
    for (var j = 0; j < 8; j++) {
      if ((crc & 0x01) != 0) {
        crc = ((crc >> 1) ^ 0x8C) & 0xFF;
      } else {
        crc = (crc >> 1) & 0xFF;
      }
    }
  }
  return crc & 0xFF;
}
