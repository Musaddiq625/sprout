import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'creature_state.dart';

/// Persisted creature state + care log + quest progress + meal photos.
/// Uses a dedicated sprout.db — separate from any previous journal DB.
class CreatureStore {
  CreatureStore._(this._db, this._docsDir);

  final Database _db;
  final String _docsDir;

  static Future<CreatureStore> open({String? dbPath}) async {
    final docsPath =
        (await getApplicationDocumentsDirectory()).path;
    final db = await openDatabase(
      dbPath ?? p.join(docsPath, 'sprout.db'),
      version: 5,
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
            name TEXT,
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
        await db.execute('''
          CREATE TABLE meals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            path TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            green_ratio REAL
          )
        ''');
        await db.execute('''
          CREATE TABLE growth_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            stage INTEGER NOT NULL,
            streak INTEGER NOT NULL,
            reached_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE wishes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT NOT NULL,
            kind TEXT NOT NULL,
            verify_prompt TEXT,
            created_at INTEGER NOT NULL,
            completed_at INTEGER,
            is_evolve INTEGER NOT NULL DEFAULT 0
          )
        ''');
        // Seed the creature row
        await db.insert('creature', CreatureState(
          lastUpdated: DateTime.now(),
        ).toRow());
      },
      onUpgrade: (db, oldV, _) async {
        if (oldV < 2) {
          await db.execute('ALTER TABLE creature ADD COLUMN name TEXT');
          await db.execute('''
            CREATE TABLE meals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              path TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              green_ratio REAL
            )
          ''');
        }
        if (oldV < 3) {
          await db.execute('''
            CREATE TABLE growth_log (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              stage INTEGER NOT NULL,
              streak INTEGER NOT NULL,
              reached_at INTEGER NOT NULL
            )
          ''');
          // Backfill one anchor row for an already-grown creature so
          // its history isn't empty.
          final c = await db.query('creature', where: 'id = 1');
          if (c.isNotEmpty && ((c.first['stage'] as int?) ?? 0) > 0) {
            await db.insert('growth_log', {
              'stage': c.first['stage'],
              'streak': (c.first['streak'] as int?) ?? 0,
              'reached_at': (c.first['hatched_at'] as int?) ??
                  (c.first['last_updated'] as int?) ??
                  DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
        if (oldV < 4) {
          await db.execute('''
            CREATE TABLE wishes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              description TEXT NOT NULL,
              kind TEXT NOT NULL,
              verify_prompt TEXT,
              created_at INTEGER NOT NULL,
              completed_at INTEGER
            )
          ''');
        }
        if (oldV < 5) {
          // Wishes can now be evolution trials.
          await db.execute(
              'ALTER TABLE wishes ADD COLUMN is_evolve INTEGER '
              'NOT NULL DEFAULT 0');
          // Stage set changed to 6: {shell 0, hatchling 1, sprout 2,
          // bloom 3, elder 4} → {shell 0, sprout 1, bloom 2, grove 3,
          // canopy 4, elder 5}. Remap by visual parity — the creature
          // keeps the form it had.
          const remap = 'CASE '
              'WHEN stage >= 4 THEN 5 '
              'WHEN stage = 3 THEN 2 '
              'WHEN stage >= 1 THEN 1 '
              'ELSE 0 END';
          await db.execute(
              'UPDATE creature SET stage = $remap');
          await db.execute(
              'UPDATE growth_log SET stage = $remap');
        }
      },
    );
    return CreatureStore._(db, docsPath);
  }

  /// Directory where meal photos are written — fully local, no sync.
  String get mealsDir => p.join(_docsDir, 'meals');

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

  /// Distinct 15-minute care blocks (created_at ~/ 900000), newest
  /// first — used for streak calculation.
  Future<List<int>> carePeriods() async {
    final rows = await _db.rawQuery(
      'SELECT DISTINCT (created_at / 900000) as p '
      'FROM care_log ORDER BY p DESC',
    );
    return rows.map((r) => r['p'] as int).toList();
  }

  /// Persists a meal photo to `docs/meals/` and logs its row —
  /// the creature's memory of grass it has eaten. Local only.
  /// Returns the saved path, or null if the write failed (the feed
  /// still counts — a missing photo never blocks care).
  Future<String?> logMeal(Uint8List bytes, {double? greenRatio}) async {
    try {
      final dir = Directory(mealsDir);
      await dir.create(recursive: true);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, '$ts.jpg'));
      await file.writeAsBytes(bytes, flush: true);
      await _db.insert('meals', {
        'path': file.path,
        'created_at': ts,
        'green_ratio': greenRatio,
      });
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// All meal photo rows, newest first.
  Future<List<Map<String, Object?>>> meals() =>
      _db.query('meals', orderBy: 'created_at DESC');

  /// Days that had BOTH sunlight and grass care — counted by local
  /// day. Each qualifying day counts once, no matter how many feeds.
  Future<int> comboDays() async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) as c FROM ("
      "SELECT date(created_at / 1000, 'unixepoch', 'localtime') AS d "
      "FROM care_log "
      "WHERE type IN ('sunlight', 'grass') "
      "GROUP BY d "
      "HAVING COUNT(DISTINCT type) >= 2)",
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Logs a stage reached (hatch, each evolution) — the creature's
  /// growth history. [streak] records the streak that earned it.
  Future<void> logStage({
    required int stage,
    required int streak,
    int? reachedAt,
  }) =>
      _db.insert('growth_log', {
        'stage': stage,
        'streak': streak,
        'reached_at':
            reachedAt ?? DateTime.now().millisecondsSinceEpoch,
      });

  /// Every stage reached, oldest first — the creature's life story.
  Future<List<Map<String, Object?>>> stageHistory() =>
      _db.query('growth_log', orderBy: 'reached_at ASC');

  /// Timestamp of the most recent stage change (or hatch) — the
  /// start of the current evolution trial. Null if never logged.
  Future<int?> latestStageChange() async {
    final rows = await _db.query('growth_log',
        orderBy: 'reached_at DESC', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['reached_at'] as int?;
  }

  /// Care events since [fromMs] — sunlight, grass and walks all
  /// count as feeds for the evolution trial ('debug' never does).
  Future<int> feedsSince(int fromMs) async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) as c FROM care_log "
      "WHERE type IN ('sunlight', 'grass', 'walk') "
      "AND created_at >= ?",
      [fromMs],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Sunlight feeds since [fromMs] — the no-quest evolution path
  /// needs 3 of these.
  Future<int> sunFeedsSince(int fromMs) async {
    final rows = await _db.rawQuery(
      "SELECT COUNT(*) as c FROM care_log "
      "WHERE type = 'sunlight' AND created_at >= ?",
      [fromMs],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// A creature-invented quest ("wish") — stored so it survives
  /// restarts. [kind]: sunlight | grass | photo | walk.
  /// [verifyPrompt] is the yes/no question the vision model answers
  /// for photo wishes. [isEvolve] marks the wish as the current
  /// evolution trial quest — completing it unlocks the stage-up.
  Future<int> addWish({
    required String title,
    required String description,
    required String kind,
    String? verifyPrompt,
    bool isEvolve = false,
  }) =>
      _db.insert('wishes', {
        'title': title,
        'description': description,
        'kind': kind,
        'verify_prompt': verifyPrompt,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'is_evolve': isEvolve ? 1 : 0,
      });

  /// Uncompleted wishes, optionally filtered to one kind.
  Future<List<Map<String, Object?>>> openWishes([String? kind]) =>
      _db.query('wishes',
          where: 'completed_at IS NULL'
              '${kind != null ? ' AND kind = ?' : ''}',
          whereArgs: kind != null ? [kind] : null,
          orderBy: 'created_at DESC');

  /// All wishes, newest first.
  Future<List<Map<String, Object?>>> allWishes() =>
      _db.query('wishes', orderBy: 'created_at DESC');

  Future<void> deleteWish(int id) =>
      _db.delete('wishes', where: 'id = ?', whereArgs: [id]);

  Future<void> completeWish(int id) => _db.update(
        'wishes',
        {'completed_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [id],
      );

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

  /// Wipes every table and reseeds a fresh shell creature — the
  /// store stays open and usable (unlike [deleteAll], which is
  /// for teardown).
  Future<void> resetAll() async {
    for (final t in const [
      'care_log',
      'growth_log',
      'quest_progress',
      'wishes',
      'meals',
      'creature',
    ]) {
      await _db.delete(t);
    }
    await _db.insert(
        'creature',
        CreatureState(lastUpdated: DateTime.now()).toRow());
    final dir = Directory(mealsDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  Future<void> deleteAll() async {
    await _db.close().then(
        (_) => File(_db.path).delete().catchError((_) => File('')));
    final dir = Directory(mealsDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }
}
