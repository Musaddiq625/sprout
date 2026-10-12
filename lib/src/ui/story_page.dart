import 'package:flutter/material.dart';

import '../creature/creature_controller.dart';
import '../creature/creature_state.dart';
import '../creature/creature_store.dart';
import '../key_constants.dart';
import 'creature_widget.dart';

/// The creature's life story — when it hatched and evolved, and every
/// care event it received. Fully local: growth_log + care_log.
class StoryPage extends StatefulWidget {
  const StoryPage({
    super.key,
    required this.controller,
    required this.store,
  });

  final CreatureController controller;
  final CreatureStore store;

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  List<Map<String, Object?>> _growth = [];
  List<Map<String, Object?>> _care = [];
  int _suns = 0;
  int _grass = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      widget.store.stageHistory(),
      widget.store.careLog(),
      widget.store.careCount('sunlight'),
      widget.store.careCount('grass'),
    ]).then((r) {
      if (mounted) {
        setState(() {
          _growth = r[0] as List<Map<String, Object?>>;
          _care = r[1] as List<Map<String, Object?>>;
          _suns = r[2] as int;
          _grass = r[3] as int;
          _loaded = true;
        });
      }
    });
  }

  String _fmt(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String _age() {
    final hatched = widget.controller.state.hatchedAt;
    if (hatched == null) return '';
    final d = DateTime.now().difference(hatched);
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours % 24}h old';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m old';
    return '${d.inMinutes}m old';
  }

  /// Care history grouped by stage era. Events since the last
  /// stage-up belong to the *open* trial — they render flat so
  /// the user sees them counting toward the next evolve. Events
  /// from earlier eras are collapsed into one group per stage,
  /// each introduced by its "evolved →" divider.
  List<Widget> _groupedCare() {
    // Growth boundaries (ASC → convert to the DESC timeline order).
    final bounds = _growth.reversed
        .map((r) => (
              stage: r['stage'] as int,
              at: r['reached_at'] as int,
            ))
        .toList();
    // The newest boundary = when the current stage began.
    final currentStart =
        bounds.isEmpty ? 0 : bounds.first.at;

    final widgets = <Widget>[];
    var i = 0;
    final care = _care.take(50).toList();

    // 1) Current era — ungrouped.
    while (i < care.length &&
        (care[i]['created_at'] as int) >= currentStart) {
      widgets.add(_careTile(care[i]));
      i++;
    }

    // 2) Each older era: evolve divider + collapsed group.
    for (var b = 0; b < bounds.length && i < care.length; b++) {
      final bound = bounds[b];
      final next = b + 1 < bounds.length
          ? bounds[b + 1].at
          : 0; // era runs [next, bound)
      final era = <Map<String, Object?>>[];
      while (i < care.length &&
          (care[i]['created_at'] as int) < bound.at &&
          (care[i]['created_at'] as int) >= next) {
        era.add(care[i]);
        i++;
      }
      final became = CreatureStage.values[bound.stage];
      // The era below this divider is the stage it WAS during
      // those events — the next-older boundary's stage (or, for
      // the oldest era, the stage that boundary began).
      final eraStage = CreatureStage.values[
          b + 1 < bounds.length ? bounds[b + 1].stage : bound.stage];
      widgets.add(_EraDivider(stage: became, at: bound.at));
      if (era.isNotEmpty) {
        widgets.add(_EraGroup(stage: eraStage, rows: era));
      }
    }
    // Anything older than the first boundary (shouldn't happen —
    // eggs can't be fed) — show flat rather than drop it.
    while (i < care.length) {
      widgets.add(_careTile(care[i]));
      i++;
    }
    return widgets;
  }

  Widget _careTile(Map<String, Object?> row) =>
      _CareTileStatic(row: row);

  @override
  Widget build(BuildContext context) {
    final s = widget.controller.state;
    return Scaffold(
      appBar: AppBar(title: Text('${s.displayName}’s story')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Summary ──────────────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CreaturePreview(stage: s.stage, size: 44),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(s.stage.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium),
                              if (s.hatchedAt != null)
                                Text(
                                  'hatched ${_fmt(s.hatchedAt!.millisecondsSinceEpoch)} · ${_age()}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                              const SizedBox(height: 6),
                              Text(
                                '☀️ $_suns   🌿 $_grass   🔥 ${s.streak}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Growth timeline ──────────────────────────────────
                Text('Growth',
                    style:
                        Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_growth.isEmpty)
                  Text('Not hatched yet.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic))
                else
                  Column(
                    key: KeyConstants.growthTimeline,
                    children: [
                      for (var i = 0; i < _growth.length; i++)
                        _GrowthTile(
                          row: _growth[i],
                          first: i == 0,
                          last: i == _growth.length - 1,
                          fmt: _fmt,
                        ),
                    ],
                  ),
                const SizedBox(height: 20),

                // ── Care history ─────────────────────────────────────
                Text('Care history',
                    style:
                        Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (_care.isEmpty)
                  Text('No care events yet.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontStyle: FontStyle.italic))
                else
                  Card(
                    key: KeyConstants.careLogList,
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.stretch,
                      children: _groupedCare(),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

/// Divider inside care history — marks the stage-up that ended
/// the era below it.
class _EraDivider extends StatelessWidget {
  const _EraDivider({required this.stage, required this.at});

  final CreatureStage stage;
  final int at;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(at);
    final when = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          const SizedBox(width: 8),
          CreaturePreview(stage: stage, size: 20),
          const SizedBox(width: 6),
          Text(
            'became ${stage.label} · $when',
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.primary,
                    ),
          ),
          const SizedBox(width: 8),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

/// One collapsed era of care history — taps open to reveal the
/// feeds that powered that stage-up.
class _EraGroup extends StatelessWidget {
  const _EraGroup({required this.stage, required this.rows});

  final CreatureStage stage;
  final List<Map<String, Object?>> rows;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      dense: true,
      tilePadding:
          const EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.zero,
      leading: CreaturePreview(stage: stage, size: 22),
      title: Text(
        'as ${stage.label} · ${rows.length} '
        'event${rows.length == 1 ? '' : 's'}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        for (final row in rows)
          _CareTileStatic(row: row),
      ],
    );
  }
}

/// Static variant of the care tile for use inside collapsed
/// groups (the live list uses the state-class method).
class _CareTileStatic extends StatelessWidget {
  const _CareTileStatic({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    final type = row['type'] as String;
    final detail = row['detail'] as double?;
    final (emoji, label) = switch (type) {
      'sunlight' => (
          '☀️',
          'sunlight${detail != null ? ' · ${detail.round()} lux' : ''}'
        ),
      'grass' => (
          '🌿',
          'grass${detail != null ? ' · ${(detail * 100).round()}% green' : ''}'
        ),
      'walk' => (
          '🐾',
          'walk${detail != null ? ' · ${detail.round()} steps' : ''}'
        ),
      _ => ('🧪', 'debug care'),
    };
    final dt = DateTime.fromMillisecondsSinceEpoch(
        row['created_at'] as int);
    final when = '${dt.day.toString().padLeft(2, '0')}.'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    return ListTile(
      dense: true,
      leading: Text(emoji, style: const TextStyle(fontSize: 20)),
      title: Text(label),
      trailing: Text(
        when,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
      ),
    );
  }
}

/// One row of the growth timeline — emoji + stage + when + the
/// streak that earned it, linked by a vertical line.
class _GrowthTile extends StatelessWidget {
  const _GrowthTile({
    required this.row,
    required this.first,
    required this.last,
    required this.fmt,
  });

  final Map<String, Object?> row;
  final bool first;
  final bool last;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final stage =
        CreatureStage.values[row['stage'] as int];
    final lineColor =
        Theme.of(context).colorScheme.onSurfaceVariant;
    return IntrinsicHeight(
      child: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: Container(
                  width: 2,
                  color: first
                      ? Colors.transparent
                      : lineColor.withValues(alpha: 0.4),
                ),
              ),
              CreaturePreview(stage: stage, size: 26),
              Expanded(
                child: Container(
                  width: 2,
                  color: last
                      ? Colors.transparent
                      : lineColor.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(stage.label,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall),
                  Text(
                    '${fmt(row['reached_at'] as int)}'
                    '${(row['streak'] as int) > 0 ? ' · streak ${row['streak']}' : ''}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
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
        ],
      ),
    );
  }
}
