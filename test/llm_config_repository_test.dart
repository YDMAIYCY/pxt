import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late LlmConfigRepository repository;
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    addTearDown(db.close);
    for (final id in [1, 2]) {
      await db.insert('users', {
        'id': id,
        'username': 'user$id',
        'password_hash': 'hash',
        'password_salt': 'salt',
        'display_name': '用户',
        'created_at': '2026-10-15',
        'updated_at': '2026-10-15',
      });
    }
    repository = LlmConfigRepository(database: app);
  });
  LlmProviderConfig config(String provider, String key, {int user = 1}) =>
      LlmProviderConfig.emptyForUser(user).copyWith(
        provider: provider,
        apiKey: key,
        baseUrl: 'https://example.com/v1',
        model: 'model-$provider',
        temperature: 0.8,
        responseFormat: 'json',
        displayName: '我的模型',
      );

  test(
    'provider and user profiles survive repository reopening without plaintext keys',
    () async {
      await repository.save(config('deepseek', 'deepseek-secret'));
      await repository.save(config('opencode_go', 'go-secret'));
      await repository.save(config('deepseek', 'user2-secret', user: 2));
      final reopened = LlmConfigRepository(database: app);
      expect((await reopened.getByUserId(1))?.provider, 'opencode_go');
      final deepseek = await reopened.getForProvider(1, 'deepseek');
      expect(deepseek?.apiKey, 'deepseek-secret');
      expect(deepseek?.temperature, 0.8);
      expect(deepseek?.responseFormat, 'json');
      expect(deepseek?.displayName, '我的模型');
      expect(
        (await reopened.getForProvider(2, 'deepseek'))?.apiKey,
        'user2-secret',
      );
      expect(
        (await db.query(
          'llm_provider_configs',
        )).every((r) => r['api_key'] == ''),
        isTrue,
      );
      await reopened.save(deepseek!);
      expect((await reopened.getByUserId(1))?.model, 'model-deepseek');
      expect(
        (await reopened.getForProvider(1, 'opencode_go'))?.apiKey,
        'go-secret',
      );
    },
  );

  test(
    'legacy key migrates only after secure write and retains row identity',
    () async {
      final old = config('minimax', 'legacy-key');
      final id = await db.insert('llm_provider_configs', {
        ...old.toDatabaseMap(),
        'api_key': 'legacy-key',
        'created_at': '2026-10-01',
      });
      final saved = await repository.getByUserId(1);
      expect(saved?.apiKey, 'legacy-key');
      expect(saved?.id, id);
      expect((await db.query('llm_provider_configs')).single['api_key'], '');
      expect((await repository.getByUserId(1))?.apiKey, 'legacy-key');
    },
  );

  test('secure storage failure leaves legacy key recoverable', () async {
    final old = config('minimax', 'legacy-key');
    await db.insert('llm_provider_configs', {
      ...old.toDatabaseMap(),
      'api_key': 'legacy-key',
      'created_at': '2026-10-01',
    });
    repository = LlmConfigRepository(
      database: app,
      secureStorage: _FailingStorage(),
    );
    await expectLater(
      repository.getByUserId(1),
      throwsA(isA<PlatformException>()),
    );
    expect(
      (await db.query('llm_provider_configs')).single['api_key'],
      'legacy-key',
    );
  });
}

class _FailingStorage extends FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw PlatformException(code: 'locked');
}
