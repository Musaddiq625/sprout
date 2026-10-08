import 'dart:async';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'models.dart';
import 'parse.dart';
import 'prompts.dart';

/// The creature's voice. One resident Gemma session pool answers
/// every dialogue call and the borderline grass check.
abstract class GemmaClient {
  /// First words after hatching.
  Future<String> hatchMoment();

  /// Greeting on every app open.
  Future<String> greeting({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required int hoursSinceCare,
  });

  /// After a sunlight feed.
  Future<String> afterSunlight({required double energy});

  /// After a successful grass feed.
  Future<String> afterGrassPass({required double hunger});

  /// After the grass gate rejects a photo.
  Future<String> afterGrassFail();

  /// When the same photo is re-submitted.
  Future<String> duplicatePhoto();

  /// Story moment when a quest unlocks.
  Future<String> questComplete({
    required String title,
    required String storyUnlock,
  });

  /// Borderline grass check — yes/no vision call.
  Future<bool> grassCheck(PreparedImage img);
}

/// Real implementation over flutter_edge_ai (LiteRT-LM `.litertlm`).
///
/// Each call creates a fresh session so prompts never accumulate context.
/// Generation is serialized by the engine — calls are strictly sequential.
class EdgeAiGemmaClient implements GemmaClient {
  EdgeAiGemmaClient(this._model);

  final InferenceModel _model;

  Future<InferenceModelSession> _session({
    bool vision = false,
    int maxOutputTokens = 80,
  }) =>
      _model.createSession(
        temperature: 0.4,
        topK: 32,
        topP: 0.9,
        enableVisionModality: vision ? true : null,
        systemInstruction: Prompts.system,
        maxOutputTokens: maxOutputTokens,
      );

  Future<String> _ask(String prompt,
      {PreparedImage? img, int maxTokens = 80}) async {
    final session =
        await _session(vision: img != null, maxOutputTokens: maxTokens);
    try {
      await session.addQueryChunk(
        img == null
            ? Message.text(text: prompt, isUser: true)
            : Message.withImage(
                text: prompt, imageBytes: img.bytes, isUser: true),
      );
      return (await session.getResponse()).trim();
    } finally {
      await session.close();
    }
  }

  @override
  Future<String> hatchMoment() =>
      _ask(Prompts.hatchMoment, maxTokens: 60);

  @override
  Future<String> greeting({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required int hoursSinceCare,
  }) =>
      _ask(
        Prompts.greeting(
          energy: energy,
          hunger: hunger,
          stage: stage,
          streak: streak,
          hoursSinceCare: hoursSinceCare,
        ),
        maxTokens: 60,
      );

  @override
  Future<String> afterSunlight({required double energy}) =>
      _ask(Prompts.afterSunlight(energy: energy), maxTokens: 40);

  @override
  Future<String> afterGrassPass({required double hunger}) =>
      _ask(Prompts.afterGrassPass(hunger: hunger), maxTokens: 40);

  @override
  Future<String> afterGrassFail() =>
      _ask(Prompts.afterGrassFail, maxTokens: 40);

  @override
  Future<String> duplicatePhoto() =>
      _ask(Prompts.duplicatePhoto, maxTokens: 40);

  @override
  Future<String> questComplete({
    required String title,
    required String storyUnlock,
  }) =>
      _ask(
        Prompts.questComplete(title: title, storyUnlock: storyUnlock),
        maxTokens: 60,
      );

  @override
  Future<bool> grassCheck(PreparedImage img) async {
    final raw = await _ask(Prompts.grassCheck, img: img, maxTokens: 8);
    return Parse.yesNo(raw, defaultTo: true);
  }
}

/// Deterministic fake: no model needed.
/// Keeps the app fully playable before/without the 2.4 GB download.
class FakeGemmaClient implements GemmaClient {
  FakeGemmaClient();

  static const _hatchLines = [
    'Where am I? Something just changed.',
    'I can feel warmth. Is that the sun?',
    'Everything is new. I think I like it here.',
  ];

  static const _greetingLines = [
    'Good morning.',
    'I was just thinking about grass.',
    'The light feels thin today.',
    'You came back.',
  ];

  static const _sunlightLines = [
    'That was good.',
    'More please.',
    'I can feel my leaves.',
  ];

  static const _grassPassLines = [
    'Acceptable.',
    'Could use more dew.',
    'The earth remembers.',
  ];

  static const _grassFailLines = [
    'That is not grass.',
    'I don\'t recognize this.',
    'Wrong.',
  ];

  static const _duplicateLines = [
    'I remember that patch.',
    'The same grass twice. Efficient.',
  ];

  static var _i = 0;
  static String _pick(List<String> lines) =>
      lines[(_i++) % lines.length];

  @override
  Future<String> hatchMoment() async => _pick(_hatchLines);

  @override
  Future<String> greeting({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required int hoursSinceCare,
  }) async =>
      _pick(_greetingLines);

  @override
  Future<String> afterSunlight({required double energy}) async =>
      _pick(_sunlightLines);

  @override
  Future<String> afterGrassPass({required double hunger}) async =>
      _pick(_grassPassLines);

  @override
  Future<String> afterGrassFail() async => _pick(_grassFailLines);

  @override
  Future<String> duplicatePhoto() async => _pick(_duplicateLines);

  @override
  Future<String> questComplete({
    required String title,
    required String storyUnlock,
  }) async =>
      'A new milestone: $title.';

  @override
  Future<bool> grassCheck(PreparedImage img) async => true;
}
