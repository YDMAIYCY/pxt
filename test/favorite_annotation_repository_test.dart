import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/favorite_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  late FavoriteRepository repository;
  late Directory directory;
  late int favoriteId;
  const now = '2026-10-17T01:00:00.000Z';
  const body = 'alpha beta alpha 😀';
  const annotation = FavoriteAnnotation(
    id: 'second-alpha',
    start: 11,
    end: 16,
    quote: 'alpha',
    color: '黄色',
    note: '只给第二处做笔记',
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'pxt-favorite-annotations-',
    );
    app = await AppDatabase.openForTesting(
      databaseFactoryFfi,
      path: '${directory.path}/favorites.db',
    );
    db = await app.database;
    for (final id in [1, 2]) {
      await db.insert('users', {
        'id': id,
        'username': 'learner$id',
        'password_hash': 'fixture',
        'password_salt': 'fixture',
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('knowledge_libraries', {
        'id': id,
        'user_id': id,
        'name': '测试库$id',
        'created_at': now,
        'updated_at': now,
      });
    }
    await db.insert('auth_sessions', {
      'user_id': 1,
      'session_token': 'fixture-session',
      'created_at': now,
    });
    final source = await SourceDocumentRepository(database: app)
        .createSourceDocument(
          userId: 1,
          libraryId: 1,
          sourceType: 'gallery_import',
          imagePath: '/fixture/source.png',
          title: '测试资料',
        );
    await db.insert('review_outlines', {
      'id': 1,
      'document_id': source.id,
      'title': '复习提纲',
      'outline_text': body,
      'created_at': now,
    });
    repository = FavoriteRepository(database: app);
    await repository.toggleFavorite(
      userId: 1,
      targetType: FavoriteTargetType.reviewOutline,
      targetId: 1,
    );
    favoriteId = (await db.query('favorites')).single['id'] as int;
    await repository.updateFavoriteNote(
      favoriteId: favoriteId,
      note: '旧笔记',
      highlightText: '旧高亮文本',
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<FavoriteItemRecord> read() async =>
      (await repository.fetchFavoritesByType(
        userId: 1,
        targetType: FavoriteTargetType.reviewOutline,
      )).single;

  test(
    'range/color/note persist after reopen without changing source or legacy data',
    () async {
      await repository.saveAnnotations(
        userId: 1,
        favoriteId: favoriteId,
        annotations: [annotation],
      );
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${directory.path}/favorites.db',
      );
      db = await app.database;
      repository = FavoriteRepository(database: app);
      final favorite = await read();
      expect(favorite.annotations.single.toJson(), annotation.toJson());
      expect(favorite.annotations.single.matches(favorite.body), isTrue);
      expect(favorite.body, body);
      expect(favorite.note, '旧笔记');
      expect(favorite.highlightText, '旧高亮文本');
      expect(
        (await db.query('auth_sessions')).single['session_token'],
        'fixture-session',
      );
      await repository.saveAnnotations(
        userId: 1,
        favoriteId: favoriteId,
        annotations: [],
      );
      expect((await read()).annotations, isEmpty);
      expect((await read()).note, '旧笔记');
    },
  );

  test(
    'another user cannot overwrite annotations and changed source cannot be mis-anchored',
    () async {
      await repository.saveAnnotations(
        userId: 1,
        favoriteId: favoriteId,
        annotations: [annotation],
      );
      await expectLater(
        repository.saveAnnotations(
          userId: 2,
          favoriteId: favoriteId,
          annotations: [],
        ),
        throwsStateError,
      );
      expect((await read()).annotations.single.id, annotation.id);
      await db.update('review_outlines', {
        'outline_text': 'different text alpha',
      }, where: 'id=1');
      final changed = await read();
      expect(changed.annotations.single.matches(changed.body), isFalse);
      expect(changed.annotations.single.note, annotation.note);
    },
  );

  test(
    'practice question favorites decode the same persisted range data',
    () async {
      final document = (await db.query('source_documents')).single['id'];
      await db.insert('practice_questions', {
        'id': 1,
        'document_id': document,
        'question_text': '问题',
        'answer_text': '答案',
        'created_at': now,
      });
      await repository.toggleFavorite(
        userId: 1,
        targetType: FavoriteTargetType.practiceQuestion,
        targetId: 1,
      );
      final question = (await repository.fetchFavoritesByType(
        userId: 1,
        targetType: FavoriteTargetType.practiceQuestion,
      )).single;
      final start = question.body.indexOf('问题');
      final note = FavoriteAnnotation(
        id: 'question-note',
        start: start,
        end: start + 2,
        quote: '问题',
        note: '解题笔记',
      );
      await repository.saveAnnotations(
        userId: 1,
        favoriteId: question.favoriteId,
        annotations: [note],
      );
      final restored = (await repository.fetchFavoritesByType(
        userId: 1,
        targetType: FavoriteTargetType.practiceQuestion,
      )).single;
      expect(restored.annotations.single.toJson(), note.toJson());
    },
  );

  test(
    'v26 upgrade backs up and retains favorites, legacy notes and login session',
    () async {
      await db.execute('ALTER TABLE favorites DROP COLUMN annotations_json');
      await db.setVersion(26);
      await db.close();
      app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: '${directory.path}/favorites.db',
      );
      db = await app.database;
      repository = FavoriteRepository(database: app);
      expect(await db.getVersion(), 27);
      final favorite = await read();
      expect(favorite.favoriteId, favoriteId);
      expect(favorite.note, '旧笔记');
      expect(favorite.highlightText, '旧高亮文本');
      expect(favorite.body, body);
      expect(favorite.annotations, isEmpty);
      expect(
        (await db.query('auth_sessions')).single['session_token'],
        'fixture-session',
      );
      final backups = await directory
          .list()
          .where((file) => file.path.contains('.before-community-v26-'))
          .toList();
      expect(backups, hasLength(1));
      final backup = await databaseFactoryFfi.openDatabase(
        backups.single.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      expect(await backup.getVersion(), 26);
      expect((await backup.query('favorites')).single['note'], '旧笔记');
      expect(
        (await backup.query('auth_sessions')).single['session_token'],
        'fixture-session',
      );
      await backup.close();
    },
  );
}
