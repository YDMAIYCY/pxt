import 'app_database.dart';
import 'models/llm_provider_config.dart';

class LlmConfigRepository {
  LlmConfigRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<LlmProviderConfig?> getByUserId(int userId) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final rows = await db.query(
      AppDatabase.tableLlmProviderConfigs,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return LlmProviderConfig.fromMap(rows.first);
  }

  Future<LlmProviderConfig> save(LlmProviderConfig config) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await getByUserId(config.userId);

    final data = {
      ...config.copyWith(updatedAt: DateTime.parse(now)).toDatabaseMap(),
      'updated_at': now,
    };

    if (existing == null) {
      final id = await db.insert(AppDatabase.tableLlmProviderConfigs, {
        ...data,
        'created_at': now,
      });
      final saved = await getByUserId(config.userId);
      if (saved == null) {
        throw StateError('LLM config write succeeded but readback failed: $id');
      }
      return saved;
    }

    await db.update(
      AppDatabase.tableLlmProviderConfigs,
      data,
      where: 'id = ?',
      whereArgs: [existing.id],
    );

    final saved = await getByUserId(config.userId);
    if (saved == null) {
      throw StateError('LLM config update succeeded but readback failed');
    }
    return saved;
  }
}
