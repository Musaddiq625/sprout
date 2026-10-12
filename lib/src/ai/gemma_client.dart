import 'dart:async';

import 'package:flutter_edge_ai/flutter_edge_ai.dart';

import 'creature_tools.dart';
import 'models.dart';
import 'parse.dart';
import 'prompts.dart';

/// The creature's voice. One resident Gemma session pool answers
/// every dialogue call and the borderline grass check.
abstract class GemmaClient {
  /// The creature's name — threaded into the system prompt.
  /// 'Sprout' until the user names it.
  String creatureName = 'Sprout';

  /// First words after hatching.
  Future<String> hatchMoment();

  /// Greeting on every app open.
  Future<String> greeting({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required int minutesSinceCare,
    required String mood,
  });

  /// Groggy first words after a shake wakes the creature.
  Future<String> wakeUp();

  /// Shaken awake mid-dream — the dream shatters, forgotten.
  Future<String> startledWake();

  /// Woken gently mid-dream — recount the dream.
  Future<String> dream();

  /// Reaction to being petted.
  Future<String> petted();

  /// Shaken while fully awake — dizzy reaction.
  Future<String> dizzy();

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

  /// The creature picks its own next move — native function
  /// calling when the real model is present.
  Future<Decision> decide({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required String mood,
    required bool walking,
    required bool hasWant,
  });

  /// Generic yes/no vision check — verifies photo wishes against
  /// the prompt the creature invented.
  Future<bool> judgePhoto(String verifyPrompt, PreparedImage img);

  /// Tilted sideways while awake.
  Future<String> tilted();

  /// Noticed the human carrying it on a walk.
  Future<String> onWalk();

  /// The walk ended — logged as care.
  Future<String> afterWalk();

  /// The human fulfilled one of its wants.
  Future<String> wantFulfilled(String want);

  /// A creature-invented wish was completed.
  Future<String> wishComplete(String title);
}

/// Real implementation over flutter_edge_ai (LiteRT-LM `.litertlm`).
///
/// Each call creates a fresh session so prompts never accumulate context.
/// Generation is serialized by the engine — calls are strictly sequential.
class EdgeAiGemmaClient implements GemmaClient {
  EdgeAiGemmaClient(this._model);

  final InferenceModel _model;

  @override
  String creatureName = 'Sprout';

  Future<InferenceModelSession> _session({
    bool vision = false,
    int maxOutputTokens = 80,
  }) =>
      _model.createSession(
        temperature: 0.4,
        topK: 32,
        topP: 0.9,
        enableVisionModality: vision ? true : null,
        systemInstruction: Prompts.system(creatureName),
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
    required int minutesSinceCare,
    required String mood,
  }) =>
      _ask(
        Prompts.greeting(
          energy: energy,
          hunger: hunger,
          stage: stage,
          streak: streak,
          minutesSinceCare: minutesSinceCare,
          mood: mood,
        ),
        maxTokens: 60,
      );

  @override
  Future<String> wakeUp() => _ask(Prompts.wakeUp, maxTokens: 40);

  @override
  Future<String> startledWake() =>
      _ask(Prompts.startledWake, maxTokens: 40);

  @override
  Future<String> dream() => _ask(Prompts.dream, maxTokens: 60);

  @override
  Future<String> petted() => _ask(Prompts.petted, maxTokens: 40);

  @override
  Future<String> dizzy() => _ask(Prompts.dizzy, maxTokens: 40);

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

  @override
  Future<Decision> decide({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required String mood,
    required bool walking,
    required bool hasWant,
  }) async {
    InferenceChat? chat;
    try {
      chat = await _model.createChat(
        temperature: 0.5,
        topK: 32,
        topP: 0.9,
        supportsFunctionCalls: true,
        tools: creatureTools,
        toolChoice: ToolChoice.auto,
        systemInstruction: Prompts.system(creatureName),
        maxOutputTokens: 160,
      );
      await chat.addQueryChunk(
        Message.text(
          text: Prompts.decide(
            energy: energy,
            hunger: hunger,
            stage: stage,
            streak: streak,
            mood: mood,
            walking: walking,
            hasWant: hasWant,
          ),
          isUser: true,
        ),
      );
      return _toDecision(await chat.generateChatResponse());
    } finally {
      await chat?.close();
    }
  }

  Decision _toDecision(ModelResponse resp) {
    if (resp is ParallelFunctionCallResponse) {
      return resp.calls.isEmpty
          ? const Decision(action: CreatureAction.nothing, line: '')
          : _toDecision(resp.calls.first);
    }
    if (resp is FunctionCallResponse) {
      return Decision(
        action: actionFromName(resp.name),
        line:
            '${resp.args['line'] ?? resp.args['question'] ?? ''}',
        args: resp.args,
      );
    }
    if (resp is TextResponse) {
      return Decision(
          action: CreatureAction.nothing, line: resp.token.trim());
    }
    return const Decision(action: CreatureAction.nothing, line: '');
  }

  @override
  Future<bool> judgePhoto(
      String verifyPrompt, PreparedImage img) async {
    final raw = await _ask(
      '$verifyPrompt\nReply with only: yes or no',
      img: img,
      maxTokens: 8,
    );
    return Parse.yesNo(raw, defaultTo: false);
  }

  @override
  Future<String> tilted() => _ask(Prompts.tilted, maxTokens: 40);

  @override
  Future<String> onWalk() => _ask(Prompts.onWalk, maxTokens: 40);

  @override
  Future<String> afterWalk() =>
      _ask(Prompts.afterWalk, maxTokens: 40);

  @override
  Future<String> wantFulfilled(String want) =>
      _ask(Prompts.wantFulfilled(want), maxTokens: 40);

  @override
  Future<String> wishComplete(String title) =>
      _ask(Prompts.wishComplete(title), maxTokens: 50);
}

/// Deterministic fake: no model needed.
/// Keeps the app fully playable before/without the 2.4 GB download.
class FakeGemmaClient implements GemmaClient {
  FakeGemmaClient();

  @override
  String creatureName = 'Sprout';

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

  static const _wakeLines = [
    'Hm? …oh. It\'s you.',
    'I was dreaming about rain.',
    'Five more minutes…',
    'Still here. Good.',
  ];

  static const _startledLines = [
    'Whoa— easy! …I lost the dream.',
    'Ah! …it was right there. Gone now.',
    'Careful! The dream scattered.',
  ];

  static const _dreamLines = [
    'I dreamed of a rain that never ended.',
    'I was a whole forest for a moment.',
    'There was a sun inside the sun.',
  ];

  static const _pettedLines = [
    'Mmm. Again.',
    'Right there. Yes.',
    '*happy rustling*',
  ];

  static const _dizzyLines = [
    'Whoa— the room is spinning.',
    'Easy! My leaves are rattled.',
    'The ground moved. Or I did.',
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
    required int minutesSinceCare,
    required String mood,
  }) async =>
      _pick(_greetingLines);

  @override
  Future<String> wakeUp() async => _pick(_wakeLines);

  @override
  Future<String> startledWake() async => _pick(_startledLines);

  @override
  Future<String> dream() async => _pick(_dreamLines);

  @override
  Future<String> petted() async => _pick(_pettedLines);

  @override
  Future<String> dizzy() async => _pick(_dizzyLines);

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

  static const _tiltedLines = [
    'Whoa— the floor moved.',
    'Everything is sideways.',
    'Careful with the horizon!',
  ];

  static const _walkLines = [
    'Are we going to the park?',
    'The world is moving past!',
    'I love being carried outside.',
  ];

  /// Deterministic stand-in for the real tool-call decision:
  /// state-driven wants first, small variety otherwise.
  @override
  Future<Decision> decide({
    required double energy,
    required double hunger,
    required String stage,
    required int streak,
    required String mood,
    required bool walking,
    required bool hasWant,
  }) async {
    if (!hasWant) {
      if (energy < 45) {
        return const Decision(
          action: CreatureAction.demandSunlight,
          line: 'I keep thinking about the sun…',
        );
      }
      if (hunger < 45) {
        return const Decision(
          action: CreatureAction.requestGrass,
          line: 'A snack of grass would be lovely.',
        );
      }
    }
    final pick = _i++ % 5;
    return switch (pick) {
      0 => const Decision(
          action: CreatureAction.requestWalk,
          line: 'Could we go for a little walk?'),
      1 => const Decision(
          action: CreatureAction.sing,
          line: '♪ doo-doo, sun on leaves ♪'),
      2 => const Decision(
          action: CreatureAction.ask,
          line: 'Is the sky really that big?'),
      _ => const Decision(
          action: CreatureAction.nothing,
          line: 'Just thinking.'),
    };
  }

  @override
  Future<bool> judgePhoto(
          String verifyPrompt, PreparedImage img) async =>
      true;

  @override
  Future<String> tilted() async => _pick(_tiltedLines);

  @override
  Future<String> onWalk() async => _pick(_walkLines);

  @override
  Future<String> afterWalk() async =>
      'That was a good walk. My leaves are tired.';

  @override
  Future<String> wantFulfilled(String want) async =>
      'Yes! Exactly what I was hoping for.';

  @override
  Future<String> wishComplete(String title) async =>
      'You did it! My little wish came true.';
}
