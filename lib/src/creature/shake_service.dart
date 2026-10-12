import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Wraps the Android TYPE_ACCELEROMETER sensor via a local
/// EventChannel — no third-party plugin needed, same pattern as
/// LuxService. Emits an error event on platforms without the
/// channel (e.g. iOS) — callers should ignore it.
///
/// [vectors] is a shared broadcast so shakes and tilts ride one
/// native subscription (a second EventChannel listener would
/// replace the native-side listener reference and leak the first).
class ShakeService {
  ShakeService._();

  static const _eventChannel =
      EventChannel('com.sprout.musaddiq625/accel_stream');

  /// g-force (xyz magnitude / 9.81) above which a reading counts
  /// as a shake. A deliberate shake peaks around 2–4g.
  static const shakeGForce = 2.5;

  /// Minimum gap between emitted shakes — one physical shake is a
  /// burst of many over-threshold readings.
  static const cooldown = Duration(milliseconds: 900);

  static Stream<List<double>>? _vectorStream;

  /// Raw accelerometer vectors [x, y, z] m/s² as a shared
  /// broadcast — derived streams subscribe to this, not the
  /// channel.
  static Stream<List<double>> get vectors => _vectorStream ??=
      _eventChannel.receiveBroadcastStream().map((e) {
        if (e is! List || e.length < 3) {
          return const <double>[0, 0, 0];
        }
        return <double>[
          (e[0] as num).toDouble(),
          (e[1] as num).toDouble(),
          (e[2] as num).toDouble(),
        ];
      }).asBroadcastStream();

  /// Stream that emits the peak g-force of each detected shake,
  /// throttled by [cooldown].
  static Stream<double> get shakes {
    DateTime? last;
    return vectors.where((v) {
      final g =
          math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) / 9.81;
      if (g < shakeGForce) return false;
      final now = DateTime.now();
      if (last != null && now.difference(last!) < cooldown) {
        return false;
      }
      last = now;
      return true;
    }).map((v) =>
        math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) / 9.81);
  }
}
