import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/import_record_schema.dart';
import 'package:pxt1/database/interview_repository.dart';
import 'package:pxt1/interview/interview_models.dart';

const _time = '2026-10-13T00:00:00.000Z';
const _historyTables = [
  'interview_sessions',
  'interview_questions',
  'interview_turns',
  'interview_evaluations',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('InterviewRepository with real SQLite', () {
    late Directory folder;
    late Database db;
    late InterviewRepository repository;

    setUp(() async {
      folder = await Directory.systemTemp.createTemp(
        'pxt-interview-repository-',
      );
      addTearDown(() async {
        await folder.delete(recursive: true);
      });
      final app = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: p.join(folder.path, 'interviews.db'),
      );
      db = await app.database;
      addTearDown(db.close);
      repository = InterviewRepository(
        database: app,
        appDocumentsDirectory: folder,
      );
      await _seed(db);
      expect(await db.rawQuery('PRAGMA foreign_keys'), [
        {'foreign_keys': 1},
      ]);
    });

    Future<InterviewSession> session({
      int user = 1,
      int library = 1,
      int? record = 11,
    }) => repository.createSession(
      userId: user,
      libraryId: library,
      recordId: record,
      scopeName: '资料范围',
      mode: 'deep',
      difficulty: 'medium',
      targetQuestionCount: 2,
    );

    Future<InterviewQuestion> question(
      InterviewSession s, {
      int record = 11,
      int page = 101,
    }) async => (await repository.saveQuestions(s.userId, s.id, [
      _draft(record: record, page: page),
    ])).single;

    Future<InterviewTurn> answer(
      InterviewQuestion q, {
      int user = 1,
      String key = 'answer',
      String text = '函数值趋近一个确定的值',
      String? audioPath,
      String status = 'final',
    }) => repository.upsertTurn(
      userId: user,
      sessionId: q.sessionId,
      questionId: q.id,
      speaker: 'user',
      text: text,
      rawText: '函数值趋近',
      audioPath: audioPath,
      durationMs: 1200,
      status: status,
      requestKey: key,
    );

    test(
      'creation rejects foreign users, libraries and records atomically',
      () async {
        for (final scope in [
          (user: 1, library: 3, record: 31),
          (user: 2, library: 1, record: 11),
          (user: 1, library: 1, record: 21),
          (user: 1, library: 1, record: 31),
          (user: 1, library: 1, record: 999),
          (user: 1, library: 999, record: 11),
        ]) {
          await expectLater(
            session(
              user: scope.user,
              library: scope.library,
              record: scope.record,
            ),
            throwsStateError,
          );
        }
        expect(await db.query('interview_sessions'), isEmpty);
        final owned = await session();
        expect(owned.userId, 1);
        expect(owned.libraryId, 1);
        expect(owned.recordId, 11);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test('history filters isolate users, libraries and records', () async {
      final a = await session();
      final b = await session(record: 12);
      final c = await session(library: 2, record: 21);
      final foreign = await session(user: 2, library: 3, record: 31);
      final libraryWide = await session(record: null);

      expect(
        (await repository.listSessions(1)).map((s) => s.id),
        unorderedEquals([a.id, b.id, c.id, libraryWide.id]),
      );
      expect(
        (await repository.listSessions(1, libraryId: 1)).map((s) => s.id),
        unorderedEquals([a.id, b.id, libraryWide.id]),
      );
      expect(
        (await repository.listSessions(1, recordId: 11)).map((s) => s.id),
        [a.id],
      );
      expect(
        await repository.listSessions(1, libraryId: 2, recordId: 11),
        isEmpty,
      );
      expect(await repository.listSessions(1, libraryId: 3), isEmpty);
      expect((await repository.listSessions(2)).map((s) => s.id), [foreign.id]);
      expect(await repository.getSession(2, a.id), isNull);
      expect(await repository.getSession(1, foreign.id), isNull);
    });

    test(
      'question sources stay inside the selected record and library',
      () async {
        final s = await session();
        for (final invalid in [
          _draft(record: 12, page: 201, order: 1),
          _draft(record: 21, page: 301, order: 1),
          _draft(record: 31, page: 401, order: 1),
          _draft(record: 11, page: 201, order: 1),
          _draft(concept: 1002, order: 1),
        ]) {
          await expectLater(
            repository.saveQuestions(1, s.id, [_draft(), invalid]),
            throwsStateError,
          );
          expect(await repository.questions(1, s.id), isEmpty);
        }
        final saved = await repository.saveQuestions(1, s.id, [
          _draft(concept: 1001),
          _draft(page: 102, order: 1),
        ]);
        expect(saved.map((q) => q.sourcePageId), [101, 102]);
        final retry = await repository.saveQuestions(1, s.id, [
          _draft(concept: 1001),
          _draft(page: 102, order: 1),
        ]);
        expect(retry.map((q) => q.id), saved.map((q) => q.id));

        final libraryWide = await session(record: null);
        expect(
          (await repository.saveQuestions(1, libraryWide.id, [
            _draft(),
            _draft(record: 12, page: 201, order: 1),
          ])).map((q) => q.sourceRecordId),
          [11, 12],
        );
      },
    );

    test('another user cannot read or mutate a populated session', () async {
      final s = await session();
      final q = await question(s);
      final t = await answer(q);
      final e = await repository.saveEvaluation(1, _evaluation(t));
      final before = await _snapshot(db, _historyTables);

      await expectLater(repository.questions(2, s.id), throwsStateError);
      expect(await repository.turns(2, s.id), isEmpty);
      expect(await repository.evaluations(2, s.id), isEmpty);
      await expectLater(
        repository.saveQuestions(2, s.id, [_draft()]),
        throwsStateError,
      );
      await expectLater(answer(q, user: 2), throwsStateError);
      await expectLater(repository.saveEvaluation(2, e), throwsStateError);
      expect(await repository.completeQuestion(2, s.id, q.id), 0);
      expect(await repository.setSessionState(2, s.id, status: 'thinking'), 0);
      expect(await repository.finishSession(2, s.id, report: {'score': 0}), 0);
      await expectLater(repository.deleteSession(2, s.id), throwsStateError);
      expect(await _snapshot(db, _historyTables), before);
    });

    test(
      'turns and evaluations cannot cross sessions or saved evidence',
      () async {
        final a = await session();
        final b = await session(record: 12);
        final qa = await question(a);
        final qb = await question(b, record: 12, page: 201);
        final ta = await answer(qa);
        final tb = await answer(qb);
        final before = await _snapshot(db, _historyTables);

        await expectLater(
          repository.upsertTurn(
            userId: 1,
            sessionId: a.id,
            questionId: qb.id,
            speaker: 'user',
            text: '越界回答',
            requestKey: 'foreign-question',
          ),
          throwsStateError,
        );
        final mismatched = _evaluation(tb).toMap()..['turn_id'] = ta.id;
        await expectLater(
          repository.saveEvaluation(1, InterviewEvaluation.fromMap(mismatched)),
          throwsStateError,
        );
        for (final page in [201, 301, 401]) {
          await expectLater(
            repository.saveEvaluation(1, _evaluation(ta, evidence: [page])),
            throwsStateError,
          );
        }
        expect(await _snapshot(db, _historyTables), before);

        // Test the production composite FK independently of repository guards.
        final invalidTurn = ta.toMap()
          ..remove('id')
          ..['question_id'] = qb.id
          ..['request_key'] = 'invalid-fk';
        await expectLater(
          db.insert('interview_turns', invalidTurn),
          throwsA(isA<DatabaseException>()),
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test(
      'concurrent turn retries retain one ID and immutable final content',
      () async {
        final s = await session();
        final q = await question(s);
        final retries = await Future.wait(List.generate(4, (_) => answer(q)));
        expect(retries.map((t) => t.id).toSet(), hasLength(1));
        expect(await repository.turns(1, s.id), hasLength(1));
        final original = retries.first.toMap();
        await expectLater(answer(q, text: '覆盖最终回答'), throwsStateError);
        await expectLater(
          repository.upsertTurn(
            userId: 1,
            sessionId: s.id,
            questionId: q.id,
            speaker: 'assistant',
            text: '不同角色',
            requestKey: 'answer',
          ),
          throwsStateError,
        );
        expect((await repository.turns(1, s.id)).single.toMap(), original);

        // The same request key in a different session must not deduplicate away.
        final other = await session();
        final otherTurn = await answer(await question(other));
        expect(otherTurn.id, isNot(retries.first.id));
      },
    );

    test(
      'a recoverable turn becomes final without allocating a second row',
      () async {
        final s = await session();
        final q = await question(s);
        final pending = await answer(q, status: 'error', text: '');
        await expectLater(
          repository.saveEvaluation(1, _evaluation(pending)),
          throwsStateError,
        );
        final finalTurn = await answer(q);
        expect(finalTurn.id, pending.id);
        expect(finalTurn.createdAt, pending.createdAt);
        expect(finalTurn.status, 'final');
        expect(await repository.turns(1, s.id), hasLength(1));
      },
    );

    test(
      'evaluation retries keep the first score and completion counts once',
      () async {
        final s = await session();
        final q = await question(s);
        final t = await answer(q);
        final first = await repository.saveEvaluation(1, _evaluation(t));
        final retries = await Future.wait([
          repository.saveEvaluation(1, _evaluation(t)),
          repository.saveEvaluation(1, _evaluation(t, accuracy: 10)),
          repository.saveEvaluation(1, first),
        ]);
        for (final retry in retries) {
          expect(retry.toMap(), first.toMap());
        }
        expect(await repository.evaluations(1, s.id), hasLength(1));
        await expectLater(
          repository.saveEvaluation(1, _evaluation(t, id: first.id + 100)),
          throwsStateError,
        );
        final duplicate = first.toMap()..remove('id');
        await expectLater(
          db.insert('interview_evaluations', duplicate),
          throwsA(isA<DatabaseException>()),
        );
        expect(await repository.completeQuestion(1, s.id, q.id), 1);
        expect(await repository.completeQuestion(1, s.id, q.id), 0);
        expect(
          (await repository.getSession(1, s.id))!.completedQuestionCount,
          1,
        );
        expect((await answer(q)).id, t.id);
        expect((await repository.saveEvaluation(1, first)).id, first.id);
        await expectLater(answer(q, key: 'new-answer'), throwsStateError);
      },
    );

    for (final cancelled in [false, true]) {
      test(
        '${cancelled ? 'cancelled' : 'completed'} sessions reject every later write',
        () async {
          final s = await session();
          final q = await question(s);
          final t = await answer(q);
          final e = await repository.saveEvaluation(1, _evaluation(t));
          final ungraded = await answer(q, key: 'ungraded');
          final report = {'score': e.totalScore, 'summary': '已结束'};
          expect(
            await repository.finishSession(
              1,
              s.id,
              report: report,
              cancelled: cancelled,
            ),
            1,
          );
          final before = await _snapshot(db, _historyTables);
          await expectLater(
            repository.saveQuestions(1, s.id, [_draft()]),
            throwsStateError,
          );
          await expectLater(answer(q), throwsStateError);
          await expectLater(answer(q, key: 'late-answer'), throwsStateError);
          await expectLater(repository.saveEvaluation(1, e), throwsStateError);
          await expectLater(
            repository.saveEvaluation(1, _evaluation(ungraded)),
            throwsStateError,
          );
          expect(await repository.completeQuestion(1, s.id, q.id), 0);
          expect(
            await repository.setSessionState(
              1,
              s.id,
              status: 'listening',
              currentRound: 1,
            ),
            0,
          );
          expect(
            await repository.finishSession(
              1,
              s.id,
              report: {'score': 0},
              cancelled: !cancelled,
            ),
            0,
          );
          expect(await _snapshot(db, _historyTables), before);
          final ended = (await repository.getSession(1, s.id))!;
          expect(ended.status, cancelled ? 'cancelled' : 'completed');
          expect(ended.endedAt, isNotNull);
          expect(ended.reportJson, contains('已结束'));
        },
      );
    }

    test(
      'deleting history cascades only its children and preserves sources',
      () async {
        final doomed = await session();
        final kept = await session();
        final foreign = await session(user: 2, library: 3, record: 31);
        final q = await question(doomed);
        final keptQuestion = await question(kept);
        final foreignQuestion = await question(foreign, record: 31, page: 401);
        final t = await answer(q);
        await repository.saveEvaluation(1, _evaluation(t));
        await repository.saveEvaluation(
          1,
          _evaluation(await answer(keptQuestion)),
        );
        await repository.saveEvaluation(
          2,
          _evaluation(await answer(foreignQuestion, user: 2), evidence: [401]),
        );
        await repository.finishSession(1, doomed.id, report: {'score': 81});
        final sourcesBefore = await _snapshot(db, _sourceTables);
        final othersBefore = await _snapshot(db, _historyTables);
        for (final table in _historyTables) {
          othersBefore[table]!.removeWhere(
            (row) =>
                (table == 'interview_sessions'
                    ? row['id']
                    : row['session_id']) ==
                doomed.id,
          );
        }

        await repository.deleteSession(1, doomed.id);

        expect(await repository.getSession(1, doomed.id), isNull);
        expect(await repository.turns(1, doomed.id), isEmpty);
        expect(await repository.evaluations(1, doomed.id), isEmpty);
        expect(await _snapshot(db, _historyTables), othersBefore);
        expect(await _snapshot(db, _sourceTables), sourcesBefore);
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      },
    );

    test(
      'audio cleanup retains shared files and files outside interview_audio',
      () async {
        final audioRoot = await Directory(
          p.join(folder.path, 'interview_audio'),
        ).create();
        final exclusive = await File(
          p.join(audioRoot.path, 'exclusive.wav'),
        ).writeAsString('own');
        final shared = await File(
          p.join(audioRoot.path, 'shared.wav'),
        ).writeAsString('shared');
        final sourceFile = await File(
          p.join(folder.path, 'source.wav'),
        ).writeAsString('source');
        final doomed = await session();
        final kept = await session(user: 2, library: 3, record: 31);
        final q = await question(doomed);
        final otherQuestion = await question(kept, record: 31, page: 401);
        await answer(q, key: 'exclusive', audioPath: exclusive.path);
        await answer(q, key: 'shared', audioPath: shared.path);
        await answer(q, key: 'source', audioPath: sourceFile.path);
        await answer(otherQuestion, user: 2, audioPath: shared.path);
        final remaining = await repository.turns(2, kept.id);

        await repository.deleteSession(1, doomed.id);

        expect(await exclusive.exists(), isFalse);
        expect(await shared.readAsString(), 'shared');
        expect(await sourceFile.readAsString(), 'source');
        expect(
          (await repository.turns(2, kept.id)).map((t) => t.toMap()),
          remaining.map((t) => t.toMap()),
        );
      },
    );
  });

  test(
    'legacy migration preserves original rows and survives reopening',
    () async {
      final folder = await Directory.systemTemp.createTemp(
        'pxt-interview-v17-',
      );
      addTearDown(() async {
        await folder.delete(recursive: true);
      });
      final path = p.join(folder.path, 'legacy.db');
      // Build v17 from the captured pre-import schema and its real migration.
      // No v18 creator or interview schema is used to construct the old DB.
      final v15 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 15,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            final sql = await File(
              'test/fixtures/phase03_schema_v15.sql',
            ).readAsString();
            for (final statement in sql.split(';')) {
              if (statement.trim().isNotEmpty) await db.execute(statement);
            }
          },
        ),
      );
      addTearDown(v15.close);
      await v15.close();
      final v17 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 17,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onUpgrade: (db, oldVersion, newVersion) async {
            expect(oldVersion, 15);
            expect(newVersion, 17);
            await createImportRecordSchema(db);
          },
        ),
      );
      addTearDown(v17.close);
      await _seed(v17);
      await v17.insert('record_source_versions', {
        'id': 70,
        'record_id': 11,
        'fingerprint': 'original-content',
        'content': '版本快照',
        'created_at': _time,
      });
      await v17.insert('practice_questions', {
        'id': 80,
        'document_id': 101,
        'question_text': '历史练习题',
        'answer_text': '原答案',
        'analysis_text': '原解析',
        'review_status': 'wrong',
        'last_user_answer': '历史回答',
        'wrong_count': 2,
        'next_review_at': '2026-11-01T00:00:00.000Z',
        'mastery_score': 37,
        'review_interval_days': 7,
        'created_at': _time,
      });
      await v17.insert('learning_resources', {
        'id': 90,
        'document_id': 101,
        'concept_id': 1001,
        'type': 'notes',
        'title': '原笔记',
        'content': '原资料内容',
        'input_fingerprint': 'old-input',
        'model': 'old-model',
        'version': 1,
        'created_at': _time,
      });
      await v17.insert('learning_attempts', {
        'id': 100,
        'user_id': 1,
        'document_id': 101,
        'concept_id': 1001,
        'question_id': 80,
        'origin': 'practice',
        'prompt': '历史练习题',
        'answer': '旧作答',
        'score': 73,
        'feedback': '旧反馈',
        'created_at': _time,
      });
      // v17 also applies this backfill on reopen. Capture that settled state,
      // rather than attributing legacy import normalization to the v18 upgrade.
      await createImportRecordSchema(v17);
      expect(await v17.getVersion(), 17);
      expect(
        await v17.rawQuery(
          "SELECT name FROM sqlite_master WHERE name LIKE 'interview_%'",
        ),
        isEmpty,
      );
      final oldTables = (await v17.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )).map((r) => r['name'] as String).toList();
      final before = await _snapshot(v17, oldTables);
      await v17.close();

      final upgraded = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final db = await upgraded.database;
      addTearDown(db.close);
      expect(await db.getVersion(), AppDatabase.databaseVersion);
      final after = await _snapshot(db, oldTables);
      for (final entry in before.entries) {
        final columns = entry.value.isEmpty
            ? <String>{}
            : entry.value.first.keys.toSet();
        expect(
          after[entry.key]!
              .map(
                (row) => Map.fromEntries(
                  row.entries.where((e) => columns.contains(e.key)),
                ),
              )
              .toList(),
          entry.value,
          reason: entry.key,
        );
      }
      for (final table in _historyTables) {
        expect(await db.query(table), isEmpty);
      }
      expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      final repository = InterviewRepository(database: upgraded);
      final s = await repository.createSession(
        userId: 1,
        libraryId: 1,
        recordId: 11,
        scopeName: '旧资料',
        mode: 'deep',
        difficulty: 'medium',
      );
      final q = (await repository.saveQuestions(1, s.id, [
        _draft(concept: 1001),
      ])).single;
      final t = await repository.upsertTurn(
        userId: 1,
        sessionId: s.id,
        questionId: q.id,
        speaker: 'user',
        text: '迁移后的回答',
        requestKey: 'after-migration',
      );
      await repository.saveEvaluation(1, _evaluation(t));
      await repository.completeQuestion(1, s.id, q.id);
      await repository.finishSession(1, s.id, report: {'score': 81});
      final history = await _snapshot(db, _historyTables);
      // The interview session legitimately writes mastery back to
      // knowledge_concepts, so "survives reopening" must compare against the
      // post-session state rather than the pre-interview snapshot above.
      final beforeClose = await _snapshot(db, oldTables);
      await db.close();

      final reopened = await AppDatabase.openForTesting(
        databaseFactoryFfi,
        path: path,
      );
      final reopenedDb = await reopened.database;
      addTearDown(reopenedDb.close);
      expect(await reopenedDb.getVersion(), AppDatabase.databaseVersion);
      expect(await _snapshot(reopenedDb, oldTables), beforeClose);
      expect(await _snapshot(reopenedDb, _historyTables), history);
      expect(await reopenedDb.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    },
  );
}

const _sourceTables = [
  'users',
  'knowledge_libraries',
  'import_records',
  'source_documents',
  'ocr_texts',
  'knowledge_concepts',
];

Future<void> _seed(Database db) async {
  for (final id in [1, 2]) {
    await db.insert('users', {
      'id': id,
      'username': 'learner$id',
      'password_hash': 'test',
      'password_salt': 'test',
      'created_at': _time,
      'updated_at': _time,
    });
  }
  for (final id in [1, 2, 3]) {
    await db.insert('knowledge_libraries', {
      'id': id,
      'user_id': id == 3 ? 2 : 1,
      'name': '资料库$id',
      'created_at': _time,
      'updated_at': _time,
    });
  }
  for (final record in [
    (id: 11, library: 1, user: 1),
    (id: 12, library: 1, user: 1),
    (id: 21, library: 2, user: 1),
    (id: 31, library: 3, user: 2),
  ]) {
    await db.insert('import_records', {
      'id': record.id,
      'user_id': record.user,
      'library_id': record.library,
      'operation_id': 'import:${record.id}',
      'title': '导入记录${record.id}',
      'created_at': _time,
      'updated_at': _time,
    });
  }
  for (final page in [
    (id: 101, record: 11, library: 1, user: 1),
    (id: 102, record: 11, library: 1, user: 1),
    (id: 201, record: 12, library: 1, user: 1),
    (id: 301, record: 21, library: 2, user: 1),
    (id: 401, record: 31, library: 3, user: 2),
  ]) {
    await db.insert('source_documents', {
      'id': page.id,
      'user_id': page.user,
      'library_id': page.library,
      'import_record_id': page.record,
      'source_type': 'camera_capture',
      'image_path': 'source-${page.id}.png',
      'original_file_path': 'source-${page.id}.png',
      'original_title': '原始页面${page.id}',
      'ocr_status': 'success',
      'created_at': _time,
    });
    await db.insert('ocr_texts', {
      'document_id': page.id,
      'raw_text': '极限定义${page.id}',
      'clean_text': '极限定义${page.id}',
      'created_at': _time,
      'updated_at': _time,
    });
  }
  for (final concept in [(id: 1001, page: 101), (id: 1002, page: 201)]) {
    await db.insert('knowledge_concepts', {
      'id': concept.id,
      'user_id': 1,
      'library_id': 1,
      'document_id': concept.page,
      'name': '极限定义',
      'created_at': _time,
      'updated_at': _time,
    });
  }
}

InterviewQuestionDraft _draft({
  int record = 11,
  int page = 101,
  int order = 0,
  int? concept,
}) => InterviewQuestionDraft(
  questionText: '解释极限的定义',
  referencePoints: ['趋近过程', '确定的值'],
  knowledgePoint: '极限定义',
  knowledgePointId: concept,
  sourceRecordId: record,
  sourcePageId: page,
  evidenceText: '函数值趋近一个确定的值',
  sourceKind: 'ocr',
  orderIndex: order,
);

InterviewEvaluation _evaluation(
  InterviewTurn turn, {
  int id = 0,
  int accuracy = 40,
  List<int> evidence = const [101],
}) => InterviewEvaluation(
  id: id,
  sessionId: turn.sessionId,
  questionId: turn.questionId,
  turnId: turn.id,
  accuracyScore: accuracy,
  completenessScore: 16,
  logicScore: 12,
  expressionScore: 13,
  totalScore: accuracy + 16 + 12 + 13,
  strengths: ['定义正确'],
  weaknesses: ['缺少例子'],
  suggestions: ['补充例子'],
  evidenceRefs: evidence,
  followUpReferencePoints: [],
);

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  Database db,
  Iterable<String> tables,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in tables) {
    result[table] = List.of(await db.query(table, orderBy: 'rowid'));
  }
  return result;
}
