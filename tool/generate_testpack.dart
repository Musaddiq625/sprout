import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

/// Generates synthetic grass/sky/floor test images.
/// Run: dart tool/generate_testpack.dart
void main() {
  final rng = Random(42);
  const size = 256;

  // grass_day.png — green-dominant with texture noise
  final grass = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      // Base green + noise texture
      final g = 100 + rng.nextInt(80);      // 100–180
      final r = 20 + rng.nextInt(40);       // 20–60
      final b = 20 + rng.nextInt(30);       // 20–50
      // Diagonal blade variation
      final blade = (sin(x * 0.3) * cos(y * 0.2)).abs() * 20;
      grass.setPixelRgb(x, y, r + blade.toInt(), g, b);
    }
  }
  File('assets/testpack/grass_day.png')
      .writeAsBytesSync(img.encodePng(grass));

  // indoor_floor.png — grey/brown, no green
  final floor = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final tone = 120 + rng.nextInt(40);   // grey-beige
      floor.setPixelRgb(x, y, tone, tone - 10, tone - 20);
    }
  }
  File('assets/testpack/indoor_floor.png')
      .writeAsBytesSync(img.encodePng(floor));

  // dark.png — very dark
  final dark = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      dark.setPixelRgb(x, y, rng.nextInt(30), rng.nextInt(30), rng.nextInt(30));
    }
  }
  File('assets/testpack/dark.png')
      .writeAsBytesSync(img.encodePng(dark));

  // ignore: avoid_print
  print('Generated 3 testpack images.');
}
