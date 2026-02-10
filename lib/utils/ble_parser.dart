import 'dart:convert';

/// Result of parsing BLE characteristic data.
sealed class BleParseResult {}

class ImuData extends BleParseResult {
  final double x, y, z, vib, ppv, rms, freq, crest, cent, kurt, stalta;

  ImuData({
    required this.x,
    required this.y,
    required this.z,
    required this.vib,
    this.ppv = 0,
    this.rms = 0,
    this.freq = 0,
    this.crest = 0,
    this.cent = 0,
    this.kurt = 0,
    this.stalta = 0,
  });
}

class MoistureData extends BleParseResult {
  final int percent;
  final int raw;
  final double? vib;

  MoistureData({required this.percent, required this.raw, this.vib});
}

class AlertBleData extends BleParseResult {
  final String level;
  final String message;
  final String type;

  AlertBleData({required this.level, required this.message, required this.type});
}

class BleParseError extends BleParseResult {
  final String reason;
  BleParseError(this.reason);
}

/// Clean raw BLE bytes: strip null bytes and trim whitespace.
String cleanBleBytes(List<int> raw) {
  final cleaned = raw.where((b) => b != 0).toList();
  return String.fromCharCodes(cleaned).trim();
}

/// Parse a cleaned JSON string from BLE into the appropriate data type.
/// [charUuid] is used to determine which characteristic sent the data.
BleParseResult parseBleJson(String jsonStr, String charUuid) {
  if (jsonStr.isEmpty) return BleParseError('empty');

  // Check for truncated JSON
  if (!jsonStr.endsWith('}')) {
    return BleParseError('truncated');
  }

  final dynamic data;
  try {
    data = json.decode(jsonStr);
  } catch (e) {
    return BleParseError('invalid_json: $e');
  }
  if (data == null) return BleParseError('null_data');

  // IMU: UUID ends with 26a8
  if (charUuid.endsWith('26a8') || charUuid.contains('b26a8')) {
    return ImuData(
      x: (data['x'] as num?)?.toDouble() ?? 0.0,
      y: (data['y'] as num?)?.toDouble() ?? 0.0,
      z: (data['z'] as num?)?.toDouble() ?? 0.0,
      vib: (data['vib'] as num?)?.toDouble() ?? 0.0,
      ppv: (data['ppv'] as num?)?.toDouble() ?? 0.0,
      rms: (data['rms'] as num?)?.toDouble() ?? 0.0,
      freq: (data['freq'] as num?)?.toDouble() ?? 0.0,
      crest: (data['crest'] as num?)?.toDouble() ?? 0.0,
      cent: (data['cent'] as num?)?.toDouble() ?? 0.0,
      kurt: (data['kurt'] as num?)?.toDouble() ?? 0.0,
      stalta: (data['stalta'] as num?)?.toDouble() ?? 0.0,
    );
  }

  // Moisture: UUID ends with 26a9
  if (charUuid.endsWith('26a9') || charUuid.contains('b26a9')) {
    return MoistureData(
      percent: (data['percent'] as num?)?.toInt() ?? 0,
      raw: (data['raw'] as num?)?.toInt() ?? 0,
      vib: (data['vib'] as num?)?.toDouble(),
    );
  }

  // Alert: UUID ends with 26aa
  if (charUuid.endsWith('26aa') || charUuid.contains('b26aa')) {
    return AlertBleData(
      level: data['level'] as String? ?? 'safe',
      message: data['message'] as String? ?? '',
      type: data['type'] as String? ?? 'none',
    );
  }

  return BleParseError('unknown_uuid: $charUuid');
}
