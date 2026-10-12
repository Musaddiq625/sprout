import 'shake_service.dart';

/// Device lean derived from the shared accelerometer broadcast.
/// Emits a low-pass-filtered lateral lean value: -1.0 (full left
/// tilt) .. 1.0 (full right tilt), ~10 Hz, only on real change.
class TiltService {
  TiltService._();

  /// Emit at most this often — GAME-delay accel runs ~50 Hz.
  static const _minGap = Duration(milliseconds: 100);

  /// Ignore jitter below this lean delta.
  static const _deadband = 0.03;

  /// Stream of lateral lean (-1..1). Gravity on x means the phone
  /// is rolled sideways; a held-flat phone reads ~±1.
  static Stream<double> get lean {
    double? gx;
    double? last;
    DateTime? lastTs;
    return ShakeService.vectors.where((v) {
      final now = DateTime.now();
      if (lastTs != null && now.difference(lastTs!) < _minGap) {
        return false;
      }
      lastTs = now;
      // Low-pass filter pulls gravity out of the noisy vector.
      gx = gx == null ? v[0] : gx! + (v[0] - gx!) * 0.25;
      final lean = (gx! / 9.81).clamp(-1.0, 1.0);
      if (last != null && (lean - last!).abs() < _deadband) {
        return false;
      }
      last = lean;
      return true;
    }).map((_) => last!);
  }
}
