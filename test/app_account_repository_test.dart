import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/community/app_account_repository.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/cloud_identity_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryAuthStorage extends GotrueAsyncStorage {
  final _values = <String, String>{};
  @override
  Future<String?> getItem({required String key}) async => _values[key];
  @override
  Future<void> setItem({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

// Isolated SDK/SQLite contract checks. These are not live Supabase acceptance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  const first = '10000000-0000-4000-8000-000000000001';
  const second = '20000000-0000-4000-8000-000000000002';
  late Directory directory;
  late AppDatabase database;
  late Database db;
  late AuthRepository local;
  late SupabaseClient client;
  late AppAccountRepository accounts;
  var serverId = first;
  var nickname = '测试同学';
  var confirmEmail = false;
  var rejectIdentity = false;
  var rejectRefresh = false;
  var missingCommunity = false;
  final requests = <String>[];

  Map<String, dynamic> user() => {
    'id': serverId,
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': serverId == first ? 'a@example.invalid' : 'b@example.invalid',
    'app_metadata': {},
    'user_metadata': {'nickname': nickname},
    'created_at': '2026-10-16T00:00:00Z',
  };
  Map<String, dynamic> session() {
    String segment(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    return {
      'access_token':
          '${segment({'alg': 'HS256'})}.${segment({'sub': serverId, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})}.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': user(),
    };
  }

  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pxt-account-contract-');
    database = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: '${directory.path}/account.db',
    );
    db = await database.database;
    local = AuthRepository(database: database);
    serverId = first;
    nickname = '测试同学';
    confirmEmail = rejectIdentity = rejectRefresh = missingCommunity = false;
    requests.clear();
    client = SupabaseClient(
      'https://fixture.supabase.co',
      'fixture-public',
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: _MemoryAuthStorage(),
      ),
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        if (request.url.path.endsWith('/signup') ||
            request.url.path.endsWith('/token')) {
          final body = jsonDecode(request.body) as Map;
          if (body['password'] == 'wrong-password') {
            return json({
              'code': 'invalid_credentials',
              'msg': 'Invalid credentials',
            }, 400);
          }
          if (body['refresh_token'] != null && rejectRefresh) {
            return json({
              'code': 'refresh_token_not_found',
              'msg': 'Invalid refresh token',
            }, 400);
          }
          if (body['email'] != null) {
            serverId = (body['email'] as String).startsWith('b@')
                ? second
                : first;
          }
          if (body['data'] != null) {
            nickname = body['data']['nickname'] as String;
          }
          if (request.url.path.endsWith('/signup') && confirmEmail) {
            return json({'user': user()});
          }
          return json(session());
        }
        if (request.url.path.endsWith('/user')) {
          return rejectIdentity
              ? json({'msg': 'Invalid token'}, 401)
              : json(user());
        }
        if (request.url.path.endsWith('/logout')) return http.Response('', 204);
        if (request.url.path.endsWith('/profiles')) {
          if (missingCommunity) {
            return json({'code': 'PGRST205', 'message': 'missing'}, 404);
          }
          return json({
            'id': serverId,
            'public_id': 'ZX-fixture',
            'nickname': nickname,
            'bio': '',
          });
        }
        return json([]);
      }),
    );
    accounts = AppAccountRepository(database: database, client: client);
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<int> oldUser() async {
    await local.register(username: '原账号', password: 'old-password');
    return (await local.login(
      username: '原账号',
      password: 'old-password',
    )).userId!;
  }

  test('新用户一次注册自动建立真实身份对应的本地学习空间', () async {
    final profile = await accounts.register(
      email: 'a@example.invalid',
      password: 'new-password',
      nickname: '新同学甲',
    );
    expect(profile!.primaryName, '新同学甲');
    expect((await local.getCurrentUserProfile())!.id, profile.id);
    expect(
      await CloudIdentityRepository(
        database: database,
        client: client,
      ).requireLinked(),
      first,
    );
    expect(await db.query('users'), hasLength(1));
    expect(await db.query('knowledge_libraries'), hasLength(1));
    expect(requests.where((path) => path.endsWith('/signup')), hasLength(1));
    expect(requests.where((path) => path.endsWith('/token')), isEmpty);
  });

  test('一次邮箱登录即可使用社区身份，恢复时不要求再次登录', () async {
    final profile = await accounts.signIn(
      email: 'a@example.invalid',
      password: 'new-password',
    );
    requests.clear();
    expect((await accounts.restoreSession())!.id, profile.id);
    expect(requests, isEmpty);
    expect(await accounts.legacyUser(), isNull);
    expect(
      await db.query('auth_sessions', where: 'logged_out_at IS NULL'),
      hasLength(1),
    );
  });

  test('普通登录不静默接管原账号，切换回来恢复各自资料', () async {
    final oldId = await oldUser();
    final source = await SourceDocumentRepository(database: database)
        .createSourceDocument(
          userId: oldId,
          sourceType: 'gallery_image',
          imagePath: 'keep-private.png',
          title: '原资料',
        );
    final a = await accounts.signIn(
      email: 'a@example.invalid',
      password: 'new-password',
    );
    final b = await accounts.signIn(
      email: 'b@example.invalid',
      password: 'new-password',
    );
    expect(a.id, isNot(oldId));
    expect(b.id, isNot(a.id));
    expect(
      (await accounts.signIn(
        email: 'a@example.invalid',
        password: 'new-password',
      )).id,
      a.id,
    );
    expect(
      (await db.query(
        'source_documents',
        where: 'id=?',
        whereArgs: [source.id],
      )).single['user_id'],
      oldId,
    );
    expect(await db.query('users'), hasLength(3));
  });

  test('旧账号在同一个登录流程完成升级，保留 ID 和全部原资料', () async {
    final oldId = await oldUser();
    await SourceDocumentRepository(database: database).createSourceDocument(
      userId: oldId,
      sourceType: 'gallery_image',
      imagePath: 'old.png',
      title: '保留文档',
    );
    final profile = await accounts.signIn(
      email: 'a@example.invalid',
      password: 'new-password',
      legacyUserId: oldId,
    );
    expect(profile.id, oldId);
    expect(await db.query('users'), hasLength(1));
    expect((await db.query('source_documents')).single['user_id'], oldId);
    expect(await accounts.legacyUser(), isNull);
    await expectLater(
      accounts.openLegacySpace(username: '原账号', password: 'old-password'),
      throwsA(isA<CloudFailure>()),
    );
  });

  test('等待邮箱确认时保留旧会话，确认后的首次登录自动完成升级', () async {
    final oldId = await oldUser();
    confirmEmail = true;
    expect(
      await accounts.register(
        email: 'a@example.invalid',
        password: 'new-password',
        nickname: '原同学',
        legacyUserId: oldId,
      ),
      isNull,
    );
    expect((await local.getCurrentUserProfile())!.id, oldId);
    expect(await db.query('cloud_identity_links'), isEmpty);
    expect(
      (await accounts.signIn(
        email: 'a@example.invalid',
        password: 'new-password',
        legacyUserId: oldId,
      )).id,
      oldId,
    );
    expect(await db.query('users'), hasLength(1));
  });

  test('邮箱未确认的新注册不创建假本地登录', () async {
    confirmEmail = true;
    expect(
      await accounts.register(
        email: 'a@example.invalid',
        password: 'new-password',
        nickname: '待确认',
      ),
      isNull,
    );
    expect(await db.query('users'), isEmpty);
    expect(await local.getCurrentUserProfile(), isNull);
  });

  test('密码错误不改变已有本机会话或资料', () async {
    final oldId = await oldUser();
    await expectLater(
      accounts.signIn(email: 'a@example.invalid', password: 'wrong-password'),
      throwsA(isA<AuthException>()),
    );
    expect((await local.getCurrentUserProfile())!.id, oldId);
    expect(await db.query('cloud_identity_links'), isEmpty);
  });

  test('服务器身份验证失败不能建立 UUID 映射或登录', () async {
    rejectIdentity = true;
    await expectLater(
      accounts.signIn(email: 'a@example.invalid', password: 'new-password'),
      throwsA(isA<AuthException>()),
    );
    expect(await db.query('cloud_identity_links'), isEmpty);
    expect(await db.query('users'), isEmpty);
    expect(client.auth.currentSession, isNull);
  });

  test('社区结构缺失不能破坏已经成功的账号登录', () async {
    missingCommunity = true;
    final profile = await accounts.signIn(
      email: 'a@example.invalid',
      password: 'new-password',
    );
    expect((await local.getCurrentUserProfile())!.id, profile.id);
    expect(client.auth.currentUser!.id, first);
  });

  test('失效刷新凭据回到统一登录，同时仍可离线查看原资料', () async {
    final profile = await accounts.signIn(
      email: 'a@example.invalid',
      password: 'new-password',
    );
    client.auth.currentSession!.expiresAt = 1;
    rejectRefresh = true;
    expect(await accounts.restoreSession(), isNull);
    expect((await accounts.offlineUser())!.id, profile.id);
    expect(await db.query('users'), hasLength(1));
  });

  test('不能指定另一位本地用户 ID 来接管资料', () async {
    final oldId = await oldUser();
    await expectLater(
      accounts.signIn(
        email: 'a@example.invalid',
        password: 'new-password',
        legacyUserId: oldId + 1,
      ),
      throwsA(isA<CloudFailure>()),
    );
    expect(requests, isEmpty);
    expect((await local.getCurrentUserProfile())!.id, oldId);
  });
}
