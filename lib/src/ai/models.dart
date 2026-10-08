import 'dart:typed_data';

/// A photo decoded, EXIF-orientation applied, downscaled for model input.
class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// JPEG bytes, orientation already baked in.
  final Uint8List bytes;
  final int width;
  final int height;
}
