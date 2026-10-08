import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

/// Model inventory + download orchestration.
///
/// The app runs fake dialogue until the Gemma model is installed —
/// the download flow is a first-run screen, not a gate.
///
/// Source: Hugging Face litert-community mirror, ungated.
/// ~2.4 GB, vision-capable, ModelType.gemma4.
class ModelManager extends ChangeNotifier {
  ModelManager();

  static const gemmaUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
      'resolve/b3ca0d2f076785a8f4b2219ddbd2bdb99954eae1/'
      'gemma-4-E2B-it.litertlm';

  ModelStatus gemma = const ModelStatus('Gemma 4 E2B', 2588147712);

  CancelToken? _cancel;

  bool get gemmaReady => gemma.state == ModelState.ready;
  bool get isDownloading => gemma.state == ModelState.downloading;

  Future<void> refresh() async {
    // Never clobber an in-flight or error state — re-entering the page
    // mid-download must still show progress.
    if (gemma.state == ModelState.downloading ||
        gemma.state == ModelState.error) {
      return;
    }
    final installed = FlutterEdgeAi.hasActiveModel();
    gemma = gemma.copyWith(
        state: installed ? ModelState.ready : ModelState.missing);
    notifyListeners();
  }

  /// Downloads the Gemma model. foreground:true keeps Android's
  /// 9-minute background limit from killing a 2.4 GB pull.
  Future<void> downloadGemma({String? token}) async {
    if (gemma.state == ModelState.downloading) return;
    _set(gemma: gemma.copyWith(state: ModelState.downloading, progress: 0));
    _cancel = CancelToken();
    try {
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      )
          .fromNetwork(gemmaUrl, token: token, foreground: true)
          .withCancelToken(_cancel!)
          .withProgress((p) =>
              _set(gemma: gemma.copyWith(progress: p / 100)))
          .install();
      _set(gemma: gemma.copyWith(state: ModelState.ready, progress: 1));
    } catch (e) {
      _set(gemma: gemma.copyWith(
        state: CancelToken.isCancel(e) ? ModelState.missing : ModelState.error,
        error: '$e',
      ));
      rethrow;
    }
  }

  /// Manual import for gated repos: user places the .litertlm on the
  /// device and picks it. file_picker supplies the path.
  Future<void> importGemma(String filePath) async {
    _set(gemma: gemma.copyWith(state: ModelState.downloading, progress: -1));
    try {
      await FlutterEdgeAi.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(filePath).install();
      _set(gemma: gemma.copyWith(state: ModelState.ready, progress: 1));
    } catch (e) {
      _set(gemma: gemma.copyWith(state: ModelState.error, error: '$e'));
      rethrow;
    }
  }

  void cancelDownload() => _cancel?.cancel('User cancelled');

  void _set({ModelStatus? gemma}) {
    if (gemma != null) this.gemma = gemma;
    notifyListeners();
  }
}

enum ModelState { missing, downloading, ready, error }

class ModelStatus {
  const ModelStatus(this.label, this.expectedBytes,
      {this.state = ModelState.missing,
      this.progress = 0,
      this.error});

  final String label;
  final int expectedBytes;
  final ModelState state;

  /// 0..1; -1 = indeterminate (file import).
  final double progress;
  final String? error;

  ModelStatus copyWith({
    String? label,
    ModelState? state,
    double? progress,
    String? error,
  }) =>
      ModelStatus(
        label ?? this.label,
        expectedBytes,
        state: state ?? this.state,
        progress: progress ?? this.progress,
        error: error ?? this.error,
      );
}
