/// Everything that persists about the creature — serialised to creature table.
/// Growth arc: blob+sprout → +flower (minor) → big body+arms (major)
/// → +flower crown (minor) → tree form (major, final).
enum CreatureStage { shell, sprout, bloom, grove, canopy, elder }

/// Derived from energy/hunger — never stored, always computed fresh.
enum CreatureMood { dormant, gloomy, content, happy }

extension CreatureMoodX on CreatureMood {
  String get emoji => switch (this) {
        CreatureMood.dormant => '😵',
        CreatureMood.gloomy => '😔',
        CreatureMood.content => '🙂',
        CreatureMood.happy => '😊',
      };

  String get label => switch (this) {
        CreatureMood.dormant => 'dormant',
        CreatureMood.gloomy => 'gloomy',
        CreatureMood.content => 'content',
        CreatureMood.happy => 'happy',
      };
}

extension CreatureStageX on CreatureStage {
  int get index => switch (this) {
        CreatureStage.shell => 0,
        CreatureStage.sprout => 1,
        CreatureStage.bloom => 2,
        CreatureStage.grove => 3,
        CreatureStage.canopy => 4,
        CreatureStage.elder => 5,
      };

  static CreatureStage fromIndex(int i) => switch (i) {
        1 => CreatureStage.sprout,
        2 => CreatureStage.bloom,
        3 => CreatureStage.grove,
        4 => CreatureStage.canopy,
        5 => CreatureStage.elder,
        _ => CreatureStage.shell,
      };

  /// The stage this one evolves into — null at the final form.
  CreatureStage? get next => switch (this) {
        CreatureStage.shell => CreatureStage.sprout,
        CreatureStage.sprout => CreatureStage.bloom,
        CreatureStage.bloom => CreatureStage.grove,
        CreatureStage.grove => CreatureStage.canopy,
        CreatureStage.canopy => CreatureStage.elder,
        CreatureStage.elder => null,
      };

  String get emoji => switch (this) {
        CreatureStage.shell => '🥚',
        CreatureStage.sprout => '🌱',
        CreatureStage.bloom => '🌸',
        CreatureStage.grove => '�',
        CreatureStage.canopy => '�',
        CreatureStage.elder => '🌳',
      };

  String get label => switch (this) {
        CreatureStage.shell => 'The Shell',
        CreatureStage.sprout => 'Sprout',
        CreatureStage.bloom => 'Bloom',
        CreatureStage.grove => 'Grove',
        CreatureStage.canopy => 'Canopy',
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
    this.lastCareAt,
    this.name,
    required this.lastUpdated,
  });

  final double energy; // 0..100
  final double hunger; // 0..100
  final CreatureStage stage;

  /// Set once when the egg hatches; never cleared.
  final DateTime? hatchedAt;

  /// Consecutive 15-minute blocks with at least one care event.
  final int streak;

  /// Timestamp of the last care event — used for streak expiry.
  /// Stored in the legacy `last_care_date` column as ISO-8601.
  final DateTime? lastCareAt;

  /// User-given name — set after hatching. null falls back to 'Sprout'.
  final String? name;

  /// Timestamp used for decay calculation.
  final DateTime lastUpdated;

  bool get isDormant => energy <= 0 || hunger <= 0;
  bool get isHatched => stage != CreatureStage.shell;

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : 'Sprout';

  /// Derived mood — the creature's face between interactions.
  CreatureMood get mood {
    if (isDormant) return CreatureMood.dormant;
    final low = energy < hunger ? energy : hunger;
    if (low < 25) return CreatureMood.gloomy;
    if (energy >= 70 && hunger >= 70) return CreatureMood.happy;
    return CreatureMood.content;
  }

  CreatureState copyWith({
    double? energy,
    double? hunger,
    CreatureStage? stage,
    DateTime? hatchedAt,
    int? streak,
    DateTime? lastCareAt,
    String? name,
    DateTime? lastUpdated,
  }) =>
      CreatureState(
        energy: energy ?? this.energy,
        hunger: hunger ?? this.hunger,
        stage: stage ?? this.stage,
        hatchedAt: hatchedAt ?? this.hatchedAt,
        streak: streak ?? this.streak,
        lastCareAt: lastCareAt ?? this.lastCareAt,
        name: name ?? this.name,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );

  Map<String, Object?> toRow() => {
        'energy': energy,
        'hunger': hunger,
        'stage': stage.index,
        'hatched_at': hatchedAt?.millisecondsSinceEpoch,
        'streak': streak,
        'last_care_date': lastCareAt?.toIso8601String(),
        'name': name,
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
        lastCareAt:
            DateTime.tryParse(row['last_care_date'] as String? ?? ''),
        name: row['name'] as String?,
        lastUpdated: DateTime.fromMillisecondsSinceEpoch(
            (row['last_updated'] as int?) ??
                DateTime.now().millisecondsSinceEpoch),
      );
}
