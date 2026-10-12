import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show EventChannel;

import '../ai/ai_service.dart';
import '../ai/model_manager.dart';
import '../creature/creature_controller.dart';
import '../creature/creature_state.dart';
import '../creature/lux_service.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import 'creature_widget.dart';
import 'grass_page.dart';
import 'hatch_page.dart';
import 'meals_page.dart';
import 'model_manager_page.dart';
import 'quest_page.dart';
import 'story_page.dart';
import 'widgets/name_sheet.dart';

/// The creature's home screen — energy/hunger bars, emoji, dialogue line,
/// and the two care actions.
class CreaturePage extends StatefulWidget {
  const CreaturePage({
    super.key,
    required this.store,
    required this.controller,
    required this.models,
  });

  final CreatureStore store;
  final CreatureController controller;
  final ModelManager models;

  @override
  State<CreaturePage> createState() => _CreaturePageState();
}

class _CreaturePageState extends State<CreaturePage>
    with TickerProviderStateMixin {
  late final AnimationController _jiggle;
  late final Animation<double> _jiggleAnim;
  late final AnimationController _evolve;
  late final AnimationController _quake;
  final _quakeRng = math.Random();
  int _quakeSeed = 0;
  int _lastPetCount = 0;
  int _lastDizzyCount = 0;
  int _lastSleepTaps = 0;
  int _lastEvolveCount = 0;
  int _lastShakeCount = 0;
  bool _lastAsleep = false;

  @override
  void initState() {
    super.initState();
    _jiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _jiggleAnim = Tween<double>(begin: -0.07, end: 0.07)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_jiggle);
    _evolve = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _quake = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    widget.controller.addListener(_onController);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadQuests();
      await widget.controller.loadGreeting();
    });
  }

  /// Pets, sleep-taps, dizzy-shakes and wake-ups all jiggle the
  /// creature. A stage-up instead runs the evolve sequence
  /// (shake the old form → sparkle-pop into the new one).
  void _onController() {
    final c = widget.controller;
    final woke = _lastAsleep && !c.isAsleep;
    if (c.evolveCount != _lastEvolveCount) {
      _lastEvolveCount = c.evolveCount;
      if (mounted) _evolve.forward(from: 0);
    }
    if (c.shakeCount != _lastShakeCount) {
      _lastShakeCount = c.shakeCount;
      // New random layout of disturbances for every quake —
      // like pictures settling differently each time.
      _quakeSeed = _quakeRng.nextInt(1 << 30);
      if (mounted) _quake.forward(from: 0);
    }
    if (c.petCount != _lastPetCount ||
        c.dizzyCount != _lastDizzyCount ||
        c.sleepTaps != _lastSleepTaps ||
        woke) {
      _lastPetCount = c.petCount;
      _lastDizzyCount = c.dizzyCount;
      _lastSleepTaps = c.sleepTaps;
      if (mounted) _jiggle.forward(from: 0);
    }
    _lastAsleep = c.isAsleep;
  }

  /// Persistent state bubble on the creature's head, top-right:
  /// 💥 shattered dream > 💭 dreaming > 💤 asleep > 💭 thinking.
  Widget? _headBadge(CreatureController c) {
    if (c.dreamShattered) {
      return const Text('💥', style: TextStyle(fontSize: 30));
    }
    if (c.isDreaming) {
      return const Text('💭',
          key: KeyConstants.dreamBubble,
          style: TextStyle(fontSize: 30));
    }
    if (c.isAsleep) {
      return const Text('💤', style: TextStyle(fontSize: 30));
    }
    if (c.loading) {
      return const Text('💭',
          key: KeyConstants.thinkingBubble,
          style: TextStyle(fontSize: 30));
    }
    return null;
  }

  /// Wraps [child] in the screen quake — [slot] decorrelates this
  /// widget's disturbance from its neighbours (reseeded per quake).
  Widget _shake(Widget child, int slot, [double strength = 1]) =>
      _Quake(
        animation: _quake,
        seed: _quakeSeed + slot * 7919,
        strength: strength,
        child: child,
      );

  /// Debug-only: long-press on the streak chip skips the current
  /// evolution trial — the quick way to watch it grow.
  Future<void> _debugEvolve(
      BuildContext context, CreatureController ctrl) async {
    final stage = await ctrl.debugEvolve();
    if (stage == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('debug: evolved → ${stage.label}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// Bottom sheet spelling out the current evolution trial:
  /// the quest, how to complete it, and both rule paths with
  /// live progress — so the player always knows the next step.
  void _showEvolveSheet(
      BuildContext context, CreatureController ctrl) {
    final s = ctrl.state;
    final next = s.stage.next;
    final q = ctrl.evolveQuest;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Evolution trial',
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            Text(
              '${s.stage.label} → ${next?.label ?? '?'}',
              style: Theme.of(sheet)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (q != null) ...[
              Text('Quest: ${q.title}',
                  style: Theme.of(sheet).textTheme.titleSmall),
              Text(q.description,
                  style: Theme.of(sheet).textTheme.bodySmall),
              Text(
                switch (q.kind) {
                  'photo' =>
                    'Complete it: open Quests and tap 📷 on this wish.',
                  'walk' =>
                    'Complete it: carry the phone and walk outside.',
                  'sunlight' => 'Complete it: hold it in sunlight.',
                  'grass' => 'Complete it: photograph grass to feed it.',
                  _ => '',
                },
                style: Theme.of(sheet)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],
            Text('Two ways to evolve — either works:',
                style: Theme.of(sheet).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(
              '① ${ctrl.trialFeeds}/${CreatureController.evolveFeedsNeeded} feeds'
              '  +  quest ${q?.completed == true ? 'done ✓' : 'pending'}\n'
              '② ~${CreatureController.evolveSunNeeded * CreatureController.sunChunkSecs}s of real sunlight — '
              '${ctrl.trialSun}/${CreatureController.evolveSunNeeded} drinks banked '
              '(no quest needed)',
              style: Theme.of(sheet).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.auto_stories, size: 16),
                label: const Text('Open quests'),
                onPressed: () {
                  Navigator.pop(sheet);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => QuestPage(controller: ctrl),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wipes everything — stage, history, quests, wishes, meals —
  /// and returns to the egg. Confirmed by dialog first.
  Future<void> _confirmReset(
      BuildContext context, CreatureController ctrl) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start over?'),
        content: Text(
          'This wipes ${ctrl.state.displayName} completely — '
          'stage, growth history, quests, wishes and meal '
          'memories. It will be a fresh egg.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ctrl.reset();
    if (!context.mounted) return;
    // Back to a fresh egg — the hatch flow owns it from here.
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => HatchPage(
          store: widget.store,
          controller: ctrl,
          models: widget.models,
        ),
      ),
      (r) => false,
    );
  }

  String _wantEmoji(CreatureWant w) => switch (w) {
        CreatureWant.sunlight => '☀️',
        CreatureWant.grass => '🌿',
        CreatureWant.walk => '🐾',
        CreatureWant.none => '',
      };

  Color _moodColor(CreatureMood mood) => switch (mood) {
        CreatureMood.happy => Colors.greenAccent,
        CreatureMood.content => Colors.tealAccent,
        CreatureMood.gloomy => Colors.blueGrey,
        CreatureMood.dormant => Colors.orange,
      };

  /// What the painted body actually looks like at this stage —
  /// used by the about sheet so the appearance is explained,
  /// not just named.
  String _stageLook(CreatureStage stage) => switch (stage) {
        CreatureStage.shell =>
          'an egg — tap it until it cracks',
        CreatureStage.sprout =>
          'newly hatched — a thin stem and two leaves reaching up',
        CreatureStage.bloom =>
          'its stem grew taller and a flower opened on the tip',
        CreatureStage.grove =>
          'a leafy crest on a stronger body — a proper little plant',
        CreatureStage.canopy =>
          'a flower crown over the crest — nearly fully grown',
        CreatureStage.elder =>
          'a full canopy of leaves — its final form',
      };

  /// What each mood means in care terms — mirrors the real
  /// derivation in CreatureState.mood.
  String _moodMeaning(CreatureMood mood) => switch (mood) {
        CreatureMood.happy =>
          'fully cared for — energy and hunger are both high',
        CreatureMood.content =>
          'doing okay — regular care keeps it this way',
        CreatureMood.gloomy =>
          'a stat dropped under 25 — it needs a feed soon',
        CreatureMood.dormant =>
          'starved — energy or hunger hit zero; it can barely move',
      };

  /// Tap the mood chip → everything about the creature in one
  /// sheet: what it looks like, what its mood means, its stats,
  /// and how to wake it.
  void _showAboutSheet(
      BuildContext context, CreatureController ctrl) {
    final s = ctrl.state;
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('About ${s.displayName}',
                style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              '${s.stage.emoji} ${s.stage.label} — ${_stageLook(s.stage)}',
              style: Theme.of(sheet).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${s.mood.emoji} ${s.mood.label} — ${_moodMeaning(s.mood)}',
              style: Theme.of(sheet).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              '☀️ ${s.energy.round()} energy · '
              '🌿 ${s.hunger.round()} hunger · '
              '🔥 ${s.streak} streak · '
              '🥤 ${ctrl.trialSun}/${CreatureController.evolveSunNeeded} sun drinks',
              style: Theme.of(sheet)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(
              'While asleep — tap ×${CreatureController.tapsToWake} '
              'for a gentle wake (it tells you its dream), or '
              'shake the phone for a rough wake (dream forgotten).',
              style: Theme.of(sheet)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _jiggle.dispose();
    _evolve.dispose();
    _quake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final ai = AiService.instance;

    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final s = ctrl.state;
        return Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              // The whole screen gets a low-strength rattle; the
              // widgets inside each get their own disturbance.
              child: _shake(
              Column(
                children: [
                  // ── Status row ─────────────────────────────────────────
                  _shake(Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Debug builds: long-press skips the current
                      // evolution trial — same ceremony as a real
                      // stage-up.
                      GestureDetector(
                        onLongPress: kDebugMode
                            ? () => _debugEvolve(context, ctrl)
                            : null,
                        child: Chip(
                          key: KeyConstants.streakChip,
                          avatar: const Icon(
                              Icons.local_fire_department,
                              size: 16),
                          label:
                              Text('${s.streak} × 15-min streak'),
                        ),
                      ),
                      IconButton(
                        key: KeyConstants.resetButton,
                        icon: const Icon(Icons.restart_alt,
                            size: 18),
                        tooltip: 'Reset',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            _confirmReset(context, ctrl),
                      ),
                      IconButton(
                        key: KeyConstants.storyButton,
                        icon: const Icon(Icons.auto_stories,
                            size: 18),
                        tooltip: 'Story',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          ctrl.noteActivity();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => StoryPage(
                                  controller: ctrl,
                                  store: widget.store),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 12),
                      ActionChip(
                        key: KeyConstants.modelStatusChip,
                        avatar: Icon(
                          ai.mode == 'real'
                              ? Icons.memory
                              : Icons.cloud_off,
                          size: 16,
                        ),
                        label: Text(
                            ai.mode == 'real' ? 'AI: on-device' : 'AI: demo'),
                        onPressed: () {
                          ctrl.noteActivity();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ModelManagerPage(manager: widget.models),
                            ),
                          ).then((_) => ai.refresh());
                        },
                      ),
                    ],
                  ), 1),
                  const SizedBox(height: 8),

                  // ── On-device proof chips ────────────────────────────
                  // wifi / airplane / Gemma-thinking — during a demo,
                  // "wifi off + airplane on + thinking" is the whole pitch.
                  _shake(_StatusChips(controller: ctrl), 2),
                  const SizedBox(height: 16),

                  // ── Stat bars ──────────────────────────────────────────
                  _shake(
                    _StatBar(
                      key: KeyConstants.energyBar,
                      emoji: '☀️',
                      label: 'Energy',
                      value: s.energy,
                      color: const Color(0xFFFFC107),
                    ),
                    3,
                  ),
                  const SizedBox(height: 12),
                  _shake(
                    _StatBar(
                      key: KeyConstants.hungerBar,
                      emoji: '🌿',
                      label: 'Hunger',
                      value: s.hunger,
                      color: const Color(0xFF4CAF50),
                    ),
                    4,
                  ),
                  const SizedBox(height: 32),

                  // ── Creature ──────────────────────────────────────────
                  // Tap to pet. Every state lives on its head, top-right:
                  // 💤 asleep · 💭 dreaming/thinking · 💥 shattered ·
                  // 💫 dizzy · 💚 hearts — never a full-screen takeover.
                  _shake(
                  GestureDetector(
                    onTap: ctrl.pet,
                    // Debug builds: long-press skips the current
                    // evolution trial — same ceremony as a real
                    // stage-up, so the whole arc is testable fast.
                    onLongPress: kDebugMode
                        ? () async {
                            final stage = await ctrl.debugEvolve();
                            if (stage != null && context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'debug: evolved → ${stage.label}'),
                                  duration:
                                      const Duration(seconds: 1),
                                ),
                              );
                            }
                          }
                        : null,
                    child: AnimatedBuilder(
                      animation: _jiggleAnim,
                      builder: (_, child) => Transform.rotate(
                        angle: _jiggleAnim.value,
                        child: child,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Ambient sun — converging rays bloom
                          // around the creature as real lux rises.
                          Positioned(
                            left: -70,
                            right: -70,
                            top: -70,
                            bottom: -70,
                            child: IgnorePointer(
                              child: _SunRays(
                                key: KeyConstants.sunRays,
                                intensity: ctrl.sunIntensity,
                              ),
                            ),
                          ),
                          // Circular evolution-progress ring —
                          // tracks the current trial (2 feeds +
                          // quest, or 3 sunlight feeds).
                          if (ctrl.trialActive)
                            Positioned(
                              left: -14,
                              top: -14,
                              child: IgnorePointer(
                                child: _EvolveRing(
                                  key: KeyConstants.evolveRing,
                                  progress: ctrl.evolveProgress,
                                ),
                              ),
                            ),
                          // Evolve sequence: the OLD form shakes for
                          // the first 45%, then scale-pops into the
                          // new emoji while sparkles burst around it.
                          AnimatedBuilder(
                            animation: _evolve,
                            builder: (_, _) {
                              final v = _evolve.value;
                              final stageOverride =
                                  (v > 0 && v < 0.45 &&
                                          ctrl.evolveFrom != null)
                                      ? ctrl.evolveFrom
                                      : null;
                              final shake = v < 0.45
                                  ? math.sin(v * math.pi * 22) *
                                      5 *
                                      (1 - v / 0.45)
                                  : 0.0;
                              final pop = v >= 0.45
                                  ? 1 +
                                      math.sin((v - 0.45) /
                                              0.55 *
                                              math.pi) *
                                          0.35
                                  : 1.0;
                              return Transform.translate(
                                offset: Offset(shake, 0),
                                child: Transform.scale(
                                  scale: pop,
                                  // The creature leans with the
                                  // device tilt — continuous,
                                  // driven by the accelerometer.
                                  child: Transform.rotate(
                                    angle: ctrl.lean * 0.3,
                                    child: Opacity(
                                      opacity: ctrl.isAsleep
                                          ? 0.45
                                          : 1,
                                      child: Hero(
                                        tag: 'creatureHero',
                                        child: CreatureBody(
                                          key: KeyConstants
                                              .creatureEmoji,
                                          controller: ctrl,
                                          stageOverride:
                                              stageOverride,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // 💭 want bubble — what the creature is
                          // currently craving (its own decision).
                          if (ctrl.want != CreatureWant.none)
                            Positioned(
                              top: -14,
                              left: -34,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Text('💭',
                                      style: TextStyle(
                                          fontSize: 30)),
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(
                                            bottom: 4),
                                    child: Text(
                                      _wantEmoji(ctrl.want),
                                      key: KeyConstants
                                          .wantBubble,
                                      style: const TextStyle(
                                          fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // 🐾 while a walking cadence is detected.
                          if (ctrl.isWalking)
                            const Positioned(
                              top: 20,
                              left: -32,
                              child: Text('🐾',
                                  key: KeyConstants.walkBadge,
                                  style: TextStyle(fontSize: 22)),
                            ),
                          // 🔍 — peer at it up close: fullscreen
                          // focus view, Hero-zoomed, no buttons.
                          // The hit box must sit INSIDE the stack
                          // bounds — Flutter never hit-tests
                          // children painted outside the parent.
                          Positioned(
                            left: -10,
                            bottom: -4,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                ctrl.noteActivity();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        _CreatureFocusPage(
                                      controller: ctrl,
                                    ),
                                  ),
                                );
                              },
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(
                                  child: Text(
                                    '🔍',
                                    key: KeyConstants
                                        .magnifierBadge,
                                    style:
                                        TextStyle(fontSize: 22),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // 🎵 when it decided to sing.
                          if (ctrl.singCount > 0)
                            Positioned(
                              top: -16,
                              left: -14,
                              child: _NoteBurst(
                                key: ValueKey(ctrl.singCount),
                              ),
                            ),
                          if (ctrl.evolveCount > 0)
                            Positioned(
                              left: 52,
                              top: 52,
                              child: _SparkleBurst(
                                key: ValueKey(ctrl.evolveCount),
                              ),
                            ),
                          if (_headBadge(ctrl) != null)
                            Positioned(
                              top: -12,
                              right: -24,
                              child: _headBadge(ctrl)!,
                            ),
                          if (ctrl.petCount > 0)
                            Positioned(
                              top: -18,
                              right: -6,
                              child: _HeartBurst(
                                key: ValueKey(ctrl.petCount),
                              ),
                            ),
                          if (ctrl.dizzyCount > 0)
                            Positioned(
                              top: -18,
                              right: -40,
                              child: _DizzyBurst(
                                key: ValueKey(ctrl.dizzyCount),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ), 5),
                  const SizedBox(height: 4),

                  // Name — tap to rename.
                  _shake(GestureDetector(
                    onTap: () async {
                      final name = await showNameSheet(
                          context, current: s.name);
                      if (name != null) await ctrl.setName(name);
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.displayName,
                          key: KeyConstants.creatureName,
                          style:
                              Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.edit,
                          size: 14,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ],
                    ),
                  ), 6),
                  Text(
                    s.stage.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  _shake(Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: GestureDetector(
                      onTap: () {
                        ctrl.noteActivity();
                        _showAboutSheet(context, ctrl);
                      },
                      child: Chip(
                        key: KeyConstants.moodChip,
                        avatar: Text(s.mood.emoji),
                        label: Text(s.mood.label),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: _moodColor(s.mood)
                            .withValues(alpha: 0.15),
                      ),
                    ),
                  ), 7),
                  if (ctrl.isAsleep || ctrl.dreamShattered)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        ctrl.dreamShattered
                            ? 'the dream shattered'
                            : ctrl.isDreaming
                                ? 'dreaming — tap ×${CreatureController.tapsToWake} to hear it · a shake loses it'
                                : 'asleep — tap ×${CreatureController.tapsToWake - ctrl.sleepTaps} or shake',
                        key: KeyConstants.sleepHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  // ── Evolution quest card ─────────────────────────────
                  // The current trial made visible: what stage is next,
                  // the quest it asks for, and both ways to finish it.
                  // Tap → explains the rules in a sheet.
                  if (ctrl.trialActive)
                    _shake(Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          ctrl.noteActivity();
                          _showEvolveSheet(context, ctrl);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4E9A3D)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF4E9A3D)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('✨',
                                      style:
                                          TextStyle(fontSize: 13)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      'Evolve → '
                                      '${ctrl.state.stage.next?.label ?? ''}'
                                      '${ctrl.evolveQuest != null ? ' · ${ctrl.evolveQuest!.title}' : ''}',
                                      key: KeyConstants
                                          .evolveQuestChip,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge,
                                      overflow:
                                          TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(Icons.info_outline,
                                      size: 14),
                                ],
                              ),
                              Text(
                                '${ctrl.trialFeeds}/${CreatureController.evolveFeedsNeeded} feeds'
                                ' + quest ${ctrl.evolveQuest?.completed == true ? '✓' : '☐'}'
                                '  ·or·  '
                                '☀️ ${ctrl.trialSun}/${CreatureController.evolveSunNeeded}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ), 8)
                  else if (s.stage == CreatureStage.elder)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Fully grown — final form',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  // Ambient sunbathe — live lux, the 3s charge
                  // in the current drink, drinks banked.
                  // Always listening; real outdoor light only.
                  _shake(_SunBanner(controller: ctrl), 14),

                  const SizedBox(height: 24),

                  // ── Dialogue ───────────────────────────────────────────
                  // Tap the bubble: ask the creature what it wants.
                  _shake(GestureDetector(
                    onTap: () {
                      ctrl.noteActivity();
                      ctrl.askWhatItWants();
                    },
                    child: Container(
                      key: KeyConstants.dialogueBubble,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ctrl.loading
                          ? const Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                                SizedBox(width: 12),
                                Text('…'),
                              ],
                            )
                          : Text(
                              '"${ctrl.dialogue}"',
                              key: KeyConstants.creatureDialogue,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(fontStyle: FontStyle.italic),
                            ),
                    ),
                  ), 9),
                  const Spacer(),

                  // ── Actions ────────────────────────────────────────────
                  _shake(_ActionButton(
                    key: KeyConstants.feedSunlightButton,
                    emoji: '☀️',
                    label: 'Bask in Sun',
                    subtitle: ctrl.sunLux >= LuxService.soakLux
                        ? 'soaking — ${ctrl.trialSun}/${CreatureController.evolveSunNeeded} drinks'
                        : 'take it into real light',
                    onTap: () {
                      ctrl.noteActivity();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'it soaks up sunlight on its own — carry it outside ☀️',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  ), 10),
                  const SizedBox(height: 12),
                  _shake(_ActionButton(
                    key: KeyConstants.feedGrassButton,
                    emoji: '🌿',
                    label: 'Feed Grass',
                    subtitle: 'Show it a patch of green',
                    onTap: () {
                      ctrl.noteActivity();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GrassPage(
                            controller: ctrl,
                            store: widget.store,
                          ),
                        ),
                      );
                    },
                  ), 11),
                  const SizedBox(height: 12),
                  _shake(_ActionButton(
                    key: KeyConstants.questsButton,
                    emoji: '📜',
                    label: 'Quests',
                    subtitle: 'Story milestones and streaks',
                    // ! for a fresh arrival; otherwise the count
                    // of quests/wishes still pending.
                    badgeLabel: ctrl.newQuestAlert
                        ? '!'
                        : (ctrl.pendingQuestCount > 0
                            ? '${ctrl.pendingQuestCount}'
                            : null),
                    onTap: () {
                      ctrl.noteActivity();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QuestPage(controller: ctrl),
                        ),
                      );
                    },
                  ), 12),
                  const SizedBox(height: 12),
                  _shake(_ActionButton(
                    key: KeyConstants.mealsButton,
                    emoji: '🍃',
                    label: 'Memories',
                    subtitle: 'Every meal it remembers',
                    onTap: () {
                      ctrl.noteActivity();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MealsPage(store: widget.store),
                        ),
                      );
                    },
                  ), 13),
                  const SizedBox(height: 16),
                ],
              ), 0, 0.35),
            ),
          ),
        );
      },
    );
  }
}

/// A 💚 that floats up and fades on each pet. Recreated per pet via
/// ValueKey — the whole animation lives in its own short lifecycle.
class _HeartBurst extends StatefulWidget {
  const _HeartBurst({super.key});

  @override
  State<_HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<_HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: 1 - _ctrl.value,
        child: Transform.translate(
          offset: Offset(0, -36 * _ctrl.value),
          child: const Text(
            '💚',
            key: KeyConstants.petHeart,
            style: TextStyle(fontSize: 26),
          ),
        ),
      ),
    );
  }
}

/// A 💫 that spins up and fades on each awake-shake. Recreated per
/// shake via ValueKey — the whole animation lives in its own lifecycle.
class _DizzyBurst extends StatefulWidget {
  const _DizzyBurst({super.key});

  @override
  State<_DizzyBurst> createState() => _DizzyBurstState();
}

class _DizzyBurstState extends State<_DizzyBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: 1 - _ctrl.value,
        child: Transform.rotate(
          angle: _ctrl.value * 6.28,
          child: Transform.translate(
            offset: Offset(0, -24 * _ctrl.value),
            child: const Text('💫', style: TextStyle(fontSize: 26)),
          ),
        ),
      ),
    );
  }
}

/// A 🎵 that drifts up and fades when the creature decides to
/// sing. Recreated per song via ValueKey — self-lifecycle.
class _NoteBurst extends StatefulWidget {
  const _NoteBurst({super.key});

  @override
  State<_NoteBurst> createState() => _NoteBurstState();
}

class _NoteBurstState extends State<_NoteBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) => Opacity(
        opacity: 1 - _ctrl.value,
        child: Transform.translate(
          offset: Offset(-14 * _ctrl.value, -40 * _ctrl.value),
          child: const Text('🎵', style: TextStyle(fontSize: 24)),
        ),
      ),
    );
  }
}

/// ✨ burst on evolution — stays hidden during the shake phase,
/// then five sparks fly outward while the new form pops in.
/// Recreated per stage-up via ValueKey — self-lifecycle animation.
class _SparkleBurst extends StatefulWidget {
  const _SparkleBurst({super.key});

  @override
  State<_SparkleBurst> createState() => _SparkleBurstState();
}

class _SparkleBurstState extends State<_SparkleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _spark(double t, double angle) {
    final r = 14 + 48 * t;
    return Transform.translate(
      offset: Offset(math.cos(angle) * r, math.sin(angle) * r),
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.4 + t * 0.9,
          child: const Text('✨', style: TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        // Silent during the creature's shake; bursts on the pop.
        if (_ctrl.value < 0.45) return const SizedBox.shrink();
        final t = (_ctrl.value - 0.45) / 0.55;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 5; i++)
              _spark(t, -math.pi / 2 + i * math.pi * 2 / 5),
          ],
        );
      },
    );
  }
}

/// Circular evolution-progress ring around the creature — the arc
/// fills as the current trial nears completion (2 feeds + quest,
/// or 3 sunlight feeds). Drawn behind the body, ignores touches.
/// One physically-shaken widget — earthquake physics on a shared
/// 1s controller. Damped sine: `sin(t·π·w)·(1−t)` rattles hard at
/// t=0 and decays to exactly zero at t=1s — the "settle back into
/// place" is built into the envelope, no return phase needed.
/// [seed] decorrelates direction/amplitude per widget AND per
/// quake (the page reseeds on every shake).
class _Quake extends StatelessWidget {
  const _Quake({
    required this.animation,
    required this.seed,
    required this.child,
    this.strength = 1,
  });

  final Animation<double> animation;

  /// Per-widget seed — includes the per-quake epoch so each shake
  /// disturbs the layout differently.
  final int seed;

  /// Motion multiplier — 1 for widgets, ~0.35 for the whole screen.
  final double strength;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final t = animation.value;
        if (t <= 0 || t >= 1) return child!;
        final r = math.Random(seed);
        final dx = (r.nextDouble() * 2 - 1) * 16 * strength;
        final dy = (r.nextDouble() * 2 - 1) * 10 * strength;
        final rot = (r.nextDouble() * 2 - 1) * 0.14 * strength;
        final wobbles = 4 + r.nextInt(4);
        // Rattle hard, settle to rest — damped oscillation.
        final env = math.sin(t * math.pi * wobbles) * (1 - t);
        return Transform.translate(
          offset: Offset(dx * env, dy * env),
          child:
              Transform.rotate(angle: rot * env, child: child),
        );
      },
    );
  }
}

/// Sunlight converging on the creature — warm streaks + glow
/// driven by live lux intensity (log-normalized in the
/// controller). Faint shimmer under a bulb, full bloom in sun.
class _SunRays extends StatefulWidget {
  const _SunRays({super.key, required this.intensity});

  /// 0..1 — CreatureController.sunIntensity.
  final double intensity;

  @override
  State<_SunRays> createState() => _SunRaysState();
}

class _SunRaysState extends State<_SunRays>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _phase,
      builder: (_, _) => CustomPaint(
        painter:
            _SunRaysPainter(widget.intensity, _phase.value),
      ),
    );
  }
}

class _SunRaysPainter extends CustomPainter {
  _SunRaysPainter(this.intensity, this.t);

  final double intensity;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0.01) return;
    final c = size.center(Offset.zero);
    final glowR = size.shortestSide * 0.42;

    // Warm core glow behind the creature.
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFD54F)
                .withValues(alpha: 0.28 * intensity),
            const Color(0xFFFFD54F).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: glowR)),
    );

    // Converging streaks — length and alpha flicker slowly so
    // the light feels alive rather than drawn.
    final rayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const rays = 14;
    for (var i = 0; i < rays; i++) {
      final ang = i / rays * 2 * math.pi + t * 0.35;
      final flick = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + i * 1.7);
      final outer = size.shortestSide *
          (0.62 + 0.12 * math.sin(i * 2.3 + t * 2 * math.pi));
      final inner = glowR * (0.55 + 0.25 * flick);
      rayPaint
        ..strokeWidth = 2.2 + 1.8 * flick * intensity
        ..color = Color.lerp(
          const Color(0xFFFFE082),
          Colors.white,
          flick * intensity,
        )!
            .withValues(alpha: intensity * (0.12 + 0.5 * flick));
      canvas.drawLine(
        c + Offset(math.cos(ang) * inner, math.sin(ang) * inner),
        c + Offset(math.cos(ang) * outer, math.sin(ang) * outer),
        rayPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_SunRaysPainter old) =>
      old.intensity != intensity || old.t != t;
}

/// Live sun status — lux readout, the 3s charge inside the
/// current drink, a ✓ flash each time a drink banks, and the
/// n/3 drink count for the trial.
class _SunBanner extends StatefulWidget {
  const _SunBanner({required this.controller});

  final CreatureController controller;

  @override
  State<_SunBanner> createState() => _SunBannerState();
}

class _SunBannerState extends State<_SunBanner> {
  Timer? _checkTimer;
  bool _showCheck = false;
  int _lastBank = 0;

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final soaking = ctrl.sunLux >= LuxService.soakLux;
    final draining = !soaking && ctrl.sunHoldProgress > 0;
    final barValue = ctrl.sunHoldProgress;

    // A drink just banked — flash the check over the bar slot
    // for a beat, then the next drink starts filling.
    if (ctrl.sunBankCount != _lastBank) {
      _lastBank = ctrl.sunBankCount;
      _showCheck = true;
      _checkTimer?.cancel();
      _checkTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) setState(() => _showCheck = false);
      });
    }
    final checked = _showCheck ||
        ctrl.trialSun >= CreatureController.evolveSunNeeded;

    final String status;
    if (!ctrl.trialActive) {
      status = 'fully grown — still loves the sun';
    } else if (!ctrl.sunTouched) {
      status = 'pet me once — then I\'ll drink';
    } else if (checked) {
      status = 'drink banked';
    } else if (soaking) {
      status =
          'drinking… ${(ctrl.sunHoldProgress * CreatureController.sunChunkSecs).toStringAsFixed(1)}s';
    } else if (draining) {
      status = 'losing light…';
    } else if (ctrl.sunLux > 0) {
      status = 'needs real sunlight';
    } else {
      status = 'no light sensor';
    }

    return Container(
      key: KeyConstants.sunBanner,
      margin: const EdgeInsets.only(top: 8),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFC107)
            .withValues(alpha: soaking ? 0.18 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFC107)
              .withValues(alpha: soaking ? 0.55 : 0.25),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                soaking ? Icons.wb_sunny : Icons.wb_twilight,
                size: 15,
                color: soaking
                    ? Colors.amber
                    : Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ctrl.sunLux > 0
                      ? '${ctrl.sunLux.round().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},')} lux · $status'
                      : status,
                  key: KeyConstants.luxValue,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                        color: soaking
                            ? Colors.amber
                            : Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                      ),
                ),
              ),
              if (ctrl.trialActive)
                Text(
                  '${ctrl.trialSun}/${CreatureController.evolveSunNeeded}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Drink banked → the bar becomes a check for a beat.
          // Otherwise it tweens its rise AND its slow drain.
          SizedBox(
            height: 18,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: checked
                  ? const Icon(Icons.check_circle,
                      key: ValueKey('sunCheck'),
                      size: 16,
                      color: Colors.amber)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 0,
                          end: barValue.clamp(0.0, 1.0),
                        ),
                        duration:
                            const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                        builder: (_, v, _) =>
                            LinearProgressIndicator(
                          key: KeyConstants.sunlightFillBar,
                          value: v,
                          minHeight: 5,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation(
                            soaking
                                ? Colors.amber
                                : draining
                                    ? Colors.orange
                                    : Colors.grey,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Connectivity + AI status chips — the "it works offline" proof.
/// Polls the native `system_status` channel every 2s; the Gemma
/// chip mirrors controller.loading (a real inference in flight).
class _StatusChips extends StatefulWidget {
  const _StatusChips({required this.controller});

  final CreatureController controller;

  @override
  State<_StatusChips> createState() => _StatusChipsState();
}

class _StatusChipsState extends State<_StatusChips> {
  static const _stream = EventChannel(
      'com.sprout.musaddiq625/system_status_stream');
  StreamSubscription? _sub;
  bool _wifi = false;
  bool _airplane = false;

  @override
  void initState() {
    super.initState();
    // Native pushes on every wifi/airplane change — live, no
    // polling. First event arrives immediately on listen.
    _sub = _stream.receiveBroadcastStream().listen(
      (m) {
        if (!mounted || m is! Map) return;
        setState(() {
          _wifi = m['wifi'] == true;
          _airplane = m['airplane'] == true;
        });
      },
      // No native channel (tests, desktop) — chips stay grey.
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Widget _chip({
    required Key key,
    required IconData icon,
    required String label,
    required bool on,
    required Color color,
  }) {
    final c = on ? color : Colors.grey;
    return Container(
      key: key,
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: on ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: c.withValues(alpha: on ? 0.5 : 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final thinking = widget.controller.loading;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _chip(
              key: KeyConstants.wifiChip,
              icon: _wifi ? Icons.wifi : Icons.wifi_off,
              label: _wifi ? 'Wi-Fi' : 'no Wi-Fi',
              on: _wifi,
              color: Colors.lightBlueAccent,
            ),
            const SizedBox(width: 8),
            _chip(
              key: KeyConstants.airplaneChip,
              icon: _airplane
                  ? Icons.airplanemode_active
                  : Icons.airplanemode_inactive,
              label: _airplane ? 'airplane' : 'radio on',
              on: _airplane,
              color: Colors.orangeAccent,
            ),
            const SizedBox(width: 8),
            _chip(
              key: KeyConstants.gemmaChip,
              icon: Icons.psychology,
              label: thinking ? 'Gemma…' : 'Gemma',
              on: thinking,
              color: Colors.greenAccent,
            ),
          ],
        );
      },
    );
  }
}

class _EvolveRing extends StatelessWidget {
  const _EvolveRing({super.key, required this.progress});

  /// 0..1 — from CreatureController.evolveProgress.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(132),
      painter: _EvolveRingPainter(progress),
    );
  }
}

class _EvolveRingPainter extends CustomPainter {
  _EvolveRingPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 4;
    // Track ring — faint sprout green.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0x334E9A3D)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    if (progress <= 0) return;
    // Progress arc — sweeps clockwise from the top.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = const Color(0xFF7ED957)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_EvolveRingPainter old) =>
      old.progress != progress;
}

class _StatBar extends StatelessWidget {
  const _StatBar({
    super.key,
    required this.emoji,
    required this.label,
    required this.value,
    required this.color,
  });

  final String emoji;
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(label,
                style: Theme.of(context).textTheme.labelMedium),
            const Spacer(),
            Text('${value.round()}%',
                style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: (value / 100).clamp(0, 1),
          minHeight: 8,
          backgroundColor: Colors.white12,
          valueColor: AlwaysStoppedAnimation(
            value > 50
                ? color
                : value > 20
                    ? Colors.orange
                    : Colors.red,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    super.key,
    required this.emoji,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badgeLabel,
  });

  final String emoji;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  /// Badge text on the button's emoji — '!' for a newly arrived
  /// quest, or the count of pending quests. Null = no badge.
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Badge(
                  isLabelVisible: badgeLabel != null,
                  label: Text(badgeLabel ?? ''),
                  child: Text(emoji,
                      style: const TextStyle(fontSize: 28)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style:
                              Theme.of(context).textTheme.titleMedium),
                      Text(subtitle,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              )),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fullscreen focus mode — the creature large, zero buttons.
/// Tap it to pet (or gentle-wake it when asleep), drag to spin
/// it like a figurine, double-tap to reset the spin, tap the
/// dark backdrop or press back to leave. Sun rays still bloom.
class _CreatureFocusPage extends StatefulWidget {
  const _CreatureFocusPage({required this.controller});

  final CreatureController controller;

  @override
  State<_CreatureFocusPage> createState() =>
      _CreatureFocusPageState();
}

class _CreatureFocusPageState extends State<_CreatureFocusPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _jiggle;
  late final Animation<double> _jiggleAnim;
  double _rot = 0;
  int _lastPet = 0;

  @override
  void initState() {
    super.initState();
    _jiggle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _jiggleAnim = Tween<double>(begin: -0.07, end: 0.07)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_jiggle);
    _lastPet = widget.controller.petCount;
    widget.controller.addListener(_onCtrl);
  }

  void _onCtrl() {
    final c = widget.controller;
    if (c.petCount != _lastPet) {
      _lastPet = c.petCount;
      if (mounted) _jiggle.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _jiggle.dispose();
    super.dispose();
  }

  /// Head badge for focus — same priority as the main page:
  /// 💥 shattered > 💭 dreaming > 💤 asleep > 💭 thinking.
  Widget? _focusBadge(CreatureController c) {
    if (c.dreamShattered) {
      return const Text('💥', style: TextStyle(fontSize: 40));
    }
    if (c.isDreaming) {
      return const Text('💭', style: TextStyle(fontSize: 40));
    }
    if (c.isAsleep) {
      return const Text('💤', style: TextStyle(fontSize: 40));
    }
    if (c.loading) {
      return const Text('💭', style: TextStyle(fontSize: 40));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F0A),
      body: GestureDetector(
        // Tapping anywhere but the creature itself leaves.
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.maybePop(context),
        child: ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final s = ctrl.state;
            return Stack(
              children: [
                // Ambient sun still blooms in focus mode.
                Positioned.fill(
                  child: IgnorePointer(
                    child: _SunRays(intensity: ctrl.sunIntensity),
                  ),
                ),
                Center(
                  child: GestureDetector(
                    // Generous hit area — near-misses still pet.
                    behavior: HitTestBehavior.opaque,
                    onTap: ctrl.pet,
                    onPanUpdate: (d) =>
                        setState(() => _rot += d.delta.dx * 0.02),
                    onDoubleTap: () =>
                        setState(() => _rot = 0),
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedBuilder(
                            animation: _jiggleAnim,
                            builder: (_, child) =>
                                Transform.rotate(
                              angle: _jiggleAnim.value + _rot,
                              child: child,
                            ),
                            child: Opacity(
                              opacity:
                                  ctrl.isAsleep ? 0.45 : 1,
                              child: Hero(
                                tag: 'creatureHero',
                                child: CreatureBody(
                                  controller: ctrl,
                                  size: 240,
                                ),
                              ),
                            ),
                          ),
                          if (_focusBadge(ctrl) != null)
                            Positioned(
                              top: -28,
                              right: -34,
                              child: _focusBadge(ctrl)!,
                            ),
                          if (ctrl.petCount > 0)
                            Positioned(
                              top: -24,
                              right: -8,
                              child: _HeartBurst(
                                key: ValueKey(ctrl.petCount),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 48,
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        Text(
                          '${s.displayName} · ${s.stage.label}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ctrl.isAsleep
                              ? 'asleep — tap ×${CreatureController.tapsToWake - ctrl.sleepTaps} to wake gently'
                              : 'tap to pet · drag to spin · double-tap to reset · tap outside to close',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
