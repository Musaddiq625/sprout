import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

import 'package:sprout/src/ai/parse.dart';
import 'package:sprout/src/creature/creature_state.dart';
import 'package:sprout/src/creature/creature_store.dart';
import 'package:sprout/src/creature/creature_controller.dart';
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
      expect(CreatureStage.hatchling.emoji, '🐣');
      expect(CreatureStage.sprout.emoji, '🌱');
      expect(CreatureStage.bloom.emoji, '🌸');
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
    });

    test('hatch transitions shell to hatchling', () async {
      final ctrl = CreatureController(store: store);
      await ctrl.applyDecay();
      await ctrl.hatch();
      expect(ctrl.state.stage, CreatureStage.hatchling);
      expect(ctrl.state.hatchedAt, isNotNull);
    });
  });
}
