import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_database.dart';
import 'models/llm_provider_config.dart';

class LlmConfigRepository {
  LlmConfigRepository({
    AppDatabase? database,
    FlutterSecureStorage? secureStorage,
  }) : _database = database ?? AppDatabase.instance,
       _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final AppDatabase _database;
  final FlutterSecureStorage _secureStorage;

  String _profileKey(int userId, String provider) =>
      'llm_profile_${userId}_${LlmProvider.normalize(provider)}';

  Future<LlmProviderConfig?> getForProvider(int userId, String provider) async {
    final value = await _secureStorage.read(key: _profileKey(userId, provider));
    if (value == null) return null;
    return LlmProviderConfig.fromMap(
      Map<String, Object?>.from(jsonDecode(value) as Map),
    );
  }

  Future<void> saveProvider(LlmProviderConfig config) async {
    final key = _profileKey(config.userId, config.provider);
    final encoded = jsonEncode(config.toSecureMap());
    await _secureStorage.write(key: key, value: encoded);
    if (await _secureStorage.read(key: key) != encoded) {
      throw StateError('安全存储写入失败，配置未保存');
    }
  }

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

    final legacy = LlmProviderConfig.fromMap(rows.first);
    final saved = await getForProvider(userId, legacy.provider);
    // Only clear the legacy plaintext after a verified secure write.
    if (legacy.apiKey.isNotEmpty) {
      if (saved == null) await saveProvider(legacy);
      await db.update(
        AppDatabase.tableLlmProviderConfigs,
        {'api_key': ''},
        where: 'id = ?',
        whereArgs: [legacy.id],
      );
    }
    return (saved ?? legacy).copyWith(id: legacy.id);
  }

  Future<LlmProviderConfig> save(LlmProviderConfig config) async {
    await _database.ensureSchemaReady();
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final existing = await getByUserId(config.userId);
    await saveProvider(config.copyWith(updatedAt: DateTime.parse(now)));

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
