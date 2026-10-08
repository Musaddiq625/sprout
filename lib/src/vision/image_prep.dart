import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../ai/models.dart';

/// Decode → EXIF bake → resize → JPEG bytes for the model.
///
/// EXIF matters: camera JPEGs are stored rotated; a sideways photo gives
/// the model garbage. bakeOrientation writes the rotation into pixels
/// before anything else touches the image.
class ImagePrep {
  ImagePrep._();

  /// Long edge cap for model input.
  static const int maxEdge = 768;

  static PreparedImage? prepare(Uint8List rawBytes) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(rawBytes);
    } catch (_) {
      return null; // corrupt file — fail the call, not the app
    }
    if (decoded == null) return null;
    decoded = img.bakeOrientation(decoded);
    if (decoded.width > maxEdge || decoded.height > maxEdge) {
      decoded = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? maxEdge : null,
        height: decoded.height > decoded.width ? maxEdge : null,
        interpolation: img.Interpolation.average,
      );
    }
    return PreparedImage(
      bytes: Uint8List.fromList(img.encodeJpg(decoded, quality: 85)),
      width: decoded.width,
      height: decoded.height,
    );
  }
}
