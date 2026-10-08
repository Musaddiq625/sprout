import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../ai/ai_service.dart';
import '../ai/models.dart';
import '../creature/creature_controller.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import '../vision/grass_gate.dart';
import '../vision/image_prep.dart';
import 'widgets/camera_capture_page.dart';
import 'widgets/photo_source_sheet.dart';

/// Grass feed flow: photo → GrassGate → feed → creature reacts.
/// Borderline photos go to Gemma vision; the result lands here.
class GrassPage extends StatefulWidget {
  const GrassPage({
    super.key,
    required this.controller,
    required this.store,
  });

  final CreatureController controller;
  final CreatureStore store;

  @override
  State<GrassPage> createState() => _GrassPageState();
}

class _GrassPageState extends State<GrassPage> {
  Uint8List? _photoBytes;
  img.Image? _photo;
  GrassVerdict? _verdict;
  bool _checking = false;
  bool _fed = false;

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<PhotoSource>(
      context: context,
      builder: (_) => const PhotoSourceSheet(),
    );
    if (source == null || !mounted) return;

    Uint8List? bytes;
    if (source == PhotoSource.camera) {
      bytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => const CameraCapturePage()),
      );
    } else if (source == PhotoSource.gallery) {
      bytes = await _pickFromGallery();
    } else {
      // testpack — skip gate for demo/dev
      bytes = await _loadTestPack();
    }

    if (bytes == null || !mounted) return;
    final prepared = ImagePrep.prepare(bytes);
    if (prepared == null) {
      if (mounted) _showError('Could not read that photo.');
      return;
    }

    final decoded = img.decodeImage(prepared.bytes);
    if (decoded == null) {
      if (mounted) _showError('Could not decode that photo.');
      return;
    }

    final verdict = GrassGate.evaluate(decoded);
    setState(() {
      _photoBytes = prepared.bytes;
      _photo = decoded;
      _verdict = verdict;
    });
  }

  Future<Uint8List?> _pickFromGallery() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
      );
      return file != null ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _loadTestPack() async {
    try {
      final data =
          await DefaultAssetBundle.of(context).load('assets/testpack/grass_day.png');
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _feed() async {
    if (_photoBytes == null || _fed) return;
    setState(() => _fed = true);

    if (_verdict == GrassVerdict.pass) {
      final ratio = GrassGate.grassRatio(_photo!);
      await widget.controller.feedGrass(_photoBytes!, ratio);
      if (mounted) Navigator.pop(context);
    } else if (_verdict == GrassVerdict.borderline) {
      setState(() => _checking = true);
      final prepared = PreparedImage(
        bytes: _photoBytes!,
        width: _photo!.width,
        height: _photo!.height,
      );
      try {
        final isGrass = await AiService.instance.gemma.grassCheck(prepared);
        if (!mounted) return;
        if (isGrass) {
          final ratio = GrassGate.grassRatio(_photo!);
          await widget.controller.feedGrass(_photoBytes!, ratio);
          if (mounted) Navigator.pop(context);
        } else {
          await widget.controller.grassRejected();
          if (!mounted) return;
          setState(() {
            _checking = false;
            _fed = false;
            _verdict = GrassVerdict.fail;
          });
        }
      } catch (_) {
        // Model unavailable — treat borderline as pass (generous).
        if (!mounted) return;
        final ratio = GrassGate.grassRatio(_photo!);
        await widget.controller.feedGrass(_photoBytes!, ratio);
        if (mounted) Navigator.pop(context);
      }
    } else {
      // fail
      await widget.controller.grassRejected();
      if (mounted) Navigator.pop(context);
    }
  }

  void _retry() {
    setState(() {
      _photoBytes = null;
      _photo = null;
      _verdict = null;
      _checking = false;
      _fed = false;
    });
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(key: KeyConstants.grassBackButton),
        title: const Text('Feed Grass'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Photo preview or picker prompt
              Expanded(
                child: _photoBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _photoBytes!,
                          key: KeyConstants.grassPhotoPreview,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('🌿',
                                style: TextStyle(fontSize: 64)),
                            const SizedBox(height: 16),
                            Text(
                              'Show Sprout a patch of grass.',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              key: KeyConstants.cameraButton,
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Take Photo'),
                              onPressed: _pickPhoto,
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              key: KeyConstants.testPackButton,
                              icon: const Icon(Icons.eco),
                              label: const Text('Use test image'),
                              onPressed: _pickPhoto,
                            ),
                          ],
                        ),
                      ),
              ),

              // Gate result banner
              if (_verdict != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _verdictColor().withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _verdictColor().withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    _verdictText(),
                    key: KeyConstants.grassGateResult,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _verdictColor()),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Actions
              if (_photoBytes != null) ...[
                if (_checking)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Asking Sprout…'),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          key: KeyConstants.feedGrassConfirm,
                          icon: const Text('🌿'),
                          label: const Text('Feed it'),
                          onPressed: _fed ? null : _feed,
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        key: KeyConstants.grassRetryButton,
                        icon: const Icon(Icons.refresh),
                        onPressed: _retry,
                      ),
                    ],
                  ),
              ] else
                const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Color _verdictColor() => switch (_verdict) {
        GrassVerdict.pass => Colors.greenAccent,
        GrassVerdict.borderline => Colors.amber,
        _ => Colors.redAccent,
      };

  String _verdictText() => switch (_verdict) {
        GrassVerdict.pass => '✓ Looks like grass!',
        GrassVerdict.borderline =>
          'Borderline — Sprout will decide.',
        _ => 'That\'s not grass. Try again outside.',
      };
}
