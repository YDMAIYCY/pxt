import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/interview_repository.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/interview/interview_ai_service.dart';
import 'package:pxt1/interview/interview_controller.dart';
import 'package:pxt1/interview/interview_evidence_service.dart';
import 'package:pxt1/interview/interview_voice_port.dart';
import 'package:pxt1/llm/minimax_client.dart';

/// 状态机行为的端到端验证：以真实 SQLite 会话为准，只替换语音与大模型。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const now = '2026-10-13T02:00:00.000Z';

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'learner',
      'password_hash': 'x',
      'password_salt': 'x',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('knowledge_libraries', {
      'id': 1,
      'user_id': 1,
      'name': '高等数学',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('import_records', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'operation_id': 'op:1',
      'title': '函数与极限',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('source_documents', {
      'id': 1,
      'user_id': 1,
      'library_id': 1,
      'import_record_id': 1,
      'source_type': 'camera_capture',
      'image_path': '/ocr.png',
      'original_title': '函数与极限',
      'ocr_status': 'success',
      'created_at': now,
    });
    await db.insert('ocr_texts', {
      'document_id': 1,
      'raw_text': '极限是x趋近某值时函数值趋近的值',
      'clean_text': '极限是x趋近某值时函数值趋近的值',
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    await db.close();
  });

  Future<InterviewController> build({
    List<http.Response>? responses,
    InterviewVoicePort? voice,
    String mode = 'deep',
  }) async {
    final repository = InterviewRepository(database: app);
    final session = await repository.createSession(
      userId: 1,
      libraryId: 1,
      recordId: 1,
      scopeName: '高等数学 · 函数与极限',
      mode: mode,
      difficulty: 'medium',
      targetQuestionCount: 1,
    );
    final queue = List<http.Response>.of(responses ?? const []);
    final client = MiniMaxClient(
      apiKey: 'test-key',
      endpoint: Uri.parse('https://example.com/v1/chat/completions'),
      httpClient: MockClient((request) async {
        if (queue.isEmpty) throw StateError('unexpected extra model call');
        return queue.removeAt(0);
      }),
    );
    final controller = InterviewController(
      userId: 1,
      session: session,
      repository: repository,
      aiService: InterviewAiService(miniMaxClient: client),
      voice: voice ?? _FakeVoice(),
      llmConfig: _config,
    );
    controller.debugEvidence = [
      const InterviewEvidence(
        key: 'ocr:1',
        sourceRecordId: 1,
        sourcePageId: 1,
        title: '函数与极限',
        content: '极限是x趋近某值时函数值趋近的值',
        sourceKind: 'ocr',
      ),
    ];
    return controller;
  }

  test(
    'full turn: question, transcript, evaluation, follow-up and report',
    () async {
      final voice = _FakeVoice();
      final repository = InterviewRepository(database: app);
      final session = await repository.createSession(
        userId: 1,
        libraryId: 1,
        recordId: 1,
        scopeName: '高等数学 · 函数与极限',
        mode: 'deep',
        difficulty: 'medium',
        targetQuestionCount: 2,
      );
      final controller = InterviewController(
        userId: 1,
        session: session,
        repository: repository,
        aiService: InterviewAiService(
          miniMaxClient: _client([
            _questionsResponse([
              {
                'question_text': '请解释函数极限的定义。',
                'evidence_key': 'ocr:1',
                'knowledge_point': '极限定义',
                'reference_points': ['趋近过程', '函数值趋近'],
              },
              {
                'question_text': '举一个极限的例子。',
                'evidence_key': 'ocr:1',
                'knowledge_point': '极限应用',
                'reference_points': ['具体例子'],
              },
            ]),
            _evaluationResponse(
              accuracy: 40,
              completeness: 15,
              logic: 12,
              expression: 13,
              followUp: '函数在该点是否有定义会影响极限存在吗？',
            ),
            _evaluationResponse(
              accuracy: 45,
              completeness: 18,
              logic: 14,
              expression: 14,
            ),
            _evaluationResponse(
              accuracy: 30,
              completeness: 10,
              logic: 8,
              expression: 9,
            ),
          ]),
        ),
        voice: voice,
        llmConfig: _config,
      );
      controller.debugEvidence = [_evidence];

      await controller.start();
      expect(controller.questions, hasLength(2));
      expect(controller.messages.where((m) => !m.isUser), hasLength(1));
      expect(controller.phase, InterviewPhase.awaitingAnswer);

      await controller.beginRecording();
      expect(controller.phase, InterviewPhase.recording);
      voice.emit('就是x靠近某个数字');
      await controller.stopRecording();
      expect(controller.phase, InterviewPhase.awaitingConfirmation);
      expect(controller.liveMessage?.text, '就是x靠近某个数字');
      // 修正识别文字不会新增第二条消息。
      controller.editPendingAnswer('就是x靠近某个数字时函数值也靠近某个值');
      expect(controller.messages.where((m) => m.isUser), isEmpty);

      await controller.submitAnswer();
      // 第一轮追问后仍在第 1 题。
      expect(controller.currentQuestionNumber, 1);
      expect(controller.messages.where((m) => m.isFollowUp), hasLength(1));

      await controller.beginRecording();
      voice.emit('不影响');
      await controller.stopRecording();
      await controller.submitAnswer();
      expect(controller.completedCount, 1);
      expect(controller.currentQuestionNumber, 2);

      await controller.beginRecording();
      voice.emit('例如1/x');
      await controller.stopRecording();
      await controller.submitAnswer();

      expect(controller.isFinished, isTrue);
      final report = jsonDecode(controller.reportJson!) as Map<String, dynamic>;
      expect(report['completed_count'], 2);
      expect(report['target_count'], 2);
      // 真实计算的均分，而不是设计稿示例分数：第 1 题取最后一次评价(91)，第 2 题 57。
      expect(report['overall_score'], (91 + 57) ~/ 2);
      expect(report['weak_points'], contains('极限应用'));

      // 会话与得分被持久化，重开后仍可读取。
      final saved = await repository.getSession(1, session.id);
      expect(saved!.status, 'completed');
      expect(saved.reportJson, isNotNull);
      expect(await repository.evaluations(1, session.id), hasLength(3));
    },
  );

  test(
    'duplicate submit is ignored while evaluating and never double-writes',
    () async {
      final voice = _FakeVoice();
      final controller = await build(
        voice: voice,
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'knowledge_point': '极限',
              'reference_points': ['趋近'],
            },
          ]),
          _evaluationResponse(
            accuracy: 20,
            completeness: 8,
            logic: 6,
            expression: 6,
          ),
        ],
      );
      controller.debugEvidence = [_evidence];
      await controller.start();
      await controller.beginRecording();
      voice.emit('答案');
      await controller.stopRecording();
      final first = controller.submitAnswer();
      final second = controller.submitAnswer();
      await Future.wait([first, second]);
      final repository = InterviewRepository(database: app);
      final turns = await repository.turns(1, controller.session.id);
      expect(turns.where((t) => t.speaker == 'user'), hasLength(1));
      expect(
        await repository.evaluations(1, controller.session.id),
        hasLength(1),
      );
    },
  );

  test(
    'text answer works and basic mode never schedules a follow-up',
    () async {
      final controller = await build(
        mode: 'basic',
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'reference_points': ['趋近'],
            },
          ]),
          _evaluationResponse(
            accuracy: 40,
            completeness: 15,
            logic: 12,
            expression: 13,
            followUp: '请再举例',
          ),
        ],
      );
      await controller.start();
      await controller.startTextAnswer();
      controller.editPendingAnswer('函数值的趋近过程');
      expect(controller.canSubmit, isTrue);
      await controller.submitAnswer();
      expect(controller.isFinished, isTrue);
      expect(controller.messages.where((m) => m.isFollowUp), isEmpty);
      expect(controller.completedCount, 1);
      controller.dispose();
    },
  );

  test('recording cannot submit before transcription is confirmed', () async {
    final voice = _FakeVoice();
    final controller = await build(
      voice: voice,
      responses: [
        _questionsResponse([
          {
            'question_text': '什么是极限？',
            'evidence_key': 'ocr:1',
            'reference_points': ['趋近'],
          },
        ]),
      ],
    );
    await controller.start();
    await controller.beginRecording();
    voice.emit('临时回答');
    await Future<void>.delayed(Duration.zero);
    await controller.submitAnswer();
    expect(controller.phase, InterviewPhase.recording);
    expect(
      (await InterviewRepository(
        database: app,
      ).turns(1, controller.session.id)).where((t) => t.speaker == 'user'),
      isEmpty,
    );
    controller.dispose();
  });

  test(
    'failed evaluation retries the saved corrected answer only once',
    () async {
      final voice = _FakeVoice();
      final controller = await build(
        voice: voice,
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'reference_points': ['趋近'],
            },
          ]),
          _contentResponse('{}'),
          _evaluationResponse(
            accuracy: 40,
            completeness: 15,
            logic: 12,
            expression: 13,
          ),
        ],
      );
      await controller.start();
      await controller.beginRecording();
      voice.emit('识别原文');
      await controller.stopRecording();
      controller.editPendingAnswer('校正后的真实回答');
      await controller.submitAnswer();
      expect(controller.phase, InterviewPhase.failed);
      await controller.retry();
      expect(controller.isFinished, isTrue);
      final turns = (await InterviewRepository(database: app).turns(
        1,
        controller.session.id,
      )).where((t) => t.speaker == 'user').toList();
      expect(turns, hasLength(1));
      expect(turns.single.text, '校正后的真实回答');
      expect(turns.single.rawText, '识别原文');
      expect(controller.messages.where((m) => m.isUser), hasLength(1));
      controller.dispose();
    },
  );

  test(
    'resume retains the follow-up round and caps follow-ups at two',
    () async {
      final controller = await build(
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'reference_points': ['趋近'],
            },
          ]),
          _evaluationResponse(
            accuracy: 20,
            completeness: 8,
            logic: 6,
            expression: 6,
            followUp: '追问一',
          ),
        ],
      );
      await controller.start();
      await controller.startTextAnswer(initial: '主答');
      await controller.submitAnswer();
      final repository = InterviewRepository(database: app);
      final resumed = InterviewController(
        userId: 1,
        session: (await repository.getSession(1, controller.session.id))!,
        repository: repository,
        aiService: InterviewAiService(
          miniMaxClient: _client([
            _evaluationResponse(
              accuracy: 30,
              completeness: 12,
              logic: 8,
              expression: 8,
              followUp: '追问二',
            ),
            _evaluationResponse(
              accuracy: 40,
              completeness: 15,
              logic: 12,
              expression: 13,
              followUp: '不应继续追问三',
            ),
          ]),
        ),
        voice: _FakeVoice(),
        llmConfig: _config,
      );
      controller.dispose();
      await resumed.resume();
      expect(resumed.phase, InterviewPhase.awaitingAnswer);
      expect(resumed.messages.last.round, 1);
      await resumed.startTextAnswer(initial: '第一轮追问回答');
      await resumed.submitAnswer();
      expect(resumed.messages.last.round, 2);
      await resumed.startTextAnswer(initial: '第二轮追问回答');
      await resumed.submitAnswer();
      expect(resumed.isFinished, isTrue);
      final turns = await repository.turns(1, resumed.session.id);
      expect(turns.where((t) => t.speaker == 'user').map((t) => t.round), [
        0,
        1,
        2,
      ]);
      resumed.dispose();
    },
  );

  test(
    'pause preserves pending answer and OCR loads through real SQL',
    () async {
      final evidence = await InterviewEvidenceService(
        database: app,
      ).load(userId: 1, libraryId: 1);
      expect(evidence.single.sourceRecordId, 1);
      expect(evidence.single.isOriginal, isTrue);
      await expectLater(
        InterviewEvidenceService(database: app).load(userId: 2, libraryId: 1),
        throwsStateError,
      );
      final controller = await build(
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'reference_points': ['趋近'],
            },
          ]),
        ],
      );
      await controller.start();
      await controller.startTextAnswer(initial: '尚未提交的回答');
      await controller.pause();
      expect(controller.phase, InterviewPhase.paused);
      await controller.resumeFromPause();
      expect(controller.canSubmit, isTrue);
      expect(controller.liveMessage?.text, '尚未提交的回答');
      controller.dispose();
    },
  );

  test('missing model config fails loudly instead of faking a score', () async {
    final controller = await build();
    controller.updateLlmConfig(LlmProviderConfig.emptyForUser(1));
    controller.debugEvidence = [_evidence];
    await controller.start();
    expect(controller.phase, InterviewPhase.failed);
    expect(controller.error, contains('配置大模型'));
    expect(controller.messages, isEmpty);
  });

  test('ending while evaluating rejects a late model response', () async {
    final repository = InterviewRepository(database: app);
    final session = await repository.createSession(
      userId: 1,
      libraryId: 1,
      recordId: 1,
      scopeName: '高等数学',
      mode: 'basic',
      difficulty: 'medium',
      targetQuestionCount: 1,
      voiceEnabled: false,
    );
    final entered = Completer<void>();
    final result = Completer<http.Response>();
    var calls = 0;
    final client = MiniMaxClient(
      apiKey: 'test-key',
      endpoint: Uri.parse('https://example.com/v1/chat/completions'),
      httpClient: MockClient((request) async {
        if (++calls == 1) {
          return _questionsResponse([
            {
              'question_text': '什么是极限？',
              'knowledge_point': '极限',
              'reference_points': ['趋近'],
              'evidence_key': 'ocr:1',
            },
          ]);
        }
        entered.complete();
        return result.future;
      }),
    );
    final controller = InterviewController(
      userId: 1,
      session: session,
      repository: repository,
      aiService: InterviewAiService(miniMaxClient: client),
      voice: _FakeVoice(),
      llmConfig: _config,
    )..debugEvidence = [_evidence];
    await controller.start();
    await controller.startTextAnswer(initial: '实际回答');
    final submitting = controller.submitAnswer();
    await entered.future;
    await controller.endEarly();
    result.complete(
      _evaluationResponse(
        accuracy: 50,
        completeness: 20,
        logic: 15,
        expression: 15,
      ),
    );
    await submitting;
    expect(controller.isFinished, isTrue);
    expect((await repository.getSession(1, session.id))!.status, 'cancelled');
    expect(await repository.evaluations(1, session.id), isEmpty);
    expect(jsonDecode(controller.reportJson!)['overall_score'], isNull);
    controller.dispose();
  });

  test(
    'cancelling a recording returns to waiting without writing a turn',
    () async {
      final voice = _FakeVoice();
      final controller = await build(
        voice: voice,
        responses: [
          _questionsResponse([
            {
              'question_text': '什么是极限？',
              'evidence_key': 'ocr:1',
              'knowledge_point': '极限',
              'reference_points': ['趋近'],
            },
          ]),
        ],
      );
      controller.debugEvidence = [_evidence];
      await controller.start();
      await controller.beginRecording();
      await controller.cancelRecording();
      expect(controller.phase, InterviewPhase.awaitingAnswer);
      expect(controller.liveMessage, isNull);
      final repository = InterviewRepository(database: app);
      expect(
        (await repository.turns(
          1,
          controller.session.id,
        )).where((t) => t.speaker == 'user'),
        isEmpty,
      );
      expect(voice.cancelCount, greaterThan(0));
    },
  );
}

const _evidence = InterviewEvidence(
  key: 'ocr:1',
  sourceRecordId: 1,
  sourcePageId: 1,
  title: '函数与极限',
  content: '极限是x趋近某值时函数值趋近的值',
  sourceKind: 'ocr',
);

final _config = LlmProviderConfig(
  id: 1,
  userId: 1,
  provider: LlmProvider.custom,
  apiMode: LlmApiMode.openAiCompatible,
  apiKey: 'test-key',
  baseUrl: 'https://example.com/v1',
  model: 'test-model',
  maxTokens: 4096,
  createdAt: DateTime.utc(2026, 10, 13),
  updatedAt: DateTime.utc(2026, 10, 13),
);

MiniMaxClient _client(List<http.Response> queue) {
  final pending = List<http.Response>.of(queue);
  return MiniMaxClient(
    apiKey: 'test-key',
    endpoint: Uri.parse('https://example.com/v1/chat/completions'),
    httpClient: MockClient((request) async {
      if (pending.isEmpty) throw StateError('unexpected extra model call');
      return pending.removeAt(0);
    }),
  );
}

http.Response _questionsResponse(List<Map<String, Object?>> questions) =>
    _contentResponse(
      jsonEncode({
        'questions': questions
            .map((q) => {'knowledge_point': '极限', ...q})
            .toList(),
      }),
    );

http.Response _evaluationResponse({
  required int accuracy,
  required int completeness,
  required int logic,
  required int expression,
  String followUp = '',
}) => _contentResponse(
  jsonEncode({
    'accuracy_score': accuracy,
    'completeness_score': completeness,
    'logic_score': logic,
    'expression_score': expression,
    'strengths': ['概念表述正确'],
    'weaknesses': ['缺少例子'],
    'suggestions': ['补充边界条件'],
    'follow_up_text': followUp,
    'follow_up_reference_points': const <String>[],
    'evidence_refs': const <int>[1],
  }),
);

http.Response _contentResponse(String content) => http.Response(
  jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'content': content},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json'},
);

class _FakeVoice implements InterviewVoicePort {
  final _phase = ValueNotifier<VoicePhase>(VoicePhase.idle);
  final _mouth = ValueNotifier<double>(0);
  final _controller = StreamController<VoiceTranscript>.broadcast();
  int cancelCount = 0;
  String _text = '';

  void emit(String text) {
    _text = text;
    _controller.add(VoiceTranscript(text: text, isFinal: false));
  }

  @override
  ValueListenable<VoicePhase> get phase => _phase;
  @override
  ValueListenable<double> get mouthActivity => _mouth;
  @override
  Stream<VoiceTranscript> get transcripts => _controller.stream;
  @override
  bool get modelReady => true;
  @override
  String? get lastError => null;
  @override
  Future<void> ensureOfflineModel({
    void Function(double progress)? onProgress,
  }) async {}
  @override
  Future<void> speak(
    String text, {
    double volume = 1,
    double rate = 0.5,
  }) async {
    _phase.value = VoicePhase.speaking;
    _mouth.value = .7;
    _phase.value = VoicePhase.idle;
    _mouth.value = 0;
  }

  @override
  Future<void> stopSpeaking() async {}
  @override
  Future<void> startRecording() async {
    _text = '';
    _phase.value = VoicePhase.recording;
  }

  @override
  Future<VoiceTranscript> stopRecording() async {
    _phase.value = VoicePhase.transcribing;
    _phase.value = VoicePhase.idle;
    return VoiceTranscript(text: _text, isFinal: true, durationMs: 1200);
  }

  @override
  Future<void> playRecording(String path) async {}
  @override
  Future<void> cancel() async {
    cancelCount++;
    _text = '';
    _phase.value = VoicePhase.idle;
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
    _phase.dispose();
    _mouth.dispose();
  }
}
