import 'package:flutter/material.dart';

import '../ai/model_manager.dart';
import '../creature/creature_controller.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import 'creature_page.dart';
import 'widgets/name_sheet.dart';

/// First-launch only. Egg taps ×3 → hatch → CreaturePage.
/// pushReplacement so the user can't go back to an un-hatched egg.
class HatchPage extends StatefulWidget {
  const HatchPage({
    super.key,
    required this.store,
    required this.controller,
    required this.models,
  });

  final CreatureStore store;
  final CreatureController controller;
  final ModelManager models;

  @override
  State<HatchPage> createState() => _HatchPageState();
}

class _HatchPageState extends State<HatchPage>
    with SingleTickerProviderStateMixin {
  int _taps = 0;
  static const _tapsToHatch = 3;
  late final AnimationController _shake;
  late final Animation<double> _shakeAnim;

  static const _prompts = [
    'Something is inside.',
    'Tap the egg.',
    'Almost there…',
    'It\'s hatching!',
  ];

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _shakeAnim = Tween<double>(begin: -0.04, end: 0.04)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shake);
  }

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    if (_taps >= _tapsToHatch) return;
    setState(() => _taps++);
    _shake.forward(from: 0);
    if (_taps >= _tapsToHatch) {
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      await widget.controller.hatch();
      if (!mounted) return;
      // It hatched — let the user name it before meeting it.
      final name = await showNameSheet(context);
      if (!mounted) return;
      if (name != null) await widget.controller.setName(name);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CreaturePage(
            store: widget.store,
            controller: widget.controller,
            models: widget.models,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _taps / _tapsToHatch;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              GestureDetector(
                onTap: _onTap,
                child: AnimatedBuilder(
                  animation: _shakeAnim,
                  builder: (_, child) => Transform.rotate(
                    angle: _shakeAnim.value,
                    child: child,
                  ),
                  child: const Text(
                    '🥚',
                    key: KeyConstants.hatchEgg,
                    style: TextStyle(fontSize: 96),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _prompts[_taps.clamp(0, _prompts.length - 1)],
                key: KeyConstants.hatchPrompt,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80),
                child: LinearProgressIndicator(
                  key: KeyConstants.hatchCrackProgress,
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
