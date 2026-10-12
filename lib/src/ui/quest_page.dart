import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../ai/models.dart';
import '../creature/creature_controller.dart';
import '../key_constants.dart';
import '../vision/image_prep.dart';
import 'widgets/scan_overlay.dart';

/// Quest log — grouped by chapter, locked chapters greyed out —
/// plus the creature's own invented wishes. Tap a completed quest
/// to re-read its story moment.
class QuestPage extends StatefulWidget {
  const QuestPage({super.key, required this.controller});

  final CreatureController controller;

  @override
  State<QuestPage> createState() => _QuestPageState();
}

class _QuestPageState extends State<QuestPage> {
  @override
  void initState() {
    super.initState();
    // Idempotent — also refreshes the wishes list.
    widget.controller.loadQuests();
    // Opening this page means the new-quest alert has been seen.
    widget.controller.markQuestsSeen();
  }

  /// Photo wish verification: pick a photo, then a scanning
  /// dialog shows the creature "looking at it" while the vision
  /// model judges it against the creature's own question.
  Future<void> _verifyWish(Wish wish) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Camera'),
              onTap: () =>
                  Navigator.pop(sheetCtx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () =>
                  Navigator.pop(sheetCtx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final prepared = ImagePrep.prepare(bytes);
      if (prepared == null) {
        _snack('Could not read that photo.');
        return;
      }
      // The dialog owns the scan → verdict flow; it returns
      // true/false on verdict, null on error/dismiss.
      final ok = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _VerifyDialog(
          controller: widget.controller,
          wish: wish,
          image: prepared,
          preview: bytes,
        ),
      );
      if (!mounted || ok == null) return;
      _snack(ok
          ? 'Wish complete — it loved it!'
          : 'Not quite — that isn\'t it.');
    } catch (_) {
      if (mounted) _snack('Could not verify the photo.');
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );

  String _kindEmoji(String kind) => switch (kind) {
        'sunlight' => '☀️',
        'grass' => '🌿',
        'walk' => '🐾',
        _ => '📷',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final quests = widget.controller.quests;
        final wishes = widget.controller.wishes;
        final chapters = <int>{};
        for (final q in quests) {
          chapters.add(q.chapter);
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Quests')),
          body: quests.isEmpty && wishes.isEmpty
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
                    if (wishes.isNotEmpty) ...[
                      Row(
                        children: [
                          Text(
                            'Wishes',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                          ),
                          const SizedBox(width: 6),
                          const Text('💫',
                              style: TextStyle(fontSize: 14)),
                        ],
                      ),
                      Text(
                        'Things it invented for you',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Column(
                        key: KeyConstants.wishList,
                        children: [
                          for (final w in wishes)
                            _WishTile(
                              wish: w,
                              kindEmoji: _kindEmoji(w.kind),
                              onVerify: w.kind == 'photo' &&
                                      !w.completed &&
                                      w.verifyPrompt != null
                                  ? () => _verifyWish(w)
                                  : null,
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// One creature-invented wish. Photo wishes get a 📷 verify
/// button; other kinds complete automatically on the matching
/// care/walk.
class _WishTile extends StatelessWidget {
  const _WishTile({
    required this.wish,
    required this.kindEmoji,
    this.onVerify,
  });

  final Wish wish;
  final String kindEmoji;
  final VoidCallback? onVerify;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Text(kindEmoji,
            style: const TextStyle(fontSize: 22)),
        title: Text(
          wish.title,
          style: TextStyle(
            color:
                wish.completed ? null : Colors.grey[400],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wish.description,
                style: Theme.of(context).textTheme.bodySmall),
            if (wish.isEvolve && !wish.completed)
              Text(
                'Evolution trial — complete to evolve',
                key: KeyConstants.evolveQuestChip,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                      color: Colors.greenAccent,
                    ),
              ),
            if (wish.kind == 'walk' && !wish.completed)
              Text(
                'Take it outside for a walk',
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
        trailing: wish.completed
            ? const Text('✓',
                style: TextStyle(
                    fontSize: 20, color: Colors.greenAccent))
            : onVerify != null
                ? IconButton(
                    key: KeyConstants.wishShowPhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    tooltip: 'Show it',
                    onPressed: onVerify,
                  )
                : null,
      ),
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

/// The "creature is looking" moment — shows the photo under a
/// sweeping scanline with the wish's question while the vision
/// model judges it. Pops with true/false on verdict, null on
/// error or timeout.
class _VerifyDialog extends StatefulWidget {
  const _VerifyDialog({
    required this.controller,
    required this.wish,
    required this.image,
    required this.preview,
  });

  final CreatureController controller;
  final Wish wish;
  final PreparedImage image;

  /// Raw bytes for the on-screen preview (pre-decode).
  final Uint8List preview;

  @override
  State<_VerifyDialog> createState() => _VerifyDialogState();
}

enum _Verdict { scanning, passed, failed, error }

class _VerifyDialogState extends State<_VerifyDialog> {
  _Verdict _verdict = _Verdict.scanning;
  int _phase = 0;
  Timer? _phaseTimer;

  /// The "thinking out loud" ticker — cycles while the model runs.
  static const _phases = [
    'Looking closely…',
    'Checking the details…',
    'Comparing with my wish…',
  ];

  @override
  void initState() {
    super.initState();
    _phaseTimer = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => setState(
          () => _phase = (_phase + 1) % _phases.length),
    );
    _run();
  }

  Future<void> _run() async {
    try {
      final ok = await widget.controller
          .verifyPhotoWish(widget.wish, widget.image)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      setState(() =>
          _verdict = ok ? _Verdict.passed : _Verdict.failed);
    } catch (_) {
      if (!mounted) return;
      setState(() => _verdict = _Verdict.error);
    }
    // Hold the verdict on screen a beat so it reads, then pop.
    Timer(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      Navigator.pop(
          context,
          _verdict == _Verdict.passed
              ? true
              : _verdict == _Verdict.failed
                  ? false
                  : null);
    });
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.controller.state.displayName;
    return PopScope(
      // Back gesture is disabled while the model is judging —
      // the dialog auto-pops right after the verdict.
      canPop: _verdict != _Verdict.scanning,
      child: Dialog(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The creature's own question — the AI is visibly
            // doing the judging.
            Text(
              widget.wish.verifyPrompt ?? 'Is this it?',
              key: KeyConstants.wishVerifyPrompt,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: ScanOverlay(
                  active: _verdict == _Verdict.scanning,
                  child: Image.memory(
                    widget.preview,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _verdict == _Verdict.scanning
                  ? Row(
                      key: const ValueKey('scan'),
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(
                            '$name is ${_phases[_phase]}'),
                      ],
                    )
                  : Text(
                      key: ValueKey(_verdict),
                      switch (_verdict) {
                        _Verdict.passed =>
                          '✓ $name sees it!',
                        _Verdict.failed =>
                          '✗ That\'s not it…',
                        _ => '✗ Couldn\'t verify that photo',
                      },
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _verdict == _Verdict.passed
                            ? Colors.greenAccent
                            : Colors.redAccent,
                      ),
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

