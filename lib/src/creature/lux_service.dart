import 'dart:async';
import 'dart:math' as math;

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

  /// Minimum lux to count as a real sun-feed. Deliberately far
  /// above indoor bulbs (~100–500 lux) and bright windows
  /// (~1–3k) — only genuinely outdoor-class light counts.
  static const soakLux = 5000;

  /// Kept for backward references — same as [soakLux].
  static const outdoorLux = soakLux;

  /// Sustained soak time that banks one sun-feed ("a drink").
  static const holdDuration = Duration(seconds: 3);

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

  /// True when [lux] is clearly outdoor-level brightness —
  /// i.e. bright enough for the creature to feed on.
  static bool isOutdoor(double lux) => lux >= soakLux;

  /// Log-normalized brightness 0..1 for the sun-rays UI.
  /// Lux is log-distributed, so a linear map would saturate —
  /// ~200 lux (dim room) → 0, ~30k (direct sun) → 1.
  static double intensity(double lux) {
    const lo = 200.0, hi = 30000.0;
    final l = lux.clamp(lo, hi);
    return ((math.log(l) - math.log(lo)) /
            (math.log(hi) - math.log(lo)))
        .clamp(0.0, 1.0);
  }
}
