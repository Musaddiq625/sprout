import 'dart:async';

import 'package:flutter/material.dart';

import '../creature/creature_controller.dart';
import '../creature/lux_service.dart';
import '../key_constants.dart';

/// Sunlight feed flow: lux sensor → hold ≥ 3000 lux for 5s → feed.
/// Falls back to a hold button when no sensor or indoor light.
class SunlightPage extends StatefulWidget {
  const SunlightPage({super.key, required this.controller});

  final CreatureController controller;

  @override
  State<SunlightPage> createState() => _SunlightPageState();
}

class _SunlightPageState extends State<SunlightPage> {
  double _lux = 0;
  double _peakLux = 0;
  int _holdSeconds = 0;
  bool _sensorActive = false;
  bool _fed = false;
  StreamSubscription<double>? _sub;
  Timer? _holdTimer;
  Timer? _sensorCheckTimer;

  static const _holdTarget = 5; // seconds at ≥ threshold

  @override
  void initState() {
    super.initState();
    _sub = LuxService.stream.listen(
      (lux) {
        if (!mounted) return;
        setState(() {
          _lux = lux;
          _sensorActive = true;
          if (lux > _peakLux) _peakLux = lux;
        });
        _onLuxReading(lux);
      },
      onError: (_) => setState(() => _sensorActive = false),
    );
    // If no readings arrive in 2s, assume no sensor.
    _sensorCheckTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_sensorActive) setState(() {});
    });
  }

  void _onLuxReading(double lux) {
    if (_fed) return;
    if (LuxService.isOutdoor(lux)) {
      _holdTimer ??= Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _holdSeconds++);
        if (_holdSeconds >= _holdTarget) {
          t.cancel();
          _holdTimer = null;
          _feed();
        }
      });
    } else {
      // Dropped below threshold — reset the hold.
      _holdTimer?.cancel();
      _holdTimer = null;
      if (_holdSeconds > 0 && mounted) setState(() => _holdSeconds = 0);
    }
  }

  void _feed() {
    if (_fed || !mounted) return;
    _fed = true;
    _sub?.cancel();
    widget.controller.feedSunlight(_peakLux);
    Navigator.pop(context);
  }

  /// Fallback: "Hold Steady" button — honour system for sensor-less devices.
  void _onHoldSteady() {
    if (_fed) return;
    _holdTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _holdSeconds++);
      if (_holdSeconds >= _holdTarget) {
        t.cancel();
        _holdTimer = null;
        _feed();
      }
    });
  }

  void _onHoldRelease() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_fed && mounted) setState(() => _holdSeconds = 0);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _holdTimer?.cancel();
    _sensorCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _holdSeconds / _holdTarget;
    final outdoor = _sensorActive && LuxService.isOutdoor(_lux);
    final showFallback = !_sensorActive || _lux < 500;

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(key: KeyConstants.sunlightBackButton),
        title: const Text('Feed Sunlight'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Lux reading
              const Text('☀️', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 8),
              if (_sensorActive)
                Text(
                  '${_lux.round()} lux',
                  key: KeyConstants.luxValue,
                  style: Theme.of(context).textTheme.headlineSmall,
                )
              else
                Text(
                  'sensor not detected',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
              const SizedBox(height: 24),

              // Hold progress
              LinearProgressIndicator(
                key: KeyConstants.sunlightFillBar,
                value: progress.clamp(0, 1),
                minHeight: 12,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation(
                  outdoor ? const Color(0xFFFFC107) : Colors.grey,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              const SizedBox(height: 8),
              Text(
                outdoor
                    ? 'Hold steady… $_holdSeconds / $_holdTarget s'
                    : _sensorActive
                        ? 'Not bright enough — go outside'
                        : 'Waiting for sensor…',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const Spacer(),

              // Fallback hold button
              if (showFallback)
                GestureDetector(
                  onLongPressStart: (_) => _onHoldSteady(),
                  onLongPressEnd: (_) => _onHoldRelease(),
                  child: Container(
                    key: KeyConstants.holdSteadyButton,
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text(
                        'Hold to feed (no sun)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Sprout needs natural light. Open a window or step outside.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
