import 'package:flutter/foundation.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'gemma_client.dart';

/// Holds whichever AI client the device can currently provide.
/// Real Gemma when installed, deterministic fake otherwise —
/// the app is fully playable before/without the 2.4 GB download.
class AiService extends ChangeNotifier {
  AiService._();

  static final AiService instance = AiService._();

  /// --dart-define USE_FAKE_AI=true forces fakes even with models installed.
  static const _forceFake =
      bool.fromEnvironment('USE_FAKE_AI', defaultValue: false);

  GemmaClient gemma = FakeGemmaClient();

  /// 'real' | 'fake'
  String mode = 'fake';

  /// Rebuilds the client from whatever flutter_edge_ai reports installed.
  /// Called at boot and after any model install/import.
  Future<void> refresh() async {
    if (_forceFake) {
      mode = 'fake';
      notifyListeners();
      return;
    }
    try {
      gemma = FlutterEdgeAi.hasActiveModel()
          ? EdgeAiGemmaClient(
              await FlutterEdgeAi.getActiveModel(
                preferredBackend: PreferredBackend.gpu,
                supportImage: true,
              ),
            )
          : FakeGemmaClient();
    } catch (_) {
      gemma = FakeGemmaClient();
    }
    mode = gemma is EdgeAiGemmaClient ? 'real' : 'fake';
    notifyListeners();
  }
}
