import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'src/ai/ai_service.dart';
import 'src/ai/model_manager.dart';
import 'src/creature/creature_store.dart';
import 'src/creature/creature_controller.dart';
import 'src/ui/home_page.dart';
import 'src/ui/hatch_page.dart';

/// Gated HF repos accept a token:
///   flutter run --dart-define HUGGINGFACE_TOKEN=hf_...
/// Gemma 4 E2B is ungated and downloads without one.
const _hfToken = String.fromEnvironment('HUGGINGFACE_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await FlutterEdgeAi.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
    huggingFaceToken: _hfToken.isEmpty ? null : _hfToken,
    maxDownloadRetries: 8,
  );

  final store = await CreatureStore.open();
  final creature = await store.loadCreature();
  final models = ModelManager()..refresh();
  await AiService.instance.refresh();

  final controller = CreatureController(store: store);
  await controller.applyDecay();

  final needsHatch = creature.stage.index == 0;

  runApp(SproutApp(
    creature: creature,
    store: store,
    models: models,
    controller: controller,
    needsHatch: needsHatch,
  ));
}

class SproutApp extends StatelessWidget {
  const SproutApp({
    super.key,
    required this.creature,
    required this.store,
    required this.models,
    required this.controller,
    required this.needsHatch,
  });

  final dynamic creature;
  final CreatureStore store;
  final ModelManager models;
  final CreatureController controller;
  final bool needsHatch;

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4CAF50),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Sprout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      home: needsHatch
          ? HatchPage(store: store, controller: controller, models: models)
          : HomePage(store: store, models: models, controller: controller),
    );
  }
}
