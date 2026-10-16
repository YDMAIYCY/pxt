import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/cloud_identity_repository.dart';
import 'package:pxt1/community/knowledge_community_bridge.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/community/chat_outbox_repository.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/focus/repository/focus_repository.dart';

const cloudA = '10000000-0000-4000-8000-000000000001';
const cloudB = '20000000-0000-4000-8000-000000000002';

class DeliveryFixture extends CommunityRepository {
  DeliveryFixture(CloudIdentityRepository identity) : super(identity: identity);
  bool loseAcknowledgement = true;
  int uploads = 0;
  final storedTokens = <String>{};
  @override
  Future<void> sendMessage({
    required String conversation,
    required String token,
    required String body,
    String? image,
  }) async {
    storedTokens.add(token);
    if (loseAcknowledgement) {
      loseAcknowledgement = false;
      throw TimeoutException('simulated lost acknowledgement');
    }
  }

  @override
  Future<String> upload(
    String bucket,
    Uint8List bytes,
    String extension, {
    String? conversation,
    String? token,
  }) async {
    uploads++;
    return '$conversation/$cloudA/$token.png';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Directory dir;
  late Database db;
  late AuthRepository auth;
  late SupabaseClient client;
  late CloudIdentityRepository identity;
  var serverUser = cloudA;
  final authUser = <String, dynamic>{
    'aud': 'authenticated',
    'role': 'authenticated',
    'email': 'fixture@example.invalid',
    'app_metadata': {},
    'user_metadata': {},
    'created_at': '2026-10-16T00:00:00Z',
  };
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pxt-community-test-');
    app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: '${dir.path}/test.db',
    );
    db = await app.database;
    auth = AuthRepository(database: app);
    serverUser = cloudA;
    client = SupabaseClient(
      'https://fixture.supabase.co',
      'test-publishable',
      httpClient: MockClient((request) async {
        final user = {...authUser, 'id': serverUser};
        if (request.url.path.endsWith('/user')) {
          return http.Response(
            jsonEncode(user),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        final jwt =
            '${base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': serverUser, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000}))).replaceAll('=', '')}.fixture';
        return http.Response(
          jsonEncode({
            'access_token': jwt,
            'refresh_token': 'test-refresh',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': user,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    identity = CloudIdentityRepository(database: app, client: client);
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
    await dir.delete(recursive: true);
  });
  Future<int> local(String name) async {
    await auth.register(username: name, password: 'local-password');
    final result = await auth.login(username: name, password: 'local-password');
    return result.userId!;
  }

  Future<void> cloud(String uuid) async {
    serverUser = uuid;
    await client.auth.signInWithPassword(
      email: 'fixture@example.invalid',
      password: 'test-password',
    );
  }

  test(
    'legacy upgrade requires verified app login and keeps original local ownership',
    () async {
      final id = await local('legacy');
      final source = await SourceDocumentRepository(database: app)
          .createSourceDocument(
            userId: id,
            sourceType: 'gallery_image',
            imagePath: 'local-only.png',
            title: '私人原文',
          );
      await expectLater(
        identity.activateAuthenticatedUser(
          legacyUserId: (await auth.getCurrentUserProfile())?.id,
        ),
        throwsA(anything),
      );
      expect(await identity.linkedUuid(id), isNull);
      await cloud(cloudA);
      final profile = await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      expect(profile.id, id);
      expect(await identity.requireLinked(), cloudA);
      expect(
        (await db.query(
          'source_documents',
          where: 'id=?',
          whereArgs: [source.id],
        )).single['user_id'],
        id,
      );
      expect((await db.query('users')).length, 1);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      expect((await db.query('cloud_identity_links')).length, 1);
    },
  );
  test(
    'local account cannot adopt a different UUID or impersonate another local space',
    () async {
      final a = await local('local-a');
      await cloud(cloudA);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      await cloud(cloudB);
      await expectLater(identity.requireLinked(), throwsA(isA<CloudFailure>()));
      await expectLater(
        identity.activateAuthenticatedUser(
          legacyUserId: (await auth.getCurrentUserProfile())?.id,
        ),
        throwsA(isA<CloudFailure>()),
      );
      expect(await identity.linkedUuid(a), cloudA);
      await auth.logoutCurrentUser();
      final b = await local('local-b');
      await cloud(cloudA);
      await expectLater(
        identity.activateAuthenticatedUser(
          legacyUserId: (await auth.getCurrentUserProfile())?.id,
        ),
        throwsA(isA<CloudFailure>()),
      );
      expect(await identity.linkedUuid(b), isNull);
      expect((await auth.getCurrentUserProfile())!.id, b);
    },
  );
  test(
    'email sign-in restores the same linked local data after local logout',
    () async {
      final id = await local('existing');
      await cloud(cloudA);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      await auth.logoutCurrentUser();
      expect(await auth.getCurrentUserProfile(), isNull);
      expect(
        (await identity.activateAuthenticatedUser(
          legacyUserId: (await auth.getCurrentUserProfile())?.id,
        )).id,
        id,
      );
      expect((await db.query('users')).length, 1);
    },
  );
  test(
    'new cloud user gets an isolated local space without changing existing users',
    () async {
      final old = await local('old');
      await auth.logoutCurrentUser();
      await cloud(cloudB);
      final created = await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      expect(created.id, isNot(old));
      expect((await db.query('users')).length, 2);
      expect(await identity.linkedUuid(old), isNull);
    },
  );
  test(
    'community saving is idempotent, locally scoped and keeps readable provenance',
    () async {
      final id = await local('save');
      await cloud(cloudA);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      final lib =
          (await db.query(
                'knowledge_libraries',
                where: 'user_id=?',
                whereArgs: [id],
              )).first['id']
              as int;
      final bridge = KnowledgeCommunityBridge(
        database: app,
        identity: identity,
      );
      const question = {'id': 'q-fixture', 'title': '极限问题', 'body': '问题正文'};
      const answer = {'id': 'a-fixture', 'body': '答案正文'};
      final saved = await bridge.saveToLibrary(
        question: question,
        answer: answer,
        libraryId: lib,
      );
      expect(
        await bridge.saveToLibrary(
          question: question,
          answer: answer,
          libraryId: lib,
        ),
        saved,
      );
      expect(
        (await db.query('knowledge_cards')).single['content'],
        contains('q-fixture'),
      );
      expect((await db.query('source_documents')).single['user_id'], id);
      final other = await local('other');
      final foreignLib =
          (await db.query(
                'knowledge_libraries',
                where: 'user_id=?',
                whereArgs: [other],
              )).first['id']
              as int;
      await auth.login(username: 'save', password: 'local-password');
      await expectLater(
        bridge.saveToLibrary(
          question: {...question, 'id': 'other-q'},
          libraryId: foreignLib,
        ),
        throwsA(isA<CloudFailure>()),
      );
    },
  );
  test(
    'v23 to v24 migration preserves local users, sources and focus history',
    () async {
      final id = await local('migration');
      final source = await SourceDocumentRepository(database: app)
          .createSourceDocument(
            userId: id,
            sourceType: 'gallery_image',
            imagePath: 'keep.png',
            title: '保留文档',
          );
      await db.execute(
        "INSERT INTO checkin_records(user_id,date,study_seconds,pomodoro_count,points_earned,is_makeup,created_at) VALUES(?, '2026-10-16', 1800, 1, 30, 0, '2026-10-16T00:00:00Z')",
        [id],
      );
      for (final table in [
        'chat_outbox',
        'community_knowledge_links',
        'cloud_identity_links',
      ]) {
        await db.execute('DROP TABLE $table');
      }
      await db.execute('PRAGMA user_version=23');
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${dir.path}/test.db',
      );
      db = await app.database;
      expect(await db.getVersion(), 24);
      final backups = await dir
          .list()
          .where((f) => f.path.contains('.before-community-v23-'))
          .toList();
      expect(backups, hasLength(1));
      final snapshot = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await snapshot.getVersion(), 23);
      expect((await snapshot.query('users')).single['id'], id);
      expect(
        (await snapshot.query(
          'auth_sessions',
          where: 'logged_out_at IS NULL',
        )).single['user_id'],
        id,
      );
      await snapshot.close();
      expect((await db.query('users')).single['id'], id);
      expect((await db.query('source_documents')).single['id'], source.id);
      expect((await db.query('checkin_records')).single['study_seconds'], 1800);
      expect(await db.query('cloud_identity_links'), isEmpty);
    },
  );
  test(
    'outbox survives uncertain delivery and retries with the same token',
    () async {
      await local('outbox');
      await cloud(cloudA);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      final remote = DeliveryFixture(identity);
      final outbox = ChatOutboxRepository(database: app, community: remote);
      await outbox.enqueue('test-conversation', '消息内容');
      final first = (await outbox.pending('test-conversation')).single;
      await expectLater(
        outbox.deliver(first),
        throwsA(isA<TimeoutException>()),
      );
      final restored = ChatOutboxRepository(database: app, community: remote);
      final second = (await restored.pending('test-conversation')).single;
      expect(second['token'], first['token']);
      await restored.deliver(second);
      expect(remote.storedTokens.length, 1);
      expect(await restored.pending('test-conversation'), isEmpty);
      await cloud(cloudB);
      await expectLater(
        restored.pending('test-conversation'),
        throwsA(isA<CloudFailure>()),
      );
    },
  );
  test(
    'image outbox persists the upload receipt before retrying message delivery',
    () async {
      await local('image-outbox');
      await cloud(cloudA);
      await identity.activateAuthenticatedUser(
        legacyUserId: (await auth.getCurrentUserProfile())?.id,
      );
      final remote = DeliveryFixture(identity);
      final outbox = ChatOutboxRepository(database: app, community: remote);
      await outbox.enqueue(
        'test-conversation',
        '',
        image: Uint8List.fromList([1, 2, 3]),
        extension: 'png',
      );
      await expectLater(
        outbox.deliver((await outbox.pending('test-conversation')).single),
        throwsA(isA<TimeoutException>()),
      );
      final restored = ChatOutboxRepository(database: app, community: remote);
      await restored.deliver(
        (await restored.pending('test-conversation')).single,
      );
      expect(remote.uploads, 1);
      expect(remote.storedTokens.length, 1);
      expect(await restored.pending('test-conversation'), isEmpty);
    },
  );
  test(
    'learning streak excludes zero-duration manual check-ins and keeps original check-in streak',
    () async {
      final id = await local('streak');
      final now = DateTime(2026, 10, 16, 10);
      final focus = FocusRepository(database: app, now: () => now);
      Future<void> day(String date, int seconds) async {
        await db.insert('checkin_records', {
          'user_id': id,
          'date': date,
          'study_seconds': seconds,
          'pomodoro_count': 0,
          'points_earned': 0,
          'is_makeup': 0,
          'created_at': now.toUtc().toIso8601String(),
        });
      }

      await day('2026-10-16', 0);
      expect(await focus.fetchLearningStreak(id), 0);
      await day('2026-10-15', 600);
      await day('2026-10-14', 800);
      expect(await focus.fetchLearningStreak(id), 2);
      expect((await focus.fetchStats(id)).currentStreak, 3);
      expect((await focus.fetchStats(id)).todaySeconds, 0);
    },
  );
}
