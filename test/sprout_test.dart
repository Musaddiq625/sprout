import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:sprout/src/ai/creature_tools.dart';
import 'package:sprout/src/ai/gemma_client.dart';
import 'package:sprout/src/ai/parse.dart';
import 'package:sprout/src/creature/creature_state.dart';
import 'package:sprout/src/creature/creature_store.dart';
import 'package:sprout/src/creature/creature_controller.dart';
import 'package:sprout/src/ui/creature_widget.dart';
import 'package:sprout/src/vision/grass_gate.dart';
import 'package:sprout/src/vision/image_prep.dart';

// ── Path provider mock for tests ─────────────────────────────────────────────

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Silent EventChannel handler — sensor streams (accel/steps) have no
/// platform side in tests; without this the listen call throws
/// MissingPluginException and fails the test.
class _SilentStreamHandler extends MockStreamHandler {
  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {}

  @override
  void onCancel(Object? arguments) {}
}

void _mockSensorChannels(TestWidgetsFlutterBinding binding) {
  for (final name in const [
    'com.sprout.musaddiq625/accel_stream',
    'com.sprout.musaddiq625/step_stream',
  ]) {
    binding.defaultBinaryMessenger
        .setMockStreamHandler(EventChannel(name), _SilentStreamHandler());
  }
}

img.Image _solidColor(int r, int g, int b) {
  final im = img.Image(width: 64, height: 64);
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      im.setPixelRgb(x, y, r, g, b);
    }
  }
  return im;
}

img.Image _grassImage() {
  final im = img.Image(width: 64, height: 64);
  final rng = DateTime.now().millisecond;
  for (var y = 0; y < 64; y++) {
    for (var x = 0; x < 64; x++) {
      im.setPixelRgb(x, y, 40 + (x * y + rng) % 60, 120 + rng % 60, 40);
    }
  }
  return im;
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CreatureStore store;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tempDir = await Directory.systemTemp.createTemp('sprout_test');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    store = await CreatureStore.open();
  });

  tearDownAll(() => tempDir.delete(recursive: true));

  // ── CreatureState ──────────────────────────────────────────────────────────

  group('CreatureState', () {
    test('starts as shell with low energy/hunger', () {
      final s = CreatureState(lastUpdated: DateTime.now());
      expect(s.stage, CreatureStage.shell);
      expect(s.isHatched, false);
      expect(s.energy, 30.0);
      expect(s.hunger, 30.0);
    });

    test('isDormant at zero', () {
      final s = CreatureState(
          energy: 0, hunger: 50, lastUpdated: DateTime.now());
      expect(s.isDormant, true);
    });

    test('stage emoji maps correctly', () {
      expect(CreatureStage.shell.emoji, '🥚');
      expect(CreatureStage.sprout.emoji, '🌱');
      expect(CreatureStage.bloom.emoji, '🌸');
      expect(CreatureStage.grove.emoji, '�');
      expect(CreatureStage.canopy.emoji, '�');
      expect(CreatureStage.elder.emoji, '🌳');
    });

    test('copyWith preserves unmodified fields', () {
      final s = CreatureState(
          energy: 50,
          hunger: 40,
          stage: CreatureStage.sprout,
          lastUpdated: DateTime.now());
      final s2 = s.copyWith(energy: 80);
      expect(s2.energy, 80.0);
      expect(s2.hunger, 40.0);
      expect(s2.stage, CreatureStage.sprout);
    });

    test('mood derives from stats', () {
      CreatureState s({double e = 50, double h = 50}) =>
          CreatureState(
              energy: e, hunger: h, lastUpdated: DateTime.now());
      expect(s(e: 0).mood, CreatureMood.dormant);
      expect(s(e: 10, h: 90).mood, CreatureMood.gloomy);
      expect(s(e: 80, h: 80).mood, CreatureMood.happy);
      expect(s().mood, CreatureMood.content);
    });

    test('displayName falls back to Sprout', () {
      expect(
          CreatureState(lastUpdated: DateTime.now()).displayName,
          'Sprout');
      expect(
          CreatureState(lastUpdated: DateTime.now(), name: '  ')
              .displayName,
          'Sprout');
      expect(
          CreatureState(lastUpdated: DateTime.now(), name: 'Fern')
              .displayName,
          'Fern');
    });
  });

  // ── GrassGate ──────────────────────────────────────────────────────────────

  group('GrassGate', () {
    test('pure green image passes', () {
      final im = _grassImage();
      expect(GrassGate.evaluate(im), GrassVerdict.pass);
    });

    test('grey floor fails', () {
      final im = _solidColor(140, 140, 140);
      expect(GrassGate.evaluate(im), GrassVerdict.fail);
    });

    test('dark image fails', () {
      final im = _solidColor(15, 15, 15);
      expect(GrassGate.evaluate(im), GrassVerdict.fail);
    });

    test('blue sky fails (not grass)', () {
      final im = _solidColor(50, 100, 220);
      expect(GrassGate.evaluate(im), GrassVerdict.fail);
    });

    test('yellow-tinted green passes', () {
      // Yellow-green is still plant matter (H ~80)
      final im = _solidColor(140, 180, 30);
      expect(GrassGate.evaluate(im), GrassVerdict.pass);
    });
  });

  // ── ImagePrep ──────────────────────────────────────────────────────────────

  group('ImagePrep', () {
    test('decodes and resizes a valid PNG', () {
      final src = _grassImage();
      final bytes = Uint8List.fromList(img.encodePng(src));
      final prepared = ImagePrep.prepare(bytes);
      expect(prepared, isNotNull);
      expect(prepared!.width, lessThanOrEqualTo(ImagePrep.maxEdge));
    });

    test('returns null on garbage bytes', () {
      final bad = Uint8List.fromList([0, 1, 2, 3, 255, 254]);
      expect(ImagePrep.prepare(bad), isNull);
    });
  });

  // ── Parse ─────────────────────────────────────────────────────────────────

  group('Parse', () {
    test('yesNo parses yes variants', () {
      expect(Parse.yesNo('yes'), true);
      expect(Parse.yesNo('YES'), true);
      expect(Parse.yesNo('Yes, definitely grass'), true);
    });

    test('yesNo parses no variants', () {
      expect(Parse.yesNo('no'), false);
      expect(Parse.yesNo('No, that is a wall'), false);
    });

    test('yesNo defaults on ambiguity', () {
      expect(Parse.yesNo('hmm', defaultTo: true), true);
      expect(Parse.yesNo('hmm', defaultTo: false), false);
    });

    test('extractJson finds JSON in prose', () {
      final raw = 'Here is the result: {"verdict":"pass"} done.';
      final j = Parse.extractJson(raw);
      expect(j?['verdict'], 'pass');
    });

    test('extractJson returns null on no JSON', () {
      expect(Parse.extractJson('no json here'), isNull);
    });

    test('firstQuoted pulls value', () {
      final r = Parse.firstQuoted('{"key": "value"}', 'key');
      expect(r, 'value');
    });
  });

  // ── CreatureStore ──────────────────────────────────────────────────────────

  group('CreatureStore', () {
    test('loads fresh creature as shell', () async {
      final s = await store.loadCreature();
      expect(s.stage, CreatureStage.shell);
    });

    test('persists energy change', () async {
      var s = await store.loadCreature();
      s = s.copyWith(energy: 75.0);
      await store.saveCreature(s);
      final loaded = await store.loadCreature();
      expect(loaded.energy, 75.0);
    });

    test('care log counts by type', () async {
      await store.logCare(type: 'sunlight', detail: 4500.0);
      await store.logCare(type: 'sunlight', detail: 3200.0);
      await store.logCare(type: 'grass', detail: 0.72);
      expect(await store.careCount('sunlight'), greaterThanOrEqualTo(2));
      expect(await store.careCount('grass'), greaterThanOrEqualTo(1));
    });

    test('persists creature name', () async {
      var s = await store.loadCreature();
      await store.saveCreature(s.copyWith(name: 'Fern'));
      expect((await store.loadCreature()).displayName, 'Fern');
    });

    test('meal photos persist locally', () async {
      final bytes =
          Uint8List.fromList(img.encodeJpg(_grassImage()));
      final path = await store.logMeal(bytes, greenRatio: 0.6);
      expect(path, isNotNull);
      expect(File(path!).existsSync(), true);
      final meals = await store.meals();
      expect(meals.any((m) => m['path'] == path), true);
    });
  });

  // ── CreatureController decay ───────────────────────────────────────────────

  group('CreatureController decay', () {
    test('applies decay after 8 hours', () async {
      // Write state with lastUpdated 8 hours ago
      final stale = CreatureState(
        energy: 80.0,
        hunger: 80.0,
        stage: CreatureStage.sprout,
        lastUpdated:
            DateTime.now().subtract(const Duration(hours: 8)),
      );
      await store.saveCreature(stale);

      final ctrl = CreatureController(store: store);
      await ctrl.applyDecay();

      // energy: 80 - 8h × 12.5 = 80-100 = 0
      expect(ctrl.state.energy, 0.0);
      // hunger: 80 - 8h × 6.25 = 80-50 = 30
      expect(ctrl.state.hunger, closeTo(30.0, 1.0));
      ctrl.dispose();
    });

    test('feeds in the same 15-min block keep streak at 1', () async {
      final ctrl = CreatureController(store: store);
      await ctrl.applyDecay();
      await ctrl.feedSunlight(5000);
      await ctrl.feedSunlight(5000);
      expect(ctrl.state.streak, 1);
      ctrl.dispose();
    });
  });

  // ── Growth history & debug streak ─────────────────────────────────

  group('Growth & debug', () {
    test('comboDays counts days with both types once', () async {
      await store.logCare(type: 'sunlight');
      await store.logCare(type: 'grass');
      await store.logCare(type: 'grass');
      expect(await store.comboDays(), greaterThanOrEqualTo(1));
    });

    test('debugAdvanceStreak bumps streak on a hatched creature',
        () async {
      final ctrl = CreatureController(store: store);
      await ctrl.applyDecay();
      await ctrl.hatch();
      final before = ctrl.state.streak;
      final n = await ctrl.debugAdvanceStreak();
      expect(n, before + 1);
      ctrl.dispose();
    });
  });

  // ── Autonomy: wishes, decisions, walking ────────────────────────

  group('Autonomy', () {
    test('wishes persist: add, open, complete', () async {
      final id = await store.addWish(
        title: 'Find a red flower',
        description: 'Show me something red',
        kind: 'photo',
        verifyPrompt: 'Is there a red flower in this photo?',
      );
      var open = await store.openWishes();
      expect(open.any((w) => w['id'] == id), true);
      await store.completeWish(id);
      open = await store.openWishes();
      expect(open.any((w) => w['id'] == id), false);
      final all = await store.allWishes();
      expect(all.any((w) => w['id'] == id), true);
    });

    test('wishes filter by kind', () async {
      final id = await store.addWish(
          title: 'Walk with me',
          description: 'A little stroll',
          kind: 'walk');
      expect(
          (await store.openWishes('walk'))
              .any((w) => w['id'] == id),
          true);
      expect(
          (await store.openWishes('grass'))
              .any((w) => w['id'] == id),
          false);
    });

    test('fake decide demands sunlight when energy is low',
        () async {
      final g = FakeGemmaClient();
      final d = await g.decide(
        energy: 10,
        hunger: 90,
        stage: 'Hatchling',
        streak: 1,
        mood: 'gloomy',
        walking: false,
        hasWant: false,
      );
      expect(d.action, CreatureAction.demandSunlight);
      expect(d.line, isNotEmpty);
    });

    test('debug walk logs care and completes walk wishes',
        () async {
      final wishId = await store.addWish(
          title: 'Walk with me',
          description: 'A little stroll',
          kind: 'walk');
      final ctrl = CreatureController(store: store);
      await ctrl.applyDecay();
      await ctrl.hatch();
      await ctrl.debugWalkSimulate(80);
      final care = await store.careLog();
      expect(care.any((c) => c['type'] == 'walk'), true);
      expect(
          (await store.openWishes('walk'))
              .any((w) => w['id'] == wishId),
          false);
      ctrl.dispose();
    });
  });

  // ── CreatureBody ───────────────────────────────────────────────────

  group('CreatureBody', () {
    testWidgets('renders and paints without errors', (t) async {
      _mockSensorChannels(t.binding);
      final ctrl = CreatureController(store: store);
      // sqflite_ffi resolves over isolate ports — real async zone needed
      // (FakeAsync in testWidgets would suspend them forever).
      await t.runAsync(() async {
        await ctrl.applyDecay();
        await ctrl.hatch();
      });
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CreatureBody(controller: ctrl),
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byType(CustomPaint), findsWidgets);
      // A pet triggers squash+hop mid-frame — no paint exceptions.
      ctrl.pet();
      await t.pump(const Duration(milliseconds: 300));
      // Unmount first — disposes the body's timers/tickers so the
      // fake-async zone can flush cleanly.
      await t.pumpWidget(const SizedBox());
      ctrl.dispose();
    });
  });
}
