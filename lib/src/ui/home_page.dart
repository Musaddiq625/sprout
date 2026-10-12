import 'package:flutter/material.dart';

import '../ai/ai_service.dart';
import '../ai/model_manager.dart';
import '../creature/creature_controller.dart';
import '../creature/creature_state.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import 'creature_page.dart';
import 'hatch_page.dart';
import 'model_manager_page.dart';
import 'quest_page.dart';

/// Home: creature card entry point, streak chip, model status chip.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.store,
    required this.models,
    required this.controller,
  });

  final CreatureStore store;
  final ModelManager models;
  final CreatureController controller;

  @override
  Widget build(BuildContext context) {
    final ai = AiService.instance;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 32),
              Text(
                'Sprout',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                textAlign: TextAlign.center,
              ),
              Text(
                'a creature that needs you to go outside',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),

              // Creature entry card — an egg goes to the hatch
              // flow instead of the full creature page.
              Card(
                child: InkWell(
                  onTap: () {
                    controller.noteActivity();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => controller.state.isHatched
                            ? CreaturePage(
                                store: store,
                                controller: controller,
                                models: models,
                              )
                            : HatchPage(
                                store: store,
                                controller: controller,
                                models: models,
                              ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) => Opacity(
                            opacity: controller.isAsleep ? 0.35 : 1,
                            child: Text(
                              controller.isAsleep
                                  ? '💤'
                                  : controller.state.stage.emoji,
                              style: const TextStyle(fontSize: 48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListenableBuilder(
                                listenable: controller,
                                builder: (context, _) => Text(
                                  '${controller.state.displayName} '
                                  '${controller.state.mood.emoji}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge,
                                ),
                              ),
                              ListenableBuilder(
                                listenable: controller,
                                builder: (context, _) => Text(
                                  controller.isAsleep
                                      ? 'Fast asleep — tap gently or shake.'
                                      : '${controller.state.stage.label} · '
                                          'Lives on sunlight and grass.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Bottom row: streak + AI status + quests
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // '!' for a fresh arrival; otherwise the count
                  // of quests/wishes still pending.
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => Badge(
                      isLabelVisible: controller.newQuestAlert ||
                          controller.pendingQuestCount > 0,
                      label: Text(controller.newQuestAlert
                          ? '!'
                          : '${controller.pendingQuestCount}'),
                      child: ActionChip(
                        key: KeyConstants.streakChip,
                        avatar: const Icon(
                            Icons.local_fire_department,
                            size: 16),
                        label: Text(
                            '${controller.state.streak} × 15-min streak'),
                        onPressed: () {
                          controller.noteActivity();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  QuestPage(controller: controller),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    key: KeyConstants.modelStatusChip,
                    avatar: Icon(
                      ai.mode == 'real' ? Icons.memory : Icons.cloud_off,
                      size: 16,
                    ),
                    label: Text(
                        ai.mode == 'real' ? 'AI: on-device' : 'AI: demo'),
                    onPressed: () {
                      controller.noteActivity();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ModelManagerPage(manager: models),
                        ),
                      ).then((_) => ai.refresh());
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
