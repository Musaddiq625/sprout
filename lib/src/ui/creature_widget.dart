import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../creature/creature_controller.dart';
import '../creature/creature_state.dart';

/// The creature's living body — pure CustomPainter, no assets.
/// Breathes continuously, blinks on a timer, follows your finger
/// with its eyes, squashes like jelly on pets/shakes/evolves, and
/// grows a sprout on its head across stages. Fully offline.
class CreatureBody extends StatefulWidget {
  const CreatureBody({
    super.key,
    required this.controller,
    this.size = 104,
    this.stageOverride,
  });

  final CreatureController controller;
  final double size;

  /// Drawn instead of the real stage while set — used to show the
  /// pre-evolution form during the evolve shake phase.
  final CreatureStage? stageOverride;

  @override
  State<CreatureBody> createState() => _CreatureBodyState();
}

class _CreatureBodyState extends State<CreatureBody>
    with TickerProviderStateMixin {
  /// Master clock — drives breathing.
  late final AnimationController _time;

  /// Decaying squash oscillation (jelly) — strength set per event.
  late final AnimationController _squash;
  double _squashStrength = 0;

  /// Vertical hop arc.
  late final AnimationController _hop;
  double _hopStrength = 0;

  /// Blink — 170ms close-then-open, on a randomized timer.
  late final AnimationController _blink;
  Timer? _blinkTimer;

  /// Pupil orbit for dizziness.
  late final AnimationController _dizzy;

  /// Smoothed gaze target — lerped toward each frame.
  Offset _gaze = Offset.zero;
  Offset _gazeTarget = Offset.zero;

  int _lastPet = 0;
  int _lastSleepTaps = 0;
  int _lastDizzy = 0;
  int _lastEvolve = 0;
  int _lastSing = 0;
  bool _lastAsleep = false;

  @override
  void initState() {
    super.initState();
    _time = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
    _squash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _blink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
    );
    _dizzy = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scheduleBlink();
    widget.controller.addListener(_onCtrl);
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(
      Duration(milliseconds: 2200 + math.Random().nextInt(3200)),
      () {
        if (!mounted || widget.controller.isAsleep) {
          _scheduleBlink();
          return;
        }
        _blink.forward(from: 0).then((_) => _blink.reverse());
        _scheduleBlink();
      },
    );
  }

  /// Watch the controller's event counters → physical reactions.
  void _onCtrl() {
    final c = widget.controller;
    if (c.petCount != _lastPet) {
      _lastPet = c.petCount;
      _boing(0.55, hop: 0.5);
    }
    if (c.sleepTaps != _lastSleepTaps) {
      _lastSleepTaps = c.sleepTaps;
      _boing(0.35);
    }
    if (c.dizzyCount != _lastDizzy) {
      _lastDizzy = c.dizzyCount;
      _boing(0.9);
      _dizzy.forward(from: 0);
    }
    if (c.singCount != _lastSing) {
      _lastSing = c.singCount;
      _boing(0.4, hop: 0.7);
    }
    if (c.evolveCount != _lastEvolve) {
      _lastEvolve = c.evolveCount;
      _boing(0.7, hop: 1);
    }
    if (_lastAsleep && !c.isAsleep) _boing(0.5);
    _lastAsleep = c.isAsleep;
  }

  void _boing(double strength, {double hop = 0}) {
    _squashStrength = strength;
    _squash.forward(from: 0);
    if (hop > 0) {
      _hopStrength = hop;
      _hop.forward(from: 0);
    }
  }

  void _setGaze(Offset local) {
    final s = widget.size;
    _gazeTarget = Offset(
      ((local.dx - s / 2) / (s / 2)).clamp(-1.0, 1.0),
      ((local.dy - s / 2) / (s / 2)).clamp(-1.0, 1.0),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    _blinkTimer?.cancel();
    _time.dispose();
    _squash.dispose();
    _hop.dispose();
    _blink.dispose();
    _dizzy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (e) => _setGaze(e.localPosition),
      onPointerMove: (e) => _setGaze(e.localPosition),
      onPointerUp: (_) => _gazeTarget = Offset.zero,
      onPointerCancel: (_) => _gazeTarget = Offset.zero,
      child: AnimatedBuilder(
        // One rebuild per frame — cheap CustomPaint only.
        animation: Listenable.merge(
            [_time, _squash, _hop, _blink, _dizzy, c]),
        builder: (_, _) {
          // Ease the gaze toward its target for smooth eye drift.
          _gaze = Offset.lerp(_gaze, _gazeTarget, 0.18)!;
          // Decaying spring squash — jelly, not rubber.
          final sq = _squashStrength *
              (1 - _squash.value) *
              math.cos(_squash.value * math.pi * 3);
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _CreaturePainter(
              t: _time.value * 10,
              stage: widget.stageOverride ?? c.state.stage,
              mood: c.state.mood,
              asleep: c.isAsleep,
              dreaming: c.isDreaming,
              gaze: _gaze,
              blink: _blink.value,
              squash: sq,
              hop: math.sin(_hop.value * math.pi) * _hopStrength,
              dizzy: _dizzy.value,
            ),
          );
        },
      ),
    );
  }
}

class _CreaturePainter extends CustomPainter {
  _CreaturePainter({
    required this.t,
    required this.stage,
    required this.mood,
    required this.asleep,
    required this.dreaming,
    required this.gaze,
    required this.blink,
    required this.squash,
    required this.hop,
    required this.dizzy,
  });

  /// Continuous seconds.
  final double t;
  final CreatureStage stage;
  final CreatureMood mood;
  final bool asleep;
  final bool dreaming;

  /// -1..1 pointer direction for pupil tracking.
  final Offset gaze;

  /// 0 open .. 1 closed.
  final double blink;

  /// -1..1 jelly squash (positive = wide/short).
  final double squash;

  /// 0..1 vertical hop arc height.
  final double hop;

  /// 0..1 pupil-orbit while dizzy.
  final double dizzy;

  static const _body = Color(0xFF86C96B);
  static const _belly = Color(0xFFA8DE8C);
  static const _groveBody = Color(0xFF6FAF5B);
  static const _groveBelly = Color(0xFF94D17B);
  static const _elderBody = Color(0xFF5B8E4E);
  static const _elderBelly = Color(0xFF7FB26A);
  static const _leafGreen = Color(0xFF4E9A3D);
  static const _leafDark = Color(0xFF3E7C30);
  static const _eyeWhite = Color(0xFFFFFFFF);
  static const _pupil = Color(0xFF2E2621);
  static const _mouth = Color(0xFF4A3428);
  static const _cheek = Color(0x66FF8A80);
  static const _petal = Color(0xFFF48FB1);
  static const _flower = Color(0xFFFFD54F);

  /// Major stage-ups grow the whole body; minor ones accessorise.
  double get _bodyScale => switch (stage) {
        CreatureStage.grove || CreatureStage.canopy => 1.15,
        CreatureStage.elder => 1.30,
        _ => 1.0,
      };

  Color get _bodyColor => switch (stage) {
        CreatureStage.grove || CreatureStage.canopy => _groveBody,
        CreatureStage.elder => _elderBody,
        _ => _body,
      };

  Color get _bellyColor => switch (stage) {
        CreatureStage.grove || CreatureStage.canopy => _groveBelly,
        CreatureStage.elder => _elderBelly,
        _ => _belly,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cx = s / 2;
    final baseY = s * 0.88;

    // Breathing — slower + deeper while asleep.
    final breathAmp = asleep ? 0.030 : 0.016;
    final breathFreq = asleep ? 0.18 : 0.38;
    final breathe =
        math.sin(t * 2 * math.pi * breathFreq) * breathAmp;

    // Ground shadow — reacts to squash/hop.
    final shadowW = s * 0.30 * (1 + squash * 0.2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, baseY + s * 0.015),
        width: shadowW * (1 - hop * 0.4),
        height: s * 0.05 * (1 - hop * 0.4),
      ),
      Paint()..color = Colors.black26,
    );

    canvas.save();
    // Squash & stretch pivot at the feet — believable weight.
    canvas.translate(cx, baseY);
    canvas.scale(1 + squash * 0.16, 1 - squash * 0.14 + breathe);
    canvas.translate(0, -hop * s * 0.10);
    canvas.translate(-cx, -baseY);

    if (stage == CreatureStage.shell) {
      _drawEgg(canvas, s, cx, baseY);
      canvas.restore();
      return;
    }

    final bodyR = s * 0.30 * _bodyScale;
    final bodyCY = baseY - bodyR * 0.92;

    // Stubby arms — gained at the grove stage-up.
    if (stage.index >= CreatureStage.grove.index) {
      for (final side in [-1, 1]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
                cx + side * bodyR * 1.04, bodyCY + bodyR * 0.18),
            width: bodyR * 0.34,
            height: bodyR * 0.52,
          ),
          Paint()..color = _bodyColor,
        );
      }
    }

    // Little feet — elder form plants itself.
    if (stage == CreatureStage.elder) {
      for (final side in [-1, 1]) {
        canvas.drawOval(
          Rect.fromCenter(
            center:
                Offset(cx + side * bodyR * 0.42, baseY - s * 0.008),
            width: bodyR * 0.38,
            height: s * 0.045,
          ),
          Paint()..color = _leafDark,
        );
      }
    }

    // Body + belly.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, bodyCY),
          width: bodyR * 2.06,
          height: bodyR * 1.92),
      Paint()..color = _bodyColor,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, bodyCY + bodyR * 0.38),
          width: bodyR * 1.5,
          height: bodyR * 1.1),
      Paint()..color = _bellyColor,
    );

    _drawHeadpiece(canvas, s, cx, bodyCY - bodyR * 0.98);
    _drawFace(canvas, s, cx, bodyCY, bodyR);

    canvas.restore();
  }

  /// Shell stage — a simple egg with a faint crack.
  void _drawEgg(Canvas canvas, double s, double cx, double baseY) {
    final r = s * 0.26;
    final cy = baseY - r * 0.95;
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(cx, cy), width: r * 1.9, height: r * 2.2),
      Paint()..color = const Color(0xFFF3EFE4),
    );
    final crack = Path()
      ..moveTo(cx - r * 0.5, cy)
      ..lineTo(cx - r * 0.2, cy - r * 0.18)
      ..lineTo(cx + r * 0.05, cy + r * 0.1)
      ..lineTo(cx + r * 0.3, cy - r * 0.12)
      ..lineTo(cx + r * 0.5, cy);
    canvas.drawPath(
      crack,
      Paint()
        ..color = const Color(0xFFB8AE97)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012,
    );
  }

  /// What's growing on its head — the visible growth arc:
  /// sprout: stem + 2 leaves · bloom: + flower (minor)
  /// grove: leaf crest (major) · canopy: + flower crown (minor)
  /// elder: leafy canopy hair (major, final).
  void _drawHeadpiece(
      Canvas canvas, double s, double cx, double top) {
    final sway = math.sin(t * 1.6) * s * 0.008;
    switch (stage) {
      case CreatureStage.sprout:
      case CreatureStage.bloom:
        // Stem + two leaves; bloom adds a flower on the tip.
        final stemLen = s * (stage == CreatureStage.bloom
            ? 0.085
            : 0.055);
        final tip = Offset(cx + sway, top - stemLen);
        canvas.drawPath(
          Path()
            ..moveTo(cx, top)
            ..quadraticBezierTo(cx + sway, top - stemLen * 0.6,
                tip.dx, tip.dy),
          Paint()
            ..color = _leafDark
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.014
            ..strokeCap = StrokeCap.round,
        );
        final leafLen =
            s * (stage == CreatureStage.bloom ? 0.062 : 0.05);
        for (final dir in [-1, 1]) {
          _leaf(canvas, tip, leafLen, dir, s);
        }
        if (stage == CreatureStage.bloom) {
          _flowerHead(canvas, tip, s * 0.028);
        }
      case CreatureStage.grove:
      case CreatureStage.canopy:
        // Leaf crest — three leaves fanning from the crown.
        final base = Offset(cx + sway, top);
        for (var i = -1; i <= 1; i++) {
          final spread = i * 0.55;
          canvas.save();
          canvas.translate(base.dx, base.dy);
          canvas.rotate(spread);
          _leaf(canvas, Offset.zero, s * 0.075, 1, s);
          canvas.restore();
        }
        if (stage == CreatureStage.canopy) {
          // Flower crown — three small blooms across the crest.
          for (var i = -1; i <= 1; i++) {
            _flowerHead(
              canvas,
              base + Offset(i * s * 0.055, -s * 0.075),
              s * 0.020,
            );
          }
        }
      case CreatureStage.elder:
        // Tree canopy — a cluster of leaves crowns the head.
        final cy = top - s * 0.035;
        final blobs = [
          (dx: -0.075, dy: 0.010, r: 0.045, c: _leafGreen),
          (dx: -0.035, dy: -0.020, r: 0.050, c: _leafDark),
          (dx: 0.010, dy: -0.030, r: 0.052, c: _leafGreen),
          (dx: 0.055, dy: -0.015, r: 0.045, c: _leafDark),
          (dx: 0.075, dy: 0.012, r: 0.040, c: _leafGreen),
        ];
        for (final b in blobs) {
          canvas.drawCircle(
            Offset(cx + sway + b.dx * s, cy + b.dy * s),
            b.r * s,
            Paint()..color = b.c,
          );
        }
      case CreatureStage.shell:
        break;
    }
  }

  /// A five-petal flower with a warm center.
  void _flowerHead(
      Canvas canvas, Offset at, double r) {
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 5;
      canvas.drawCircle(
        at + Offset(math.cos(a) * r * 1.15,
            math.sin(a) * r * 1.15),
        r,
        Paint()..color = _petal,
      );
    }
    canvas.drawCircle(at, r * 0.55, Paint()..color = _flower);
  }

  /// One teardrop leaf arcing away from the sprout tip.
  void _leaf(Canvas canvas, Offset tip, double len, int dir,
      double s) {
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..quadraticBezierTo(
          tip.dx + dir * len * 0.9,
          tip.dy - len * 0.45,
          tip.dx + dir * len,
          tip.dy - len * 0.9,
        )
        ..quadraticBezierTo(
          tip.dx + dir * len * 0.55,
          tip.dy - len * 0.1,
          tip.dx,
          tip.dy,
        ),
      Paint()..color = _leafGreen,
    );
  }

  void _drawFace(
      Canvas canvas, double s, double cx, double cy, double r) {
    final eyeY = cy - r * 0.10;
    final eyeDX = r * 0.44;
    final eyeRW = s * 0.052;
    final eyeRH = s * 0.068;

    final closed = asleep || mood == CreatureMood.dormant;

    // Rosy cheeks when pleased.
    if (mood == CreatureMood.happy || dreaming) {
      for (final side in [-1, 1]) {
        canvas.drawCircle(
          Offset(cx + side * r * 0.62, cy + r * 0.22),
          s * 0.035,
          Paint()..color = _cheek,
        );
      }
    }

    for (final side in [-1, 1]) {
      final ex = cx + eyeDX * side;
      if (closed) {
        // Closed eye — shallow downward arc.
        canvas.drawPath(
          Path()
            ..moveTo(ex - eyeRW, eyeY)
            ..quadraticBezierTo(
                ex, eyeY + eyeRH * 0.7, ex + eyeRW, eyeY),
          Paint()
            ..color = _mouth
            ..style = PaintingStyle.stroke
            ..strokeWidth = s * 0.014
            ..strokeCap = StrokeCap.round,
        );
        continue;
      }
      canvas.save();
      canvas.translate(ex, eyeY);
      canvas.scale(1, 1 - blink);
      canvas.translate(-ex, -eyeY);
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(ex, eyeY),
            width: eyeRW * 2,
            height: eyeRH * 2),
        Paint()..color = _eyeWhite,
      );
      // Pupil: follows gaze; orbits while dizzy.
      final po = dizzy > 0 && dizzy < 1
          ? Offset(math.cos(dizzy * math.pi * 6),
                  math.sin(dizzy * math.pi * 6)) *
              s *
              0.02
          : gaze * s * 0.016;
      final pr =
          s * 0.026 * (mood == CreatureMood.happy ? 1.15 : 1);
      canvas.drawCircle(
          Offset(ex + po.dx, eyeY + po.dy),
          pr,
          Paint()..color = _pupil);
      // Sparkle — the dot of life.
      canvas.drawCircle(
        Offset(ex + po.dx - pr * 0.3, eyeY + po.dy - pr * 0.3),
        pr * 0.3,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }

    _drawMouth(canvas, s, cx, cy + r * 0.34, r);
  }

  void _drawMouth(
      Canvas canvas, double s, double cx, double my, double r) {
    final mw = s * 0.10;
    final paint = Paint()
      ..color = _mouth
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.016
      ..strokeCap = StrokeCap.round;

    if (asleep || mood == CreatureMood.dormant) {
      // Tiny sleeping 'o' (dreaming smiles instead).
      if (dreaming) {
        canvas.drawPath(
          Path()
            ..moveTo(cx - mw * 0.5, my)
            ..quadraticBezierTo(
                cx, my + mw * 0.6, cx + mw * 0.5, my),
          paint,
        );
      } else {
        canvas.drawCircle(Offset(cx, my), mw * 0.28, paint);
      }
      return;
    }
    switch (mood) {
      case CreatureMood.happy:
        // Open smile — filled wedge.
        canvas.drawPath(
          Path()
            ..moveTo(cx - mw, my - mw * 0.15)
            ..quadraticBezierTo(
                cx, my + mw * 1.15, cx + mw, my - mw * 0.15)
            ..quadraticBezierTo(
                cx, my + mw * 0.35, cx - mw, my - mw * 0.15)
            ..close(),
          Paint()..color = _mouth,
        );
      case CreatureMood.content:
        canvas.drawPath(
          Path()
            ..moveTo(cx - mw * 0.7, my)
            ..quadraticBezierTo(
                cx, my + mw * 0.8, cx + mw * 0.7, my),
          paint,
        );
      case CreatureMood.gloomy:
        // Small downturned arc.
        canvas.drawPath(
          Path()
            ..moveTo(cx - mw * 0.55, my + mw * 0.3)
            ..quadraticBezierTo(cx, my - mw * 0.35,
                cx + mw * 0.55, my + mw * 0.3),
          paint,
        );
      case CreatureMood.dormant:
        break;
    }
  }

  @override
  bool shouldRepaint(_CreaturePainter old) => true;
}

/// A still render of a stage — same painter as the living body,
/// used by the Story timeline so history shows the creature's
/// real forms instead of emoji.
class CreaturePreview extends StatelessWidget {
  const CreaturePreview({
    super.key,
    required this.stage,
    this.size = 28,
  });

  final CreatureStage stage;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _CreaturePainter(
        t: 0,
        stage: stage,
        mood: CreatureMood.content,
        asleep: false,
        dreaming: false,
        gaze: Offset.zero,
        blink: 0,
        squash: 0,
        hop: 0,
        dizzy: 0,
      ),
    );
  }
}
