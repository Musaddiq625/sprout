import 'dart:async';

import 'package:flutter/services.dart';

/// Wraps the Android TYPE_LIGHT ambient light sensor via a local
/// MethodChannel/EventChannel — no third-party plugin needed.
///
/// Typical readings:
///   indoor lamp     ~200–800 lux
///   overcast outdoor ~1,000–5,000 lux
///   direct sun      ~30,000–100,000 lux
class LuxService {
  LuxService._();

  static const _methodChannel =
      MethodChannel('com.sprout.musaddiq625/lux');
  static const _eventChannel =
      EventChannel('com.sprout.musaddiq625/lux_stream');

  /// Minimum lux to count as outdoor sunlight.
  static const outdoorLux = 2000;

  /// How long the reading must stay at/above threshold to feed.
  static const holdDuration = Duration(seconds: 5);

  /// True if the device reports a working light sensor.
  static Future<bool> hasSensor() async {
    try {
      final result =
          await _methodChannel.invokeMethod<bool>('hasSensor');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Stream of lux readings as doubles.
  /// Emits an error event if no sensor is present.
  static Stream<double> get stream =>
      _eventChannel.receiveBroadcastStream().map((e) => (e as num).toDouble());

  /// True when [lux] is clearly outdoor-level brightness.
  static bool isOutdoor(double lux) => lux >= outdoorLux;
}
