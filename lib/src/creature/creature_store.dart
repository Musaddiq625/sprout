import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'creature_state.dart';

/// Persisted creature state + care log + quest progress.
/// Uses a dedicated sprout.db — separate from any previous journal DB.
class CreatureStore {
  CreatureStore._(this._db);

  final Database _db;

  static Future<CreatureStore> open({String? dbPath}) async {
    final docsPath =
        (await getApplicationDocumentsDirectory()).path;
    final db = await openDatabase(
      dbPath ?? p.join(docsPath, 'sprout.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE creature (
            id INTEGER PRIMARY KEY DEFAULT 1,
            energy REAL NOT NULL DEFAULT 30.0,
            hunger REAL NOT NULL DEFAULT 30.0,
            stage INTEGER NOT NULL DEFAULT 0,
            hatched_at INTEGER,
            streak INTEGER NOT NULL DEFAULT 0,
            last_care_date TEXT,
            last_updated INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE care_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            detail REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE quest_progress (
            quest_id TEXT PRIMARY KEY,
            count INTEGER NOT NULL DEFAULT 0,
            completed_at INTEGER
          )
        ''');
        // Seed the creature row
        await db.insert('creature', CreatureState(
          lastUpdated: DateTime.now(),
        ).toRow());
      },
    );
    return CreatureStore._(db);
  }

  Future<CreatureState> loadCreature() async {
    final rows = await _db.query('creature', where: 'id = 1');
    if (rows.isEmpty) {
      final state = CreatureState(lastUpdated: DateTime.now());
      await _db.insert('creature', state.toRow());
      return state;
    }
    return CreatureState.fromRow(rows.first);
  }

  Future<void> saveCreature(CreatureState state) =>
      _db.update('creature', state.toRow(), where: 'id = 1');

  /// Logs a care event (sunlight or grass feed).
  Future<void> logCare({
    required String type, // 'sunlight' | 'grass'
    double? detail,       // lux reading or green_ratio
  }) =>
      _db.insert('care_log', {
        'type': type,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'detail': detail,
      });

  /// All care events, newest first.
  Future<List<Map<String, Object?>>> careLog() =>
      _db.query('care_log', orderBy: 'created_at DESC');

  /// Total count for a care type.
  Future<int> careCount(String type) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) as c FROM care_log WHERE type = ?',
      [type],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Distinct care dates — used for streak calculation.
  Future<List<String>> careDates() async {
    final rows = await _db.rawQuery(
      "SELECT DISTINCT date(created_at / 1000, 'unixepoch') as d "
      'FROM care_log ORDER BY d DESC',
    );
    return rows.map((r) => r['d'] as String).toList();
  }

  /// Today's combo check: did both sunlight AND grass happen today?
  Future<bool> todayHadBoth() async {
    final today = DateTime.now();
    final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}'
        '-${today.day.toString().padLeft(2, '0')}';
    final rows = await _db.rawQuery(
      "SELECT COUNT(DISTINCT type) as c FROM care_log "
      "WHERE date(created_at / 1000, 'unixepoch') = ?",
      [dateStr],
    );
    return ((rows.first['c'] as int?) ?? 0) >= 2;
  }

  /// Quest progress — load all, update one.
  Future<Map<String, Map<String, Object?>>> allQuestProgress() async {
    final rows = await _db.query('quest_progress');
    return {
      for (final r in rows) r['quest_id'] as String: r,
    };
  }

  Future<void> upsertQuest(String questId,
      {required int count, int? completedAt}) =>
      _db.insert(
        'quest_progress',
        {
          'quest_id': questId,
          'count': count,
          'completed_at': completedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteAll() => _db.close().then(
      (_) => File(_db.path).delete().catchError((_) => File('')));
}
