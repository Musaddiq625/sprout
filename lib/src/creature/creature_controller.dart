import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show HapticFeedback, rootBundle;

import '../ai/ai_service.dart';
import '../ai/creature_tools.dart';
import '../ai/models.dart';
import 'creature_state.dart';
import 'creature_store.dart';
import 'lux_service.dart';
import 'shake_service.dart';
import 'step_service.dart';
import 'tilt_service.dart';

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

  // ── Sleep ────────────────────────────────────────────────────────────────

  /// Idle time before the creature falls asleep.
  static const sleepAfter = Duration(seconds: 10);

  /// Streak block length — each block needs ≥1 care event.
  static const streakBlock = Duration(minutes: 15);

  /// Gentle taps needed to wake a sleeping creature.
  static const tapsToWake = 3;

  /// Time asleep before a dream begins (💭 appears).
  static const dreamAfter = Duration(seconds: 5);

  /// Cooldowns so rapid taps/shakes don't spam Gemma.
  static const _petReactCooldown = Duration(seconds: 15);
  static const _dizzyCooldown = Duration(seconds: 10);

  bool _asleep = false;

  /// True while the creature is asleep. Wake by gentle taps or a
  /// physical shake — only taps preserve the dream.
  bool get isAsleep => _asleep;

  /// True while a dream is playing (asleep ≥ [dreamAfter]).
  bool _dreaming = false;
  bool get isDreaming => _dreaming;

  /// Briefly true after a shake shatters a dream — drives the 💥
  /// frame before the sleep overlay lifts.
  bool _dreamShattered = false;
  bool get dreamShattered => _dreamShattered;

  /// Awake taps — drives the heart-burst animation.
  int _petCount = 0;
  int get petCount => _petCount;

  /// Asleep taps — wake progress 0..[tapsToWake].
  int _sleepTaps = 0;
  int get sleepTaps => _sleepTaps;

  /// Awake-shake counter — drives the dizzy jiggle.
  int _dizzyCount = 0;
  int get dizzyCount => _dizzyCount;

  /// Every physical shake bumps this — the page plays the
  /// whole-screen earthquake on it (awake-dizzy and
  /// shake-to-wake both count).
  int _shakeCount = 0;
  int get shakeCount => _shakeCount;

  /// Bumped on every stage-up — the page plays shake→sparkle on it.
  int _evolveCount = 0;
  int get evolveCount => _evolveCount;

  /// The stage before the latest stage-up — shown during the shake
  /// phase so the new form visibly pops in at the sparkle moment.
  CreatureStage? _evolveFrom;
  CreatureStage? get evolveFrom => _evolveFrom;

  Timer? _sleepTimer;
  Timer? _dreamTimer;
  Timer? _shatterTimer;
  Timer? _streakTimer;
  StreamSubscription<double>? _shakeSub;
  DateTime? _lastPetReact;
  DateTime? _lastDizzy;

  // ── Autonomy / wants ─────────────────────────────────────────

  /// How often the creature consults its own will.
  static const autonomyEvery = Duration(minutes: 4);

  /// An unfulfilled want expires after this long.
  static const _wantTtl = Duration(minutes: 15);

  Timer? _autonomyTimer;
  Timer? _wantTimer;
  CreatureWant _want = CreatureWant.none;

  /// What the creature currently wants — drives the 💭 want
  /// bubble on its head.
  CreatureWant get want => _want;

  /// Sing counter — drives the 🎵 burst.
  int _singCount = 0;
  int get singCount => _singCount;

  // ── Tilt ─────────────────────────────────────────────────────

  /// Sideways lean at which the creature reacts (~20°).
  static const _tiltThreshold = 0.35;
  static const _tiltReactCooldown = Duration(seconds: 20);

  StreamSubscription<double>? _tiltSub;
  double _lean = 0;

  /// Low-pass-filtered lateral lean, -1 (left) .. 1 (right).
  /// The emoji leans with it.
  double get lean => _lean;
  bool _tilted = false;
  DateTime? _lastTiltReact;

  // ── Walking ──────────────────────────────────────────────────

  /// Steps in the trailing 30s that count as "walking".
  static const _walkingThreshold = 20;

  /// Quiet time after the last step that ends a walk.
  static const _walkEndQuiet = Duration(seconds: 60);

  /// Minimum steps for a walk to count as care.
  static const _walkMinSteps = 60;
  static const _walkLineCooldown = Duration(seconds: 90);

  StreamSubscription<int>? _stepSub;
  final List<DateTime> _steps = [];
  bool _isWalking = false;

  /// True while a walking cadence is sustained — 🐾 badge.
  bool get isWalking => _isWalking;
  int _sessionSteps = 0;
  Timer? _walkEndTimer;
  DateTime? _lastWalkLine;

  // ── Wishes (creature-invented quests) ────────────────────────

  List<Wish> _wishes = [];
  List<Wish> get wishes => _wishes;

  // ── Decay ────────────────────────────────────────────────────────────────

  /// Applies energy/hunger decay from stored timestamp delta.
  /// Called on app open — no timers, no background service.
  Future<void> applyDecay() async {
    _state = await store.loadCreature();
    final now = DateTime.now();
    if (_state.isHatched) {
      final delta = now.difference(_state.lastUpdated);
      final hours = delta.inSeconds.clamp(0, 48 * 3600) / 3600;

      _state = _state.copyWith(
        energy: (_state.energy - hours * 12.5).clamp(0, 100),
        hunger: (_state.hunger - hours * 6.25).clamp(0, 100),
        lastUpdated: now,
      );
      // A missed 15-min block breaks the streak — even before next care.
      if (_streakExpired(now)) _state = _state.copyWith(streak: 0);
    }
    _ai.gemma.creatureName = _state.displayName;
    await store.saveCreature(_state);
    notifyListeners();
    if (_state.isHatched) {
      startSleepWatcher();
      // Resume an in-flight evolution trial — the quest and its
      // progress survive restarts via the wishes/care tables.
      await _loadQuests();
      await _ensureEvolveQuest();
      await _refreshEvolve();
      notifyListeners();
    }
  }

  // ── Hatch ────────────────────────────────────────────────────────────────

  /// Called by HatchPage after the egg cracks.
  Future<void> hatch() async {
    _state = _state.copyWith(
      stage: CreatureStage.sprout,
      hatchedAt: DateTime.now(),
      lastUpdated: DateTime.now(),
    );
    await store.saveCreature(_state);
    _sunTouched = true; // hatching is the first touch
    await store.logStage(stage: CreatureStage.sprout.index, streak: 0);
    await _loadQuests();
    await _ensureEvolveQuest();
    await _refreshEvolve();
    // The first inference on a cold engine takes seconds — don't
    // block the hatch → name → creature flow on it. The line lands
    // in the dialogue bubble whenever it finishes.
    _ai.gemma.hatchMoment().then((line) {
      _dialogue = line;
      notifyListeners();
    }).catchError((_) {
      _dialogue = 'Where am I? Something just changed.';
      notifyListeners();
    });
    notifyListeners();
    startSleepWatcher();
  }

  // ── Greeting ─────────────────────────────────────────────────────────────

  /// Called on app open and after navigation back to creature page.
  Future<void> loadGreeting() async {
    if (!_state.isHatched) return;
    _setLoading(true);
    try {
      final minutes = _state.lastCareAt != null
          ? DateTime.now()
                  .difference(_state.lastCareAt!)
                  .inMinutes
                  .abs()
              : 0;
      _dialogue = await _ai.gemma.greeting(
        energy: _state.energy,
        hunger: _state.hunger,
        stage: _state.stage.label,
        streak: _state.streak,
        minutesSinceCare: minutes,
        mood: _state.mood.label,
      );
    } catch (_) {
      _dialogue = 'Good morning.';
    }
    _setLoading(false);
    noteActivity();
  }

  // ── Sunlight feed ─────────────────────────────────────────────────────────

  // ── Sunbathe (ambient light feed) ──────────────────────────

  /// Seconds of ≥[LuxService.soakLux] light that bank one
  /// sun-feed — chained, so 9s of real sun completes Rule B.
  static const sunChunkSecs = 3;

  StreamSubscription<double>? _luxSub;
  double _sunLux = 0;

  /// Latest ambient lux reading — feeds the rays UI and banner.
  double get sunLux => _sunLux;

  /// 0..1 log-normalized brightness for the ray intensity.
  double get sunIntensity => LuxService.intensity(_sunLux);

  double _sunHoldMs = 0;
  double _peakChunkLux = 0;
  double _lastTickHold = -1;
  DateTime? _lastLuxNotify;
  Timer? _soakTimer;

  /// 0..1 — progress inside the current 3s drink.
  double get sunHoldProgress =>
      (_sunHoldMs / (sunChunkSecs * 1000)).clamp(0.0, 1.0);

  /// True once the creature got ≥1 touch since this trial began —
  /// sun only counts toward evolution when someone's engaged,
  /// so it can't evolve alone in a sunny window.
  bool _sunTouched = true;
  bool get sunTouched => _sunTouched;

  static const _soakTick = Duration(milliseconds: 100);

  /// Charge leaks at 40% of fill speed once the light is gone —
  /// a passing shadow doesn't wipe it, sustained dark still does.
  static const _soakDrainFactor = 0.4;

  /// Stores the latest lux and arms the soak ticker. The ticker
  /// drives accumulation — the sensor only emits on CHANGE, so
  /// counting between events would stall under a steady sun.
  void _onLux(double lux) {
    if (!_state.isHatched) return;
    _sunLux = lux;
    _soakTimer ??= Timer.periodic(_soakTick, (_) => _soakTickFn());
    final now = DateTime.now();
    if (_lastLuxNotify == null ||
        now.difference(_lastLuxNotify!) >
            const Duration(milliseconds: 250)) {
      _lastLuxNotify = now;
      notifyListeners();
    }
  }

  /// 10Hz: fills the 3s drink while ≥ soakLux (only when the
  /// creature's been touched this trial), drains it back slowly
  /// when the light drops, banks a feed each completed drink.
  void _soakTickFn() {
    if (!_state.isHatched) return;
    final soaking = _sunLux >= LuxService.soakLux;
    if (soaking && _sunTouched) {
      _sunHoldMs += _soakTick.inMilliseconds.toDouble();
      if (_sunLux > _peakChunkLux) _peakChunkLux = _sunLux;
      if (_sunHoldMs >= sunChunkSecs * 1000) {
        _sunHoldMs = 0;
        final peak = _peakChunkLux;
        _peakChunkLux = 0;
        _bankSunFeed(peak);
      }
    } else if (_sunHoldMs > 0) {
      _sunHoldMs =
          (_sunHoldMs - _soakTick.inMilliseconds * _soakDrainFactor)
              .clamp(0.0, double.infinity);
      if (_sunHoldMs == 0) _peakChunkLux = 0;
    }
    // Notify only while the hold is actually moving — the UI
    // tweens between these updates for a smooth bar.
    if (_sunHoldMs != _lastTickHold) {
      _lastTickHold = _sunHoldMs;
      final now = DateTime.now();
      if (_lastLuxNotify == null ||
          now.difference(_lastLuxNotify!) >
              const Duration(milliseconds: 200)) {
        _lastLuxNotify = now;
        notifyListeners();
      }
    }
  }

  /// Banks an automatic sun-feed — but only if the creature has
  /// had attention this trial. Untouched, it just basks.
  Future<void> _bankSunFeed(double peak) async {
    if (!_sunTouched) return;
    // Speak on the first drink, then quietly — not a Gemma
    // inference every 3 seconds.
    final announce = _lastSunFeedAt == null ||
        DateTime.now().difference(_lastSunFeedAt!) >
            const Duration(seconds: 60);
    _lastSunFeedAt = DateTime.now();
    await feedSunlight(peak, announce: announce);
  }

  DateTime? _lastSunFeedAt;

  /// Bumped every time a sun-feed banks — the page flashes a
  /// check state on the drink bar when this changes (same
  /// watcher pattern as shakeCount/evolveCount).
  int _sunBankCount = 0;
  int get sunBankCount => _sunBankCount;

  /// Called when the sun-feed threshold was held (auto-soak or
  /// the honor-system hold on sensor-less devices).
  /// [lux] = the peak lux reading during the hold.
  Future<void> feedSunlight(double lux, {bool announce = true}) async {
    if (!_state.isHatched) return;
    _state = _state.copyWith(
      energy: (_state.energy + 25).clamp(0, 100),
      lastUpdated: DateTime.now(),
    );
    await store.saveCreature(_state);
    await store.logCare(type: 'sunlight', detail: lux);
    _sunTouched = true;
    _sunBankCount++;
    await _fulfillWant(CreatureWant.sunlight);
    await _completeWishes('sunlight');
    await _updateStreak();
    await _checkQuests();

    if (announce) {
      _setLoading(true);
      try {
        _dialogue = await _ai.gemma
            .afterSunlight(energy: _state.energy)
            .catchError((_) => 'That was good.');
      } catch (_) {
        _dialogue = 'That was good.';
      }
      _setLoading(false);
    } else {
      _dialogue = 'Soaking it in…';
      notifyListeners();
    }
    noteActivity();
  }

  // ── Grass feed ────────────────────────────────────────────────────────────

  /// Called by GrassPage after the pixel gate (or Gemma) accepts the photo.
  /// Returns 'ok' | 'duplicate' — caller shows the appropriate message.
  Future<String> feedGrass(Uint8List photoBytes, double greenRatio) async {
    if (!_state.isHatched) return 'ok';
    _sunTouched = true;
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
    // Keep the photo as a meal memory — local files, no sync.
    await store.logMeal(photoBytes, greenRatio: greenRatio);
    await _fulfillWant(CreatureWant.grass);
    await _completeWishes('grass');
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
    noteActivity();
    return 'ok';
  }

  /// Called when the gate (or Gemma) rejects the photo.
  Future<void> grassRejected() async {
    if (!_state.isHatched) return;
    try {
      _dialogue = await _ai.gemma
          .afterGrassFail()
          .catchError((_) => 'That is not grass.');
    } catch (_) {
      _dialogue = 'That is not grass.';
    }
    notifyListeners();
    noteActivity();
  }

  // ── Streak ────────────────────────────────────────────────────────────────

  /// 15-minute streak: every consecutive 15-min block must contain
  /// ≥1 care event. Care twice in the same block doesn't inflate it —
  /// the next feed has to land in the following block to extend.
  Future<void> _updateStreak() async {
    final periods = await store.carePeriods();
    final now = DateTime.now();
    final cur = _block(now);

    int streak = _state.streak;
    if (periods.contains(cur)) {
      // Already cared this block — streak holds, just confirm.
      if (streak == 0) streak = 1;
    } else if (periods.isNotEmpty && periods.first == cur - 1) {
      // Cared in the previous block but not yet this one — extend.
      streak = _state.streak + 1;
    } else {
      // Missed a block or first-ever care — streak starts at 1.
      streak = 1;
    }

    _state = _state.copyWith(
      streak: streak,
      lastCareAt: now,
      lastUpdated: now,
    );

    // Stage progression is trial-gated — feeds+quest, not streak.
    await _refreshEvolve();
    await store.saveCreature(_state);
    await _checkQuests();
  }

  /// Debug builds only: simulates one completed streak block so
  /// streak quests can be tested without waiting 15 min. Marks the
  /// current block as cared ('debug' never counts toward feeds,
  /// sun/grass quests or the evolution trial), bumps the streak.
  /// Returns the new streak, or null when unavailable.
  Future<int?> debugAdvanceStreak() async {
    if (!kDebugMode || !_state.isHatched) return null;
    final now = DateTime.now();
    await store.logCare(type: 'debug');
    _state = _state.copyWith(
      streak: _state.streak + 1,
      lastCareAt: now,
      lastUpdated: now,
    );
    await store.saveCreature(_state);
    await _checkQuests();
    noteActivity();
    notifyListeners();
    return _state.streak;
  }

  /// Debug builds only: skips the current evolution trial — same
  /// visual ceremony as a real stage-up. Returns the new stage.
  Future<CreatureStage?> debugEvolve() async {
    if (!kDebugMode || !_state.isHatched ||
        _state.stage.next == null) {
      return null;
    }
    await _evolve();
    noteActivity();
    notifyListeners();
    return _state.stage;
  }

  /// 15-minute block index — consecutive blocks carry the streak.
  int _block(DateTime dt) =>
      dt.millisecondsSinceEpoch ~/ streakBlock.inMilliseconds;

  /// True once a whole 15-min block passed with no care event.
  bool _streakExpired(DateTime now) {
    final last = _state.lastCareAt;
    return last != null &&
        _state.streak != 0 &&
        _block(now) - _block(last) > 1;
  }

  // ── Evolution trial ─────────────────────────────────────────

  /// Rule A — feeds needed alongside the trial quest.
  static const evolveFeedsNeeded = 2;

  /// Rule B — sunlight feeds that evolve without a quest.
  static const evolveSunNeeded = 3;

  /// When this trial began — the last stage-up (or hatch).
  int? _trialStart;

  /// Feeds logged since the trial started (any care type).
  int _trialFeeds = 0;
  int get trialFeeds => _trialFeeds;

  /// Sunlight feeds since the trial started.
  int _trialSun = 0;
  int get trialSun => _trialSun;

  /// The active trial quest — auto-created per stage boundary.
  /// Fulfilling it satisfies Rule A.
  Wish? _evolveQuest;

  /// The creature's current evolution quest, if a trial is open.
  Wish? get evolveQuest => _evolveQuest;

  /// True when a new quest (trial or invented wish) appeared since
  /// the user last opened the Quests page — drives the ! badge.
  bool _newQuestAlert = false;
  bool get newQuestAlert => _newQuestAlert;

  /// Incomplete quests + open wishes — drives a persistent badge on
  /// quest entry points. Unlike [newQuestAlert] it does NOT clear
  /// when the Quests page opens: pending work stays flagged until
  /// it's actually done.
  int get pendingQuestCount =>
      _quests.where((q) => !q.completed).length +
      _wishes.where((w) => !w.completed).length;

  /// Called when the Quests page opens — clears the alert.
  void markQuestsSeen() {
    _newQuestAlert = false;
    notifyListeners();
  }

  /// 0..1 — how close the current trial is to completion. Drives
  /// the circular progress ring around the creature.
  double _evolveProgress = 0;
  double get evolveProgress => _evolveProgress;

  /// True while a stage-up is pending (hatched, not yet elder).
  bool get trialActive =>
      _state.isHatched && _state.stage.next != null;

  /// The trial quest per target stage — deterministic templates so
  /// the requirement is always completable by real mechanics.
  static Map<String, String> _trialQuestFor(CreatureStage target) =>
      switch (target) {
        CreatureStage.bloom => const {
            'title': 'Show me a real flower',
            'description':
                'Take a photo of a flower outside so I can wear one too.',
            'kind': 'photo',
            'verify': 'Is there a flower visible in this photo?',
          },
        CreatureStage.grove => const {
            'title': 'Take me for a walk',
            'description':
                'Carry me outside and walk together for a while.',
            'kind': 'walk',
          },
        CreatureStage.canopy => const {
            'title': 'Show me a tree',
            'description':
                'I want to see what I might become — show me a real tree.',
            'kind': 'photo',
            'verify': 'Is there a tree visible in this photo?',
          },
        CreatureStage.elder => const {
            'title': 'Show me the open sky',
            'description':
                'One last look at the wide world before I settle.',
            'kind': 'photo',
            'verify': 'Is the sky visible in this outdoor photo?',
          },
        _ => const {
            'title': 'Spend time outside',
            'description': 'Feed me and keep me company outdoors.',
            'kind': 'photo',
            'verify': 'Was this photo taken outdoors in nature?',
          },
      };

  /// Creates the evolution quest for the pending stage if none is
  /// open — called on hatch, after each evolve, and on app open so
  /// a mid-trial creature always has its quest.
  Future<void> _ensureEvolveQuest() async {
    final target = _state.stage.next;
    if (!_state.isHatched || target == null) {
      _evolveQuest = null;
      return;
    }
    _trialStart ??= await store.latestStageChange() ??
        _state.hatchedAt?.millisecondsSinceEpoch ??
        _state.lastUpdated.millisecondsSinceEpoch;
    // Any evolve wish created since this trial began counts —
    // a completed one satisfies Rule A, an open one is pending.
    final all = await store.allWishes();
    final existing = all.where((w) =>
        (w['is_evolve'] as int?) == 1 &&
        (w['created_at'] as int? ?? 0) >= _trialStart!);
    if (existing.isNotEmpty) {
      _evolveQuest = Wish.fromRow(existing.first);
      return;
    }
    final q = _trialQuestFor(target);
    final id = await store.addWish(
      title: q['title']!,
      description: q['description']!,
      kind: q['kind']!,
      verifyPrompt: q['verify'],
      isEvolve: true,
    );
    _newQuestAlert = true;
    _evolveQuest = Wish(
      id: id,
      title: q['title']!,
      description: q['description']!,
      kind: q['kind']!,
      verifyPrompt: q['verify'],
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isEvolve: true,
    );
    await _refreshWishes();
  }

  /// Recomputes trial progress and evolves when a rule is met.
  /// Rule A: ≥[evolveFeedsNeeded] feeds + the trial quest done.
  /// Rule B: ≥[evolveSunNeeded] sunlight feeds (no quest needed).
  /// Called after every care event and wish completion.
  Future<void> _refreshEvolve() async {
    if (!trialActive) {
      _evolveProgress = 0;
      _trialFeeds = 0;
      _trialSun = 0;
      return;
    }
    _trialStart ??= await store.latestStageChange() ??
        _state.hatchedAt?.millisecondsSinceEpoch ??
        _state.lastUpdated.millisecondsSinceEpoch;
    _trialFeeds = await store.feedsSince(_trialStart!);
    _trialSun = await store.sunFeedsSince(_trialStart!);

    // The quest is "done" if it was completed since the trial began
    // (or simply doesn't exist — e.g. already consumed).
    var questDone = false;
    if (_evolveQuest != null) {
      final rows = await store.allWishes();
      final found = rows
          .where((w) => w['id'] == _evolveQuest!.id);
      if (found.isNotEmpty) {
        _evolveQuest = Wish.fromRow(found.first);
        questDone = _evolveQuest!.completed;
      }
    }

    final progressA = (_trialFeeds / evolveFeedsNeeded)
            .clamp(0.0, 1.0) *
            0.6 +
        (questDone ? 0.4 : 0);
    final progressB =
        (_trialSun / evolveSunNeeded).clamp(0.0, 1.0);
    _evolveProgress = progressA >= progressB ? progressA : progressB;

    final ruleA =
        _trialFeeds >= evolveFeedsNeeded && questDone;
    final ruleB = _trialSun >= evolveSunNeeded;
    if (ruleA || ruleB) await _evolve();
  }

  /// The stage-up — fires the ceremony the page plays
  /// (shake → sparkle → new form), consumes the trial quest and
  /// opens the next trial.
  Future<void> _evolve() async {
    final next = _state.stage.next;
    if (next == null) return;
    _evolveFrom = _state.stage;
    _state = _state.copyWith(
      stage: next,
      lastUpdated: DateTime.now(),
    );
    _evolveCount++;
    _haptic(HapticFeedback.mediumImpact());
    await store.saveCreature(_state);
    await store.logStage(
        stage: next.index, streak: _state.streak);
    // Drop an unfinished trial quest — if the sunlight path
    // carried the evolve, the quest was never fulfilled, so it
    // must not be marked complete. Completed ones stay as
    // history in the wishes list.
    if (_evolveQuest != null && !_evolveQuest!.completed) {
      await store.deleteWish(_evolveQuest!.id);
    }
    _evolveQuest = null;
    _trialStart = null;
    _trialFeeds = 0;
    _trialSun = 0;
    _evolveProgress = 0;
    // New trial, new sun rules — it needs one touch before
    // ambient light banks toward this stage-up.
    _sunTouched = false;
    await _ensureEvolveQuest();
    await _refreshWishes();
    notifyListeners();
  }

  // ── Sleep / wake ─────────────────────────────────────────────────────────

  /// Arms the inactivity sleep timer, shake-to-wake listener and the
  /// streak expiry tick. Idempotent — safe to call from every entry
  /// point (app open, hatch). An egg does none of this.
  void startSleepWatcher() {
    if (!_state.isHatched) return;
    _shakeSub ??= ShakeService.shakes.listen(
      (_) => wake(),
      // No accelerometer on this platform — sleep still works.
      onError: (_) {},
    );
    _tiltSub ??= TiltService.lean.listen(
      _onLean,
      // Same channel family — missing platform support is silent.
      onError: (_) {},
    );
    _stepSub ??= StepService.steps.listen(
      (_) => _noteStep(),
      // No step detector / permission denied — walking just
      // never triggers.
      onError: (_) {},
    );
    _luxSub ??= LuxService.stream.listen(
      _onLux,
      // No light sensor — sunbathe just never charges; the
      // honor-system hold still feeds.
      onError: (_) {},
    );
    _streakTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _expireStreak(),
    );
    _autonomyTimer ??= Timer.periodic(
      autonomyEvery,
      (_) => _autonomyTick(),
    );
    noteActivity();
  }

  /// Any user interaction or finished work restarts the sleep
  /// countdown. No-op while asleep or unhatched — an egg never
  /// sleeps, only a hatched creature does.
  void noteActivity() {
    if (_asleep || !_state.isHatched) return;
    _sleepTimer?.cancel();
    _sleepTimer = Timer(sleepAfter, _fallAsleep);
  }

  void _fallAsleep() {
    if (!_state.isHatched) return;
    _asleep = true;
    _sleepTaps = 0;
    _dialogue = 'Zzz…';
    _haptic(HapticFeedback.vibrate());
    // Staying asleep long enough starts a dream.
    _dreamTimer = Timer(dreamAfter, () {
      if (!_asleep) return;
      _dreaming = true;
      notifyListeners();
    });
    notifyListeners();
  }

  /// A tap on the creature.
  /// Asleep → counts toward a gentle [tapsToWake]-tap wake (dream
  /// survives). Awake → a pet: haptic + heart + occasional Gemma line.
  /// An egg ignores taps — hatching has its own tap flow.
  void pet() {
    if (!_state.isHatched) return;
    _sunTouched = true;
    if (_asleep) {
      _sleepTaps++;
      _haptic(HapticFeedback.selectionClick());
      if (_sleepTaps >= tapsToWake) {
        wake(gently: true);
      } else {
        notifyListeners();
      }
      return;
    }
    _petCount++;
    _haptic(HapticFeedback.lightImpact());
    noteActivity();
    final now = DateTime.now();
    if (_lastPetReact == null ||
        now.difference(_lastPetReact!) > _petReactCooldown) {
      _lastPetReact = now;
      _ai.gemma.petted().then((line) {
        _dialogue = line;
        notifyListeners();
      }).catchError((_) {});
    }
    notifyListeners();
  }

  /// Wake paths: gentle taps keep the dream (it gets told); a shake
  /// startles it awake and the dream shatters. A shake while already
  /// awake makes it dizzy instead. An egg doesn't react at all.
  Future<void> wake({bool gently = false}) async {
    if (!_state.isHatched) return;
    if (!gently) {
      _shakeCount++;
      notifyListeners();
    }
    if (!_asleep) {
      if (!gently) _dizzy();
      return;
    }
    final wasDreaming = _dreaming;
    _dreamTimer?.cancel();
    _dreamTimer = null;
    _dreamShattered = wasDreaming && !gently;
    _asleep = false;
    _dreaming = false;
    _sleepTaps = 0;
    noteActivity();
    _setLoading(true);
    try {
      if (gently && wasDreaming) {
        _haptic(HapticFeedback.mediumImpact());
        _dialogue = await _ai.gemma.dream().catchError(
            (_) => 'I dreamed of a rain that never ended.');
      } else if (wasDreaming) {
        _haptic(HapticFeedback.heavyImpact());
        _dialogue = await _ai.gemma.startledWake().catchError(
            (_) => 'Whoa— easy! …the dream slipped away.');
      } else {
        _haptic(gently
            ? HapticFeedback.lightImpact()
            : HapticFeedback.mediumImpact());
        _dialogue = await _ai.gemma
            .wakeUp()
            .catchError((_) => 'Hm? …oh. It\'s you.');
      }
    } catch (_) {
      _dialogue = 'Hm? …oh. It\'s you.';
    }
    _setLoading(false);
    // Keep the 💥 frame up briefly so the shatter reads on screen.
    if (_dreamShattered) {
      _shatterTimer = Timer(const Duration(milliseconds: 900), () {
        _dreamShattered = false;
        notifyListeners();
      });
    }
  }

  /// Shake while awake — the whole world rattles.
  void _dizzy() {
    final now = DateTime.now();
    if (_lastDizzy != null &&
        now.difference(_lastDizzy!) < _dizzyCooldown) {
      return;
    }
    _lastDizzy = now;
    _dizzyCount++;
    _haptic(HapticFeedback.heavyImpact());
    noteActivity();
    _ai.gemma.dizzy().then((line) {
      _dialogue = line;
      notifyListeners();
    }).catchError((_) {});
  }

  /// Haptics are best-effort — a missing platform channel (tests,
  /// desktop) must never crash an interaction.
  void _haptic(Future<void> f) => f.catchError((_) {});

  // ── Wants / autonomy ─────────────────────────────────────────

  /// The creature declares a want — 💭 bubble shows what it
  /// craves until fulfilled or it forgets (~[_wantTtl]).
  void _setWant(CreatureWant w) {
    _want = w;
    _wantTimer?.cancel();
    _wantTimer = Timer(_wantTtl, () {
      _want = CreatureWant.none;
      notifyListeners();
    });
    notifyListeners();
  }

  /// A want was fulfilled by the matching care — gratitude line.
  Future<void> _fulfillWant(CreatureWant w) async {
    if (_want != w) return;
    _want = CreatureWant.none;
    _wantTimer?.cancel();
    try {
      _dialogue = await _ai.gemma
          .wantFulfilled(w.name)
          .catchError((_) => 'Thank you.');
    } catch (_) {}
    notifyListeners();
  }

  /// Autonomy tick — asks the model what it wants and executes
  /// the decision. Skips while asleep/thinking — the creature
  /// doesn't talk in its sleep.
  Future<void> _autonomyTick() async {
    if (_asleep || _loading || !_state.isHatched) return;
    try {
      final d = await _decide();
      await _executeDecision(d);
    } catch (_) {}
  }

  Future<Decision> _decide() => _ai.gemma.decide(
        energy: _state.energy,
        hunger: _state.hunger,
        stage: _state.stage.label,
        streak: _state.streak,
        mood: _state.mood.label,
        walking: _isWalking,
        hasWant: _want != CreatureWant.none,
      );

  /// "What do you want?" — tapping the dialogue bubble asks it
  /// to decide right now instead of waiting for the next tick.
  Future<void> askWhatItWants() async {
    if (_loading || _asleep || !_state.isHatched) return;
    _setLoading(true);
    try {
      await _executeDecision(await _decide());
    } catch (_) {
      _dialogue = 'Hmm. Nothing in particular.';
      notifyListeners();
    }
    _setLoading(false);
  }

  /// Carries out the creature's self-chosen action.
  Future<void> _executeDecision(Decision d) async {
    switch (d.action) {
      case CreatureAction.demandSunlight:
        _setWant(CreatureWant.sunlight);
        break;
      case CreatureAction.requestGrass:
        _setWant(CreatureWant.grass);
        break;
      case CreatureAction.requestWalk:
        _setWant(CreatureWant.walk);
        break;
      case CreatureAction.inventQuest:
        const kinds = {'sunlight', 'grass', 'photo', 'walk'};
        final kind = '${d.args['kind'] ?? 'photo'}';
        await store.addWish(
          title: '${d.args['title'] ?? 'A small wish'}',
          description: '${d.args['description'] ?? ''}',
          kind: kinds.contains(kind) ? kind : 'photo',
          verifyPrompt: d.args['verify_prompt'] as String?,
        );
        _newQuestAlert = true;
        await _refreshWishes();
        break;
      case CreatureAction.sing:
        _singCount++;
        break;
      case CreatureAction.nap:
        _dialogue = d.line.isEmpty ? 'Sleepy now…' : d.line;
        notifyListeners();
        _fallAsleep();
        return;
      case CreatureAction.ask:
      case CreatureAction.nothing:
        break;
    }
    if (d.line.isNotEmpty) _dialogue = d.line;
    notifyListeners();
  }

  // ── Tilt ─────────────────────────────────────────────────────

  void _onLean(double lean) {
    _lean = lean;
    final tiltedNow = lean.abs() > _tiltThreshold;
    if (tiltedNow && !_tilted) {
      _tilted = true;
      if (!_asleep) _reactToTilt();
    } else if (!tiltedNow) {
      _tilted = false;
    }
    notifyListeners();
  }

  /// Tilt-edge reaction — a wobble line + light haptic, throttled.
  void _reactToTilt() {
    if (!_state.isHatched) return;
    final now = DateTime.now();
    if (_lastTiltReact != null &&
        now.difference(_lastTiltReact!) < _tiltReactCooldown) {
      return;
    }
    _lastTiltReact = now;
    _haptic(HapticFeedback.lightImpact());
    noteActivity();
    _ai.gemma.tilted().then((line) {
      _dialogue = line;
      notifyListeners();
    }).catchError((_) {});
  }

  // ── Walking ──────────────────────────────────────────────────

  /// One detected step — keeps a 30s rolling window; ≥threshold
  /// steps means we're moving together. An egg can't walk.
  void _noteStep() {
    if (!_state.isHatched) return;
    final now = DateTime.now();
    _steps.add(now);
    _sessionSteps++;
    _steps.removeWhere((t) =>
        now.difference(t) > const Duration(seconds: 30));
    final was = _isWalking;
    _isWalking = _steps.length >= _walkingThreshold;
    _walkEndTimer?.cancel();
    _walkEndTimer = Timer(_walkEndQuiet, _endWalk);
    if (!_isWalking || was) return;
    notifyListeners();
    if (_lastWalkLine == null ||
        now.difference(_lastWalkLine!) > _walkLineCooldown) {
      _lastWalkLine = now;
      _ai.gemma.onWalk().then((line) {
        _dialogue = line;
        notifyListeners();
      }).catchError((_) {});
    }
  }

  /// Walk over — a real walk (≥[_walkMinSteps]) counts as care:
  /// it fills the streak block and completes walk wishes.
  Future<void> _endWalk() async {
    final steps = _sessionSteps;
    _sessionSteps = 0;
    _steps.clear();
    _isWalking = false;
    if (steps >= _walkMinSteps && _state.isHatched) {
      _sunTouched = true;
      await store.logCare(type: 'walk', detail: steps.toDouble());
      await _updateStreak();
      await _completeWishes('walk');
      await _fulfillWant(CreatureWant.walk);
      try {
        _dialogue = await _ai.gemma
            .afterWalk()
            .catchError((_) => 'What a walk.');
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Debug builds only: simulate a finished walk so walk care is
  /// testable without leaving the desk.
  Future<void> debugWalkSimulate([int steps = 80]) async {
    if (!kDebugMode || !_state.isHatched) return;
    _sessionSteps = steps;
    _isWalking = true;
    _walkEndTimer?.cancel();
    notifyListeners();
    await _endWalk();
  }

  // ── Wishes ───────────────────────────────────────────────────

  Future<void> _refreshWishes() async {
    _wishes =
        (await store.allWishes()).map(Wish.fromRow).toList();
    notifyListeners();
  }

  /// Completes every open wish of [kind] — sunlight/grass wishes
  /// finish on their feed, walk wishes on a real walk.
  Future<void> _completeWishes(String kind) async {
    final done = await store.openWishes(kind);
    for (final w in done) {
      await store.completeWish(w['id'] as int);
      _dialogue = await _ai.gemma
          .wishComplete('${w['title']}')
          .catchError((_) => 'You did it!');
    }
    await _refreshWishes();
    await _refreshEvolve();
  }

  /// Photo wishes are judged by the vision model against the
  /// yes/no question the creature itself invented.
  Future<bool> verifyPhotoWish(Wish wish, PreparedImage img) async {
    if (wish.completed || wish.verifyPrompt == null) return false;
    final ok = await _ai.gemma.judgePhoto(wish.verifyPrompt!, img);
    if (!ok) return false;
    _sunTouched = true;
    await store.completeWish(wish.id);
    await _refreshWishes();
    await _refreshEvolve();
    _haptic(HapticFeedback.mediumImpact());
    try {
      _dialogue = await _ai.gemma
          .wishComplete(wish.title)
          .catchError((_) => 'You did it!');
    } catch (_) {}
    notifyListeners();
    return true;
  }

  /// Persists the creature's name and threads it into the AI voice.
  Future<void> setName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _state = _state.copyWith(name: trimmed);
    await store.saveCreature(_state);
    _ai.gemma.creatureName = _state.displayName;
    notifyListeners();
  }

  /// Full reset — wipes the DB and drops back to a fresh egg.
  /// Sensor watchers stay armed (they no-op on a shell); every
  /// piece of creature state is rebuilt from the seeded row.
  Future<void> reset() async {
    _sleepTimer?.cancel();
    _dreamTimer?.cancel();
    _shatterTimer?.cancel();
    _wantTimer?.cancel();
    _walkEndTimer?.cancel();
    _asleep = false;
    _dreaming = false;
    _dreamShattered = false;
    _sleepTaps = 0;
    _isWalking = false;
    _sessionSteps = 0;
    _steps.clear();
    _want = CreatureWant.none;
    _sunLux = 0;
    _sunHoldMs = 0;
    _peakChunkLux = 0;
    _lastTickHold = -1;
    _soakTimer?.cancel();
    _soakTimer = null;
    _lastSunFeedAt = null;
    _sunBankCount = 0;
    _sunTouched = false;
    _evolveQuest = null;
    _trialStart = null;
    _trialFeeds = 0;
    _trialSun = 0;
    _evolveProgress = 0;
    _evolveFrom = null;
    _newQuestAlert = false;
    _wishes = [];
    _fedHashes.clear();
    _dialogue = '…';
    await store.resetAll();
    _state = await store.loadCreature();
    await _syncQuestCounts();
    notifyListeners();
  }

  /// Zeroes the streak on screen as soon as a block is missed —
  /// the creature visibly loses the chain, not just on next feed.
  void _expireStreak() {
    if (!_streakExpired(DateTime.now())) return;
    _state = _state.copyWith(streak: 0);
    store.saveCreature(_state);
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _dreamTimer?.cancel();
    _shatterTimer?.cancel();
    _streakTimer?.cancel();
    _autonomyTimer?.cancel();
    _wantTimer?.cancel();
    _walkEndTimer?.cancel();
    _shakeSub?.cancel();
    _tiltSub?.cancel();
    _stepSub?.cancel();
    _luxSub?.cancel();
    _soakTimer?.cancel();
    super.dispose();
  }

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

  /// Loads quests and syncs their progress counts from the DB —
  /// also refreshes the wishes list.
  Future<void> loadQuests() async {
    await _loadQuests();
    await _syncQuestCounts();
  }

  Future<void> _syncQuestCounts() async {
    final progress = await store.allQuestProgress();
    final sunCount = await store.careCount('sunlight');
    final grassCount = await store.careCount('grass');
    final combo = await store.comboDays();
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
        QuestType.comboCount => combo,
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
    await _refreshWishes();
  }

  Future<void> _checkQuests() => _syncQuestCounts();

  // ── Private ───────────────────────────────────────────────────────────────

  void _setLoading(bool v) {
    _loading = v;
    notifyListeners();
  }
}

// ── Quest model ──────────────────────────────────────────────────────────────

/// What the creature is currently craving — set by its own
/// decisions, cleared when the matching care arrives.
enum CreatureWant { none, sunlight, grass, walk }

/// A creature-invented quest — the model named it, the human can
/// fulfill it. Kinds: sunlight | grass | photo | walk.
class Wish {
  const Wish({
    required this.id,
    required this.title,
    required this.description,
    required this.kind,
    this.verifyPrompt,
    required this.createdAt,
    this.completed = false,
    this.isEvolve = false,
  });

  final int id;
  final String title;
  final String description;
  final String kind;
  final String? verifyPrompt;
  final int createdAt;
  final bool completed;

  /// True when this wish is the evolution trial quest —
  /// completing it satisfies Rule A of the pending stage-up.
  final bool isEvolve;

  factory Wish.fromRow(Map<String, Object?> r) => Wish(
        id: r['id'] as int,
        title: r['title'] as String,
        description: r['description'] as String,
        kind: r['kind'] as String,
        verifyPrompt: r['verify_prompt'] as String?,
        createdAt: (r['created_at'] as int?) ?? 0,
        completed: r['completed_at'] != null,
        isEvolve: (r['is_evolve'] as int?) == 1,
      );
}

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
