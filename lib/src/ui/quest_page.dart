import 'package:flutter/material.dart';

import '../creature/creature_controller.dart';
import '../key_constants.dart';

/// Quest log — grouped by chapter, locked chapters greyed out.
/// Tap a completed quest to re-read its story moment.
class QuestPage extends StatelessWidget {
  const QuestPage({super.key, required this.controller});

  final CreatureController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final quests = controller.quests;
        final chapters = <int>{};
        for (final q in quests) {
          chapters.add(q.chapter);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Quests')),
          body: quests.isEmpty
              ? const Center(child: Text('No quests yet.'))
              : ListView(
                  key: KeyConstants.questList,
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final chapter in chapters.toList()..sort()) ...[
                      _ChapterHeader(chapter: chapter, quests: quests),
                      const SizedBox(height: 8),
                      for (final q
                          in quests.where((q) => q.chapter == chapter))
                        _QuestTile(quest: q),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _ChapterHeader extends StatelessWidget {
  const _ChapterHeader({required this.chapter, required this.quests});

  final int chapter;
  final List<Quest> quests;

  bool get _unlocked {
    if (chapter == 1) return true;
    return quests
        .where((q) => q.chapter == chapter - 1)
        .every((q) => q.completed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            'Chapter $chapter',
            key: chapter == 1 ? KeyConstants.chapter1Header : null,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: _unlocked
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                ),
          ),
          const SizedBox(width: 8),
          if (!_unlocked)
            const Icon(Icons.lock, size: 14, color: Colors.grey),
        ],
      ),
    );
  }
}

class _QuestTile extends StatelessWidget {
  const _QuestTile({required this.quest});

  final Quest quest;

  @override
  Widget build(BuildContext context) {
    final done = quest.completed;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Text(
          done ? '✓' : '○',
          style: TextStyle(
            fontSize: 20,
            color: done ? Colors.greenAccent : Colors.grey,
          ),
        ),
        title: Text(
          quest.title,
          style: TextStyle(
            color: done ? null : Colors.grey[400],
            decoration: done ? null : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(quest.description,
                style: Theme.of(context).textTheme.bodySmall),
            if (!done)
              Text(
                '${quest.count} / ${quest.target}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
              ),
            if (done)
              GestureDetector(
                onTap: () => _showStory(context, quest),
                child: Text(
                  'Read the moment →',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  void _showStory(BuildContext context, Quest q) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(q.title),
        content: Text(
          q.storyUnlock,
          style: const TextStyle(fontStyle: FontStyle.italic),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
