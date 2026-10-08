import 'package:flutter/material.dart';

import '../ai/ai_service.dart';
import '../ai/model_manager.dart';
import '../creature/creature_controller.dart';
import '../creature/creature_state.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import 'grass_page.dart';
import 'model_manager_page.dart';
import 'quest_page.dart';
import 'sunlight_page.dart';

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

class _CreaturePageState extends State<CreaturePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.controller.loadQuests();
      await widget.controller.loadGreeting();
    });
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
              child: Column(
                children: [
                  // ── Status row ─────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Chip(
                        key: KeyConstants.streakChip,
                        avatar: const Icon(Icons.local_fire_department,
                            size: 16),
                        label: Text('${s.streak}-day streak'),
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
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ModelManagerPage(manager: widget.models),
                          ),
                        ).then((_) => ai.refresh()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Stat bars ──────────────────────────────────────────
                  _StatBar(
                    key: KeyConstants.energyBar,
                    emoji: '☀️',
                    label: 'Energy',
                    value: s.energy,
                    color: const Color(0xFFFFC107),
                  ),
                  const SizedBox(height: 12),
                  _StatBar(
                    key: KeyConstants.hungerBar,
                    emoji: '🌿',
                    label: 'Hunger',
                    value: s.hunger,
                    color: const Color(0xFF4CAF50),
                  ),
                  const SizedBox(height: 32),

                  // ── Creature ──────────────────────────────────────────
                  Text(
                    s.stage.emoji,
                    key: KeyConstants.creatureEmoji,
                    style: const TextStyle(fontSize: 80),
                  ),
                  Text(
                    s.stage.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (s.isDormant)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(
                        label: const Text('dormant'),
                        avatar: const Icon(Icons.bedtime, size: 14),
                        backgroundColor: Colors.orange.withValues(alpha: 0.15),
                      ),
                    ),
                  const SizedBox(height: 24),

                  // ── Dialogue ───────────────────────────────────────────
                  Container(
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
                  const Spacer(),

                  // ── Actions ────────────────────────────────────────────
                  _ActionButton(
                    key: KeyConstants.feedSunlightButton,
                    emoji: '☀️',
                    label: 'Feed Sunlight',
                    subtitle: 'Hold phone outside in the sun',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SunlightPage(controller: ctrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionButton(
                    key: KeyConstants.feedGrassButton,
                    emoji: '🌿',
                    label: 'Feed Grass',
                    subtitle: 'Show it a patch of green',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GrassPage(
                          controller: ctrl,
                          store: widget.store,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ActionButton(
                    key: KeyConstants.questsButton,
                    emoji: '📜',
                    label: 'Quests',
                    subtitle: 'Story milestones and streaks',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => QuestPage(controller: ctrl),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
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
  });

  final String emoji;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

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
                Text(emoji, style: const TextStyle(fontSize: 28)),
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
