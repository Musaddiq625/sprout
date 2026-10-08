import 'package:image/image.dart' as img;

/// Stage-1 grass gate: pure image statistics, ~0ms, no ML.
///
/// pass      — clearly grass/green plants, feed directly
/// borderline — grey zone, hand to Gemma vision for one yes/no
/// fail      — confidently not grass; creature reacts with confusion
enum GrassVerdict { pass, borderline, fail }

class GrassGate {
  GrassGate._();

  /// Tunable after corpus calibration.
  static const double passAt = 0.40;
  static const double failBelow = 0.20;
  static const int _sampleSize = 64;

  static GrassVerdict evaluate(img.Image photo) {
    final ratio = grassRatio(photo);
    if (ratio >= passAt) return GrassVerdict.pass;
    if (ratio >= failBelow) return GrassVerdict.borderline;
    return GrassVerdict.fail;
  }

  /// Fraction of pixels classified as grass/green plant material.
  static double grassRatio(img.Image photo) {
    final small =
        img.copyResize(photo, width: _sampleSize, height: _sampleSize);
    var green = 0;
    for (final pixel in small) {
      if (isGrassPixel(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt())) {
        green++;
      }
    }
    return green / (_sampleSize * _sampleSize);
  }

  /// Grass/plant greens: H 60–160°, enough saturation to rule out grey
  /// pavement, enough brightness to rule out deep shadow.
  /// Intentionally broad — the creature eats greens, not just lawn.
  static bool isGrassPixel(int r, int g, int b) {
    final hsv = _toHsv(r, g, b);
    final h = hsv[0], s = hsv[1], v = hsv[2];
    return h >= 60 && h <= 160 && s > 0.25 && v > 0.20;
  }

  /// Returns [hue 0..360, saturation 0..1, value 0..1].
  static List<double> _toHsv(int r, int g, int b) {
    final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
    final max = [rf, gf, bf].reduce((a, c) => a > c ? a : c);
    final min = [rf, gf, bf].reduce((a, c) => a < c ? a : c);
    final d = max - min;
    double h = 0;
    if (d > 0) {
      if (max == rf) {
        h = 60 * (((gf - bf) / d) % 6);
      } else if (max == gf) {
        h = 60 * ((bf - rf) / d + 2);
      } else {
        h = 60 * ((rf - gf) / d + 4);
      }
    }
    if (h < 0) h += 360;
    return [h, max == 0 ? 0 : d / max, max];
  }
}
