import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:sqflite/sqflite.dart';
import 'package:pxt1/camera/image_input_service.dart';
import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/document_batch_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/llm_config_repository.dart';
import 'package:pxt1/database/models/document_batch_record.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/practice_session_repository.dart';
import 'package:pxt1/generator/learning_resource_service.dart';
import 'package:pxt1/generator/library_practice_service.dart';
import 'package:pxt1/ocr/local_ocr_client.dart';
import 'package:pxt1/ui/pages/rich_note_editor_page.dart';
import 'package:pxt1/ui/widgets/record_mindmap_view.dart';
import 'package:pxt1/ui/theme/app_theme.dart';
import 'package:pxt1/llm/minimax_client.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final results = <String, Object?>{};
  late Directory folder;
  late AppDatabase fixture;
  late Database db;
  int? documentId;
  setUpAll(() async {
    folder = await Directory(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'phase03-device-${DateTime.now().millisecondsSinceEpoch}',
      ),
    ).create();
    fixture = await AppDatabase.openForTesting(
      databaseFactory,
      path: p.join(folder.path, 'fixture.db'),
    );
    db = await fixture.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('users', {
      'id': 1,
      'username': 'phase03-fixture',
      'password_hash': 'test',
      'password_salt': 'test',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('knowledge_libraries', {
      'id': 1,
      'user_id': 1,
      'name': '数据库基础',
      'created_at': now,
      'updated_at': now,
    });
  });
  tearDownAll(() async {
    binding.reportData = results;
    final report = File(
      p.join(
        (await getApplicationDocumentsDirectory()).path,
        'phase03_device_results.json',
      ),
    );
    await report.writeAsString(jsonEncode(results));
    await db.close();
    await folder.delete(recursive: true);
  });
  testWidgets('device database upgrades without losing existing user data', (
    tester,
  ) async {
    final live = await AppDatabase.instance.database;
    expect(await live.getVersion(), 16);
    expect(await live.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    final docs = await live.rawQuery('SELECT COUNT(*) n FROM source_documents');
    final resources = await live.rawQuery(
      'SELECT COUNT(*) n FROM learning_resources',
    );
    expect(docs.single['n'], greaterThanOrEqualTo(2));
    expect(resources.single['n'], greaterThanOrEqualTo(8));
    results['migration'] = {
      'version': await live.getVersion(),
      'documents': docs.single['n'],
      'resources': resources.single['n'],
    };
  });
  testWidgets(
    'native Chinese OCR and native 20-page PDF rendering feed one record',
    (tester) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      final paragraph =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 36))
                ..pushStyle(ui.TextStyle(color: Colors.black))
                ..addText(
                  '数据库基础\n事务的原子性：全部成功或者全部失败。\n'
                  '隔离性：并发事务不应互相干扰。\nDatabase transaction atomicity.',
                ))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 850));
      canvas.drawParagraph(paragraph, const Offset(40, 80));
      final image = await recorder.endRecording().toImage(960, 640);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final imagePath = p.join(folder.path, 'ocr.png');
      await File(imagePath).writeAsBytes(bytes.buffer.asUint8List());
      image.dispose();
      final recognized = await LocalOcrClient().recognizeImage(
        imagePath: imagePath,
      );
      expect(recognized.cleanText, contains('事务'));
      final doc = await SourceDocumentRepository(database: fixture)
          .createSourceDocument(
            userId: 1,
            libraryId: 1,
            sourceType: 'gallery_import',
            imagePath: imagePath,
            title: '事务与隔离',
          );
      documentId = doc.id;
      await OcrTextRepository(database: fixture).upsertOcrText(
        documentId: doc.id,
        rawText: recognized.rawText,
        cleanText: recognized.cleanText,
      );
      final pdfPath = p.join(folder.path, 'twenty.pdf');
      await File(pdfPath).writeAsBytes(_pdf(20));
      final pages = await const PdfPageRenderer().renderPdf(
        pdfPath: pdfPath,
        outputDirectoryPath: folder.path,
        outputPrefix: 'native-page',
        maxPages: 80,
        maxLongestSide: 1600,
        maxRenderedPixels: 2200000,
      );
      expect(pages, hasLength(20));
      final batch = await DocumentBatchRepository(database: fixture)
          .createDocumentBatch(
            userId: 1,
            libraryId: 1,
            sourceType: 'pdf',
            pageSourceType: 'pdf_page',
            title: '数据库讲义',
            originalFilePath: pdfPath,
            pages: pages
                .map(
                  (page) => DocumentBatchPageDraft(
                    savedPath: page.savedPath,
                    title: 'PDF 第 ${page.pageNumber} 页',
                    pageNumber: page.pageNumber,
                    originalFilePath: pdfPath,
                    filePageNumber: page.pageNumber,
                  ),
                )
                .toList(),
          );
      final records = await ImportRecordRepository(database: fixture).list(1);
      expect(records, hasLength(2));
      expect(
        records.singleWhere((r) => r.anchor.batchId == batch.id).pages,
        hasLength(20),
      );
      final firstPdf = await LocalOcrClient().recognizeImage(
        imagePath: pages.first.savedPath,
      );
      expect(firstPdf.cleanText.toLowerCase(), contains('database'));
      results['native_import'] = {
        'chinese_ocr': true,
        'pdf_pages': pages.length,
        'pdf_ocr': true,
        'record_count': records.length,
      };
    },
  );
  testWidgets(
    'Chinese rich text persists and native mindmap supports touch interaction',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
          locale: const Locale('zh', 'CN'),
          home: const RichNoteEditorPage(content: '{"content":"事务是一个整体"}'),
        ),
      );
      await tester.pumpAndSettle();
      final editor = tester.widget<QuillEditor>(find.byType(QuillEditor));
      expect(editor.controller.document.toPlainText().trim(), '事务是一个整体');
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      final raw = tester.state<QuillRawEditorState>(
        find.byType(QuillRawEditor),
      );
      await tester.pump();
      final current = raw.currentTextEditingValue!;
      debugPrint(
        'Quill input lengths: remote=${current.text.length}, document=${editor.controller.document.length}',
      );
      raw.updateEditingValue(
        TextEditingValue(
          text: '原子性：全部成功或全部失败。${current.text}',
          selection: const TextSelection.collapsed(offset: 14),
        ),
      );
      await tester.pumpAndSettle();
      expect(editor.controller.document.toPlainText(), contains('全部成功或全部失败'));
      final saved = editor.controller.document.toDelta().toJson();
      expect(
        Document.fromJson(saved).toPlainText(),
        editor.controller.document.toPlainText(),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: RecordMindmapView(
                text: '数据库基础\n  事务\n    原子性\n    隔离性\n  索引',
                onSource: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('原子性'), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(-50, -20));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      results['mobile_editors'] = {'chinese_input': true, 'graph_touch': true};
    },
  );
  testWidgets(
    'configured real model generates record knowledge and grounded library questions',
    (tester) async {
      final user = await AuthRepository().getCurrentUserProfile();
      expect(user, isNotNull, reason: '真模型验收需要现有登录用户');
      final config = await LlmConfigRepository().getByUserId(user!.id);
      expect(config?.isConfigured, isTrue, reason: '真模型验收需要有效模型设置');
      final doc = await SourceDocumentRepository(
        database: fixture,
      ).getSourceDocumentById(userId: 1, documentId: documentId!);
      final network = _DiagnosticClient();
      final client = MiniMaxClient.fromConfig(config!, httpClient: network);
      final service = LearningResourceService(
        database: fixture,
        client: client,
      );
      final notes = await service.generate(doc!, config, 'notes');
      expect(notes.content.trim(), isNotEmpty);
      final questions =
          await LibraryPracticeService(
            database: fixture,
            client: client,
          ).generate(
            const PracticeScope(userId: 1, libraryId: 1, recordId: 1),
            config,
            count: 5,
          );
      expect(questions, hasLength(5));
      expect(await db.query('practice_questions'), hasLength(5));
      results['real_model'] = {
        'notes': true,
        'grounded_questions': questions.length,
      };
    },
    timeout: const Timeout(Duration(minutes: 4)),
    skip: !const bool.fromEnvironment(
      'PHASE03_MODEL_CHECK',
      defaultValue: true,
    ),
  );
  testWidgets(
    'Chinese speech playback, cancellation and microphone capture are available',
    (tester) async {
      final tts = FlutterTts();
      expect(
        await tts.isLanguageAvailable('zh-CN'),
        isTrue,
        reason: '需要可用的中文 TTS 引擎',
      );
      await tts.setLanguage('zh-CN');
      await tts.setSpeechRate(.45);
      final started = Completer<void>();
      tts.setStartHandler(() {
        if (!started.isCompleted) started.complete();
      });
      final playback = tts.speak(
        '这是阶段零语音测试。请解释事务的原子性，'
        '事务要求所有操作一起成功，或者一起失败。',
      );
      await started.future.timeout(const Duration(seconds: 15));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      final watch = Stopwatch()..start();
      await tts.stop();
      results['tts'] = {
        'chinese_playback_started': true,
        'cancel_ms': watch.elapsedMilliseconds,
      };
      await playback;
      final recorder = AudioRecorder();
      expect(await recorder.hasPermission(), isTrue, reason: '需要麦克风权限');
      final path = p.join(folder.path, 'microphone.m4a');
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      final recorded = await recorder.stop();
      expect(recorded, isNotNull);
      expect(await File(recorded!).length(), greaterThan(100));
      await recorder.dispose();
      final recognition = SpeechToText();
      var available = false;
      try {
        available = await recognition.initialize();
      } catch (_) {}
      results['speech'] = {
        'microphone_capture': true,
        'system_recognition_available': available,
      };
      results['speech_gap'] = available
          ? null
          : '设备无系统识别服务，用户确认暂无云 STT，收发闭环未验收';
      await recognition.stop();
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

class _DiagnosticClient extends http.BaseClient {
  final _client = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _client.send(request);
    } catch (error) {
      // The diagnostic contains no request headers or body.
      debugPrint('Device network diagnostic: $error');
      rethrow;
    }
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

List<int> _pdf(int count) {
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [${List.generate(count, (i) => '${4 + i * 2} 0 R').join(' ')}] /Count $count >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  for (var i = 0; i < count; i++) {
    final stream =
        'BT /F1 18 Tf 50 740 Td (Database transaction page ${i + 1}) Tj '
        '0 -40 Td (Atomicity means all operations succeed or all fail.) Tj ET';
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Resources << /Font << /F1 3 0 R >> >> /Contents ${5 + i * 2} 0 R >>',
    );
    objects.add('<< /Length ${stream.length} >>\nstream\n$stream\nendstream');
  }
  var data = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(data.length);
    data += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = data.length;
  data += 'xref\n0 ${objects.length + 1}\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    data += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  data +=
      'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return ascii.encode(data);
}
