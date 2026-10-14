import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'package:pxt1/interview/interview_models.dart';
import 'package:pxt1/interview/interview_voice_port.dart';
import 'package:pxt1/llm/minimax_client.dart';
import 'package:pxt1/ui/pages/interview/interview_chat_page.dart';
import 'package:pxt1/ui/pages/interview/interview_result_page.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

/// 面试 UI 验证：微信式左右布局、进度显示和真实分数来源。
/// The avatar runs a continuous breathing ticker, so pumpAndSettle never
/// settles; advance a bounded number of frames instead.
Future<void> _settle(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    // Real sqlite_ffi work only progresses outside the fake-async zone.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final shot = await boundary.toImage(pixelRatio: 2);
    final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('docs/interview-validation')
      ..createSync(recursive: true);
    await File('${dir.path}/$name').writeAsBytes(bytes!.buffer.asUint8List());
    shot.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppDatabase app;
  late Database db;
  const now = '2026-10-13T03:00:00.000Z';
  var testTheme = AppTheme.light;
  setUpAll(() async {
    // Use locally installed fonts only for readable validation screenshots.
    // They are never packaged as application assets.
    final chinese = File('C:/Windows/Fonts/msyh.ttc');
    if (await chinese.exists()) {
      final loader = FontLoader('ValidationChinese')
        ..addFont(chinese.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
      testTheme = AppTheme.light.copyWith(
        appBarTheme: AppTheme.light.appBarTheme.copyWith(
          titleTextStyle: AppTheme.light.appBarTheme.titleTextStyle?.copyWith(
            fontFamily: 'ValidationChinese',
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: AppTheme.light.filledButtonTheme.style?.copyWith(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'ValidationChinese',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: AppTheme.light.outlinedButtonTheme.style?.copyWith(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'ValidationChinese',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        textTheme: AppTheme.light.textTheme.apply(
          fontFamily: 'ValidationChinese',
        ),
      );
    }
    final icons = File(
      'D:/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (await icons.exists()) {
      final loader = FontLoader('MaterialIcons')
        ..addFont(icons.readAsBytes().then((b) => ByteData.sublistView(b)));
      await loader.load();
    }
  });

  setUp(() async {
    app = await AppDatabase.openForTesting(databaseFactoryFfi);
    db = await app.database;
    await db.insert('users', {
      'id': 1,
      'username': 'u',
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
      'image_path': '/a.png',
      'original_title': '函数与极限',
      'ocr_status': 'success',
      'created_at': now,
    });
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets('chat shows AI on the left with a right-aligned user bubble', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = InterviewRepository(database: app);
    final session = (await tester.runAsync(
      () => repository.createSession(
        userId: 1,
        libraryId: 1,
        recordId: 1,
        scopeName: '高等数学 · 函数与极限',
        mode: 'basic',
        difficulty: 'medium',
        targetQuestionCount: 2,
        voiceEnabled: false,
        autoPlay: false,
      ),
    ))!;
    final voice = _FakeVoice();
    final controller = InterviewController(
      userId: 1,
      session: session,
      repository: repository,
      aiService: InterviewAiService(
        miniMaxClient: _client([
          _response(
            jsonEncode({
              'questions': [
                {
                  'question_text': '请解释函数极限的定义。',
                  'evidence_key': 'ocr:1',
                  'knowledge_point': '极限定义',
                  'reference_points': ['趋近过程'],
                },
                {
                  'question_text': '举一个例子。',
                  'evidence_key': 'ocr:1',
                  'knowledge_point': '极限应用',
                  'reference_points': ['例子'],
                },
              ],
            }),
          ),
          _response(
            jsonEncode({
              'accuracy_score': 40,
              'completeness_score': 15,
              'logic_score': 12,
              'expression_score': 13,
              'strengths': ['表述准确'],
              'weaknesses': ['缺例子'],
              'suggestions': ['补充例子'],
              'follow_up_text': '',
              'evidence_refs': [1],
            }),
          ),
        ]),
      ),
      voice: voice,
      llmConfig: _config,
    );
    controller.debugEvidence = [_evidence];

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: testTheme,
          debugShowCheckedModeBanner: false,
          home: InterviewChatPage(
            userId: 1,
            sessionId: session.id,
            controller: controller,
            voice: voice,
          ),
        ),
      ),
    );
    await _settle(tester);
    expect(controller.phase, InterviewPhase.awaitingAnswer);

    expect(find.text('AI 语音面试'), findsOneWidget);
    expect(find.text('AI 面试官'), findsWidgets);
    expect(find.textContaining('第 1 / 2 题'), findsOneWidget);
    expect(find.text('点击作答'), findsOneWidget);
    expect(find.text('请解释函数极限的定义。'), findsOneWidget);

    // AI 气泡靠左。
    final aiRow = tester.widget<Row>(
      find
          .ancestor(of: find.text('请解释函数极限的定义。'), matching: find.byType(Row))
          .first,
    );
    expect(aiRow.mainAxisAlignment, MainAxisAlignment.start);

    // 逐字转写只更新当前气泡，不新增消息。
    await tester.tap(find.byKey(const ValueKey('interview-mic')));
    await _settle(tester);
    voice.emit('就是x靠近某值');
    await _settle(tester);
    voice.emit('就是x靠近某值时函数值也靠近某值');
    await _settle(tester);
    expect(find.text('就是x靠近某值时函数值也靠近某值'), findsOneWidget);
    expect(find.text('我的回答'), findsOneWidget);

    // 用户气泡靠右，并与 AI 分开。
    final userRow = tester.widget<Row>(
      find.ancestor(of: find.text('我的回答'), matching: find.byType(Row)).first,
    );
    expect(userRow.mainAxisAlignment, MainAxisAlignment.end);
    expect(find.text('AI 面试官'), findsWidgets);
    await _capture(tester, 'chat-widget.png');
    await tester.tap(find.byKey(const ValueKey('interview-mic')));
    await _settle(tester);
    await tester.tap(find.text('文字回答'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), '校对后的回答');
    await tester.pump();
    expect(controller.liveMessage?.text, '校对后的回答');
    expect(controller.canSubmit, isTrue);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.resetViewInsets();
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('result page shows persisted score, never the design mock', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = InterviewRepository(database: app);
    final session = (await tester.runAsync(
      () => repository.createSession(
        userId: 1,
        libraryId: 1,
        recordId: 1,
        scopeName: '高等数学 · 函数与极限',
        mode: 'basic',
        difficulty: 'medium',
        targetQuestionCount: 1,
      ),
    ))!;
    final questions = (await tester.runAsync(
      () => repository.saveQuestions(1, session.id, [
        InterviewQuestionDraft(
          questionText: '请解释函数极限的定义。',
          referencePoints: const ['趋近过程'],
          knowledgePoint: '极限定义',
          sourceRecordId: 1,
          sourcePageId: 1,
          evidenceText: '极限内容',
          sourceKind: 'ocr',
          orderIndex: 0,
        ),
      ]),
    ))!;
    final turn = (await tester.runAsync(
      () => repository.upsertTurn(
        userId: 1,
        sessionId: session.id,
        questionId: questions.single.id,
        speaker: 'user',
        text: '当x趋近某值时函数值趋近一个固定值',
        requestKey: 'q1:user:r0',
      ),
    ))!;
    await tester.runAsync(
      () => repository.saveEvaluation(
        1,
        InterviewEvaluation(
          id: 0,
          sessionId: session.id,
          questionId: questions.single.id,
          turnId: turn.id,
          accuracyScore: 30,
          completenessScore: 10,
          logicScore: 10,
          expressionScore: 11,
          totalScore: 61,
          strengths: const ['定义方向正确'],
          weaknesses: const ['缺少例子'],
          suggestions: const ['补充具体例子'],
          evidenceRefs: const [1],
          followUpReferencePoints: const [],
        ),
      ),
    );
    await tester.runAsync(
      () => repository.completeQuestion(1, session.id, questions.single.id),
    );
    await tester.runAsync(
      () => repository.finishSession(
        1,
        session.id,
        report: const {
          'overall_score': 61,
          'knowledge_score': 40,
          'expression_score': 21,
          'completed_count': 1,
          'target_count': 1,
          'cancelled': false,
          'strengths': ['定义方向正确'],
          'weaknesses': ['缺少例子'],
          'suggestions': ['补充具体例子'],
          'weak_points': ['极限定义'],
        },
      ),
    );

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: testTheme,
          debugShowCheckedModeBanner: false,
          home: InterviewResultPage(
            userId: 1,
            sessionId: session.id,
            repository: repository,
          ),
        ),
      ),
    );
    await _settle(tester);

    await _capture(tester, 'result-widget.png');
    expect(find.text('61'), findsOneWidget);
    expect(find.text('84'), findsNothing);
    expect(find.text('合格'), findsOneWidget);
    expect(find.text('完成题数 1 / 1'), findsOneWidget);
    expect(find.text('极限定义'), findsWidgets);
    expect(find.textContaining('补充具体例子'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('再来一次'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('再来一次'), findsOneWidget);
    expect(find.text('复习提纲'), findsOneWidget);
    expect(find.text('知识卡片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _evidence = InterviewEvidence(
  key: 'ocr:1',
  sourceRecordId: 1,
  sourcePageId: 1,
  title: '函数与极限',
  content: '极限内容',
  sourceKind: 'ocr',
);

final _config = LlmProviderConfig(
  id: 1,
  userId: 1,
  provider: LlmProvider.custom,
  apiMode: LlmApiMode.openAiCompatible,
  apiKey: 'k',
  baseUrl: 'https://example.com/v1',
  model: 'm',
  maxTokens: 4096,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

MiniMaxClient _client(List<http.Response> queue) {
  final pending = List<http.Response>.of(queue);
  return MiniMaxClient(
    apiKey: 'k',
    endpoint: Uri.parse('https://example.com/v1/chat/completions'),
    httpClient: MockClient((request) async {
      if (pending.isEmpty) throw StateError('unexpected model call');
      return pending.removeAt(0);
    }),
  );
}

http.Response _response(String content) => http.Response(
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
  }) async {}
  @override
  Future<void> stopSpeaking() async {}
  @override
  Future<void> startRecording() async {
    _text = '';
    _phase.value = VoicePhase.recording;
  }

  @override
  Future<VoiceTranscript> stopRecording() async {
    _phase.value = VoicePhase.idle;
    return VoiceTranscript(text: _text, isFinal: true, durationMs: 900);
  }

  @override
  Future<void> playRecording(String path) async {}
  @override
  Future<void> cancel() async {
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
