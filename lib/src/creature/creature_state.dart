/// Everything that persists about the creature — serialised to creature table.
enum CreatureStage { shell, hatchling, sprout, bloom, elder }

extension CreatureStageX on CreatureStage {
  int get index => switch (this) {
        CreatureStage.shell => 0,
        CreatureStage.hatchling => 1,
        CreatureStage.sprout => 2,
        CreatureStage.bloom => 3,
        CreatureStage.elder => 4,
      };

  static CreatureStage fromIndex(int i) => switch (i) {
        1 => CreatureStage.hatchling,
        2 => CreatureStage.sprout,
        3 => CreatureStage.bloom,
        4 => CreatureStage.elder,
        _ => CreatureStage.shell,
      };

  String get emoji => switch (this) {
        CreatureStage.shell => '🥚',
        CreatureStage.hatchling => '🐣',
        CreatureStage.sprout => '🌱',
        CreatureStage.bloom => '🌸',
        CreatureStage.elder => '🌳',
      };

  String get label => switch (this) {
        CreatureStage.shell => 'The Shell',
        CreatureStage.hatchling => 'Hatchling',
        CreatureStage.sprout => 'Sprout',
        CreatureStage.bloom => 'Bloom',
        CreatureStage.elder => 'Elder',
      };
}

class CreatureState {
  const CreatureState({
    this.energy = 30.0,
    this.hunger = 30.0,
    this.stage = CreatureStage.shell,
    this.hatchedAt,
    this.streak = 0,
    this.lastCareDate,
    required this.lastUpdated,
  });

  final double energy; // 0..100
  final double hunger; // 0..100
  final CreatureStage stage;

  /// Set once when the egg hatches; never cleared.
  final DateTime? hatchedAt;

  /// Consecutive days with at least one care event.
  final int streak;

  /// 'YYYY-MM-DD' string — used for streak increment.
  final String? lastCareDate;

  /// Timestamp used for decay calculation.
  final DateTime lastUpdated;

  bool get isDormant => energy <= 0 || hunger <= 0;
  bool get isHatched => stage != CreatureStage.shell;

  String get dateKey => lastCareDate ?? '';

  CreatureState copyWith({
    double? energy,
    double? hunger,
    CreatureStage? stage,
    DateTime? hatchedAt,
    int? streak,
    String? lastCareDate,
    DateTime? lastUpdated,
  }) =>
      CreatureState(
        energy: energy ?? this.energy,
        hunger: hunger ?? this.hunger,
        stage: stage ?? this.stage,
        hatchedAt: hatchedAt ?? this.hatchedAt,
        streak: streak ?? this.streak,
        lastCareDate: lastCareDate ?? this.lastCareDate,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  Map<String, Object?> toRow() => {
        'energy': energy,
        'hunger': hunger,
        'stage': stage.index,
        'hatched_at': hatchedAt?.millisecondsSinceEpoch,
        'streak': streak,
        'last_care_date': lastCareDate,
        'last_updated': lastUpdated.millisecondsSinceEpoch,
      };

  factory CreatureState.fromRow(Map<String, Object?> row) => CreatureState(
        energy: (row['energy'] as num?)?.toDouble() ?? 30.0,
        hunger: (row['hunger'] as num?)?.toDouble() ?? 30.0,
        stage: CreatureStageX.fromIndex((row['stage'] as int?) ?? 0),
        hatchedAt: row['hatched_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['hatched_at'] as int)
            : null,
        streak: (row['streak'] as int?) ?? 0,
        lastCareDate: row['last_care_date'] as String?,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
            (row['last_updated'] as int?) ??
                DateTime.now().millisecondsSinceEpoch),
      );
}
