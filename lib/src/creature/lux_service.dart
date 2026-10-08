import 'dart:async';

import 'package:light_sensor/light_sensor.dart';

/// Wraps the Android ambient light sensor (TYPE_LIGHT) — lux units.
///
/// No permission required. On devices without a sensor, `hasSensor`
/// returns false and the stream emits nothing.
///
/// Typical readings:
///   indoor lamp     ~200–800 lux
///   overcast outdoor ~1,000–5,000 lux
///   direct sun      ~30,000–100,000 lux
class LuxService {
  LuxService._();

  /// Minimum lux to count as outdoor sunlight.
  /// Above typical indoor lighting, below guaranteed sunshine —
  /// most overcast days still pass this threshold.
  static const outdoorLux = 2000;

  /// How long the reading must stay at/above threshold to feed.
  static const holdDuration = Duration(seconds: 5);

  /// Returns true if the device reports a working light sensor.
  static Future<bool> hasSensor() =>
      LightSensor.hasSensor().catchError((_) => false);

  /// Raw stream of lux readings (integers from the sensor).
  /// Emits nothing on devices with no sensor.
  static Stream<double> get stream {
    try {
      return LightSensor.luxStream().map((l) => l.toDouble());
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// True when [lux] is clearly outdoor-level brightness.
  static bool isOutdoor(double lux) => lux >= outdoorLux;
}
