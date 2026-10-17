import '../database/app_database.dart';

/// Foreground app usage, kept separate from focus records and check-in points.
class StudyActivityRepository {
  StudyActivityRepository({AppDatabase? database, DateTime Function()? now})
    : _database = database ?? AppDatabase.instance,
      _now = now ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _now;

  Future<void> recordUsage(int userId, DateTime from, DateTime to) async {
    if (to.isBefore(from)) return;
    final db = await _database.database;
    await db.transaction((txn) async {
      var cursor = from;
      do {
        final midnight = DateTime(cursor.year, cursor.month, cursor.day + 1);
        final end = to.isBefore(midnight) ? to : midnight;
        await txn.rawInsert(
          '''
          INSERT INTO study_activity_days(user_id, day, foreground_seconds)
          VALUES (?, ?, ?)
          ON CONFLICT(user_id, day) DO UPDATE SET
            foreground_seconds = foreground_seconds + excluded.foreground_seconds
        ''',
          [userId, _dayKey(cursor), end.difference(cursor).inSeconds],
        );
        cursor = end;
      } while (cursor.isBefore(to));
      // A visit at midnight belongs to the new day even before a second passes.
      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO study_activity_days(user_id, day, foreground_seconds)
        VALUES (?, ?, 0)
      ''',
        [userId, _dayKey(to)],
      );
    });
  }

  Future<int> todaySeconds(int userId) async {
    final rows = await (await _database.database).query(
      'study_activity_days',
      columns: ['foreground_seconds'],
      where: 'user_id = ? AND day = ?',
      whereArgs: [userId, _dayKey(_now())],
    );
    return rows.firstOrNull?['foreground_seconds'] as int? ?? 0;
  }

  String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
