import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../ai/ai_service.dart';
import 'creature_state.dart';
import 'creature_store.dart';

/// Central state machine for the creature.
/// ChangeNotifier so the UI rebuilds on every stat change.
class CreatureController extends ChangeNotifier {
  CreatureController({required this.store});

  final CreatureStore store;
  final AiService _ai = AiService.instance;

  CreatureState _state = CreatureState(lastUpdated: DateTime.now());
  CreatureState get state => _state;

  /// Latest dialogue line — updated after every AI call.
  String _dialogue = '…';
  String get dialogue => _dialogue;

  /// Loaded quests — populated from quests.json on first call.
  List<Quest> _quests = [];
  List<Quest> get quests => _quests;

  /// Photo hashes already fed — for the duplicate-detection joke.
  final Set<String> _fedHashes = {};

  bool _loading = false;
  bool get loading => _loading;

  // ── Decay ────────────────────────────────────────────────────────────────

  /// Applies energy/hunger decay from stored timestamp delta.
  /// Called on app open — no timers, no background service.
  Future<void> applyDecay() async {
    _state = await store.loadCreature();
    final now = DateTime.now();
    final delta = now.difference(_state.lastUpdated);
    final hours = delta.inSeconds.clamp(0, 48 * 3600) / 3600;

    _state = _state.copyWith(
      energy: (_state.energy - hours * 12.5).clamp(0, 100),
      hunger: (_state.hunger - hours * 6.25).clamp(0, 100),
      lastUpdated: now,
    );
    await store.saveCreature(_state);
    notifyListeners();
  }

  // ── Hatch ────────────────────────────────────────────────────────────────

  /// Called by HatchPage after the egg cracks.
  Future<void> hatch() async {
    _state = _state.copyWith(
      stage: CreatureStage.hatchling,
      hatchedAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    await store.saveCreature(_state);
    await _loadQuests();
    _dialogue = await _ai.gemma.hatchMoment().catchError(
        (_) => 'Where am I? Something just changed.');
    notifyListeners();
  }

  // ── Greeting ─────────────────────────────────────────────────────────────

  /// Called on app open and after navigation back to creature page.
  Future<void> loadGreeting() async {
    _setLoading(true);
    try {
      final hours = _state.hatchedAt != null
          ? DateTime.now()
                  .difference(_state.lastUpdated)
                  .inHours
                  .abs()
              : 0;
      _dialogue = await _ai.gemma.greeting(
        energy: _state.energy,
        hunger: _state.hunger,
        stage: _state.stage.label,
        streak: _state.streak,
        hoursSinceCare: hours,
      );
    } catch (_) {
      _dialogue = 'Good morning.';
    }
    _setLoading(false);
    notifyListeners();
  }

  // ── Sunlight feed ─────────────────────────────────────────────────────────

  /// Called by SunlightPage after a successful 5-second lux hold.
  /// [lux] = the peak lux reading during the hold.
  Future<void> feedSunlight(double lux) async {
    _state = _state.copyWith(
      energy: (_state.energy + 25).clamp(0, 100),
      lastUpdated: DateTime.now(),
    );
    await store.saveCreature(_state);
    await store.logCare(type: 'sunlight', detail: lux);
    await _updateStreak();
    await _checkQuests();

    _setLoading(true);
    try {
      _dialogue = await _ai.gemma
          .afterSunlight(energy: _state.energy)
          .catchError((_) => 'That was good.');
    } catch (_) {
      _dialogue = 'That was good.';
    }
    _setLoading(false);
    notifyListeners();
  }

  // ── Grass feed ────────────────────────────────────────────────────────────

  /// Called by GrassPage after the pixel gate (or Gemma) accepts the photo.
  /// Returns 'ok' | 'duplicate' — caller shows the appropriate message.
  Future<String> feedGrass(Uint8List photoBytes, double greenRatio) async {
    final hash = md5.convert(photoBytes).toString();
    if (_fedHashes.contains(hash)) {
      _dialogue = await _ai.gemma
          .duplicatePhoto()
          .catchError((_) => 'I remember that patch.');
      notifyListeners();
      return 'duplicate';
    }
    _fedHashes.add(hash);

    _state = _state.copyWith(
      hunger: (_state.hunger + 25).clamp(0, 100),
      lastUpdated: DateTime.now(),
    );
    await store.saveCreature(_state);
    await store.logCare(type: 'grass', detail: greenRatio);
    await _updateStreak();
    await _checkQuests();

    _setLoading(true);
    try {
      _dialogue = await _ai.gemma
          .afterGrassPass(hunger: _state.hunger)
          .catchError((_) => 'Acceptable.');
    } catch (_) {
      _dialogue = 'Acceptable.';
    }
    _setLoading(false);
    notifyListeners();
    return 'ok';
  }

  /// Called when the gate (or Gemma) rejects the photo.
  Future<void> grassRejected() async {
    try {
      _dialogue = await _ai.gemma
          .afterGrassFail()
          .catchError((_) => 'That is not grass.');
    } catch (_) {
      _dialogue = 'That is not grass.';
    }
    notifyListeners();
  }

  // ── Streak ────────────────────────────────────────────────────────────────

  Future<void> _updateStreak() async {
    final dates = await store.careDates();
    final today = DateTime.now();
    final todayStr = _dateStr(today);
    final yesterdayStr = _dateStr(today.subtract(const Duration(days: 1)));

    int streak = _state.streak;
    if (dates.contains(todayStr)) {
      // Already cared today — streak unchanged, just confirm.
      if (streak == 0) streak = 1;
    } else if (dates.isNotEmpty && dates.first == yesterdayStr) {
      // Cared yesterday but not yet today — extend streak.
      streak = _state.streak + 1;
    } else {
      // Gap or first-ever care — streak starts at 1.
      streak = 1;
    }

    _state = _state.copyWith(
      streak: streak,
      lastCareDate: todayStr,
      lastUpdated: DateTime.now(),
    );

    // Stage progression is milestone-locked.
    _state = _state.copyWith(stage: _nextStage(_state.stage, streak));
    await store.saveCreature(_state);
    await _checkQuests();
  }

  CreatureStage _nextStage(CreatureStage current, int streak) {
    final earned = streak >= 14
        ? CreatureStage.elder
        : streak >= 7
            ? CreatureStage.bloom
            : streak >= 3
                ? CreatureStage.sprout
                : CreatureStage.hatchling;
    return earned.index > current.index ? earned : current;
  }

  String _dateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
      '-${dt.day.toString().padLeft(2, '0')}';

  // ── Quests ────────────────────────────────────────────────────────────────

  Future<void> _loadQuests() async {
    if (_quests.isNotEmpty) return;
    try {
      final raw = await rootBundle.loadString('assets/quests/quests.json');
      final list = jsonDecode(raw) as List;
      _quests = list
          .map((e) => Quest.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.chapter.compareTo(b.chapter));
      await _syncQuestCounts();
    } catch (_) {
      _quests = [];
    }
  }

  /// Loads quests and syncs their progress counts from the DB.
  Future<void> loadQuests() => _loadQuests();

  Future<void> _syncQuestCounts() async {
    final progress = await store.allQuestProgress();
    final sunCount = await store.careCount('sunlight');
    final grassCount = await store.careCount('grass');
    final combo = await store.todayHadBoth();
    final streak = _state.streak;

    for (final q in _quests) {
      final saved = progress[q.id];
      q.count = (saved?['count'] as int?) ?? 0;
      q.completed = saved?['completed_at'] != null;
      if (q.completed) continue;

      final current = switch (q.type) {
        QuestType.sunlightCount => sunCount,
        QuestType.grassCount => grassCount,
        QuestType.streak => streak,
        QuestType.comboCount => combo ? q.count + 1 : q.count,
      };

      if (current != q.count) {
        q.count = current;
        if (current >= q.target) {
          q.completed = true;
          await store.upsertQuest(q.id,
              count: current,
              completedAt: DateTime.now().millisecondsSinceEpoch);
          _dialogue = await _ai.gemma
              .questComplete(title: q.title, storyUnlock: q.storyUnlock)
              .catchError((_) => 'A new milestone: ${q.title}.');
        } else {
          await store.upsertQuest(q.id, count: current);
        }
      }
    }
  }

  Future<void> _checkQuests() => _syncQuestCounts();

  // ── Private ───────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}

// ── Quest model ──────────────────────────────────────────────────────────────

enum QuestType { sunlightCount, grassCount, streak, comboCount }

class Quest {
  Quest({
    required this.id,
    required this.title,
    required this.chapter,
    required this.description,
    required this.type,
    required this.target,
    required this.storyUnlock,
    this.count = 0,
    this.completed = false,
  });

  final String id;
  final String title;
  final int chapter;
  final String description;
  final QuestType type;
  final int target;
  final String storyUnlock;
  int count;
  bool completed;

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        id: j['id'] as String,
        title: j['title'] as String,
        chapter: j['chapter'] as int,
        description: j['description'] as String,
        type: QuestType.values.byName(j['type'] as String),
        target: j['target'] as int,
        storyUnlock: j['story_unlock'] as String,
      );
}
