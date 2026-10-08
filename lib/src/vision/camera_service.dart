import 'dart:typed_data';

import 'package:camera/camera.dart';

/// Camera lifecycle for grass feeding.
/// Initializes on demand, returns a live controller, disposes cleanly.
class CameraService {
  CameraService._();

  static CameraController? _controller;

  /// Returns a ready controller, or null if no camera / permission denied.
  static Future<CameraController?> getController() async {
    if (_controller != null && _controller!.value.isInitialized) {
      return _controller;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return null;
      _controller = CameraController(
        cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      return _controller;
    } catch (_) {
      _controller = null;
      return null;
    }
  }

  /// Captures the current frame as JPEG bytes.
  static Future<Uint8List?> capture(CameraController ctrl) async {
    try {
      final file = await ctrl.takePicture();
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
