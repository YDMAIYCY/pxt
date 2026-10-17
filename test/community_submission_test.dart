// Platform fixtures isolate image picking without changing pubspec.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/cloud_identity_repository.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/ui/pages/community/publish_question_page.dart';
import 'package:pxt1/ui/pages/community/question_detail_page.dart';

class _LinkedIdentity extends CloudIdentityRepository {
  @override
  Future<String> requireLinked() async => 'fixture-user';
}

class _SubmissionRepository extends CommunityRepository {
  _SubmissionRepository() : super(identity: _LinkedIdentity());

  final publications =
      <
        ({
          String title,
          String body,
          String token,
          List<String> tags,
          List<String> images,
        })
      >[];
  final replies = <({String question, String body, String token})>[];
  final storedQuestions = <String, String>{};
  final storedAnswers = <String, String>{};
  final questionLoads = <String>[];
  int answerLoads = 0, bookmarkLoads = 0, uploads = 0;
  bool failUpload = false, timeoutPublish = false;
  Object? answerFailure;
  Completer<void>? publishResponse, answerResponse;

  @override
  String get uid => 'fixture-user';

  @override
  Future<String> upload(
    String bucket,
    Uint8List bytes,
    String extension, {
    String? conversation,
    String? token,
    String? expectedOwner,
  }) async {
    uploads++;
    if (failUpload) throw const CloudFailure('图片上传失败');
    return 'fixture-user/$token.$extension';
  }

  @override
  Future<String> publish({
    required String title,
    required String body,
    required String token,
    List<String> tags = const [],
    List<String> images = const [],
  }) async {
    publications.add((
      title: title,
      body: body,
      token: token,
      tags: tags,
      images: images,
    ));
    final id = storedQuestions.putIfAbsent(token, () => 'fixture-question');
    if (publications.length == 1) {
      if (publishResponse != null) await publishResponse!.future;
      if (timeoutPublish) throw TimeoutException('Response lost after commit');
    }
    return id;
  }

  @override
  Future<void> answer(String question, String body, String token) async {
    replies.add((question: question, body: body, token: token));
    // The first write succeeds even when its response fails.
    storedAnswers.putIfAbsent(token, () => body);
    if (replies.length == 1) {
      if (answerResponse != null) await answerResponse!.future;
      if (answerFailure != null) throw answerFailure!;
    }
  }

  @override
  Future<Json> question(String id) async {
    questionLoads.add(id);
    return {
      'id': id,
      'author_id': 'fixture-author',
      'title': 'Fixture question',
      'body': 'Fixture description',
      'profile': {'id': 'fixture-author', 'nickname': 'Fixture author'},
      'created_at': '2026-10-16T00:00:00Z',
      'updated_at': '2026-10-16T00:00:00Z',
      'image_paths': <String>[],
      'tags': <String>[],
      'accepted_answer_id': null,
    };
  }

  @override
  Future<List<Json>> answers(String id, {int offset = 0}) async {
    answerLoads++;
    return [
      for (final entry in storedAnswers.entries)
        {
          'id': entry.key,
          'author_id': 'fixture-user',
          'body': entry.value,
          'profile': {'id': 'fixture-user', 'nickname': 'Fixture user'},
          'created_at': '2026-10-16T00:00:00Z',
        },
    ];
  }

  @override
  Future<bool> bookmarked(String id) async {
    bookmarkLoads++;
    return false;
  }
}

class _ImagePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
    ),
    path: 'fixture.png',
    name: 'fixture.png',
    mimeType: 'image/png',
  );
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

TextField _input(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label));

void _expectLocked(WidgetTester tester, String label) {
  expect(_input(tester, label).enabled, isFalse);
  final editable = find.descendant(
    of: _field(label),
    matching: find.byType(EditableText),
  );
  expect(tester.widget<EditableText>(editable).readOnly, isTrue);
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 2000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: page));
  await tester.pumpAndSettle();
}

Future<void> _tapButton(WidgetTester tester, String text) async {
  final button = find.widgetWithText(FilledButton, text);
  await tester.ensureVisible(button);
  await tester.tap(button);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final previous = ImagePickerPlatform.instance;
    ImagePickerPlatform.instance = _ImagePicker();
    addTearDown(() => ImagePickerPlatform.instance = previous);
  });

  testWidgets('publish timeout freezes inputs and confirms the same snapshot', (
    tester,
  ) async {
    final repo = _SubmissionRepository()
      ..timeoutPublish = true
      ..publishResponse = Completer<void>();
    await _pumpPage(
      tester,
      PublishQuestionPage(
        initialTitle: 'Original title',
        initialBody: 'Original body',
        repository: repo,
      ),
    );
    await tester.enterText(_field('知识标签'), 'math，limits');
    await tester.tap(find.widgetWithText(OutlinedButton, '相册'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('移除图片'), findsOneWidget);
    await _tapButton(tester, '发布问题');
    await tester.pump();
    expect(repo.publications, hasLength(1));
    for (final label in ['问题标题', '问题描述', '知识标签']) {
      _expectLocked(tester, label);
    }
    repo.publishResponse!.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('结果待确认，请重试确认'), findsOneWidget);
    expect(_input(tester, '问题描述').controller!.text, 'Original body');
    for (final label in ['问题标题', '问题描述', '知识标签']) {
      _expectLocked(tester, label);
    }
    for (final label in ['相册', '拍照']) {
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, label))
            .onPressed,
        isNull,
      );
    }
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '引用知识卡片'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '移除图片',
            ),
          )
          .onPressed,
      isNull,
    );
    await _tapButton(tester, '重试确认');
    await tester.pumpAndSettle();
    expect(repo.publications, hasLength(2));
    final first = repo.publications.first, retry = repo.publications.last;
    expect(first.title, 'Original title');
    expect(first.body, 'Original body');
    expect(first.tags, ['math', 'limits']);
    expect(first.images, hasLength(1));
    expect(first.token, isNotEmpty);
    expect(retry, first);
    expect(repo.uploads, 1);
    expect(repo.storedQuestions, hasLength(1));
    expect(find.byType(PublishQuestionPage), findsNothing);
    expect(find.byType(QuestionDetailPage), findsOneWidget);
    expect(repo.questionLoads, ['fixture-question']);
    expect(repo.answerLoads, 1);
    expect(repo.bookmarkLoads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('upload failure before publish keeps the draft editable', (
    tester,
  ) async {
    final repo = _SubmissionRepository()..failUpload = true;
    await _pumpPage(
      tester,
      PublishQuestionPage(
        initialTitle: 'Before upload',
        initialBody: 'Before upload body',
        repository: repo,
      ),
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '相册'));
    await tester.pumpAndSettle();
    await _tapButton(tester, '发布问题');
    await tester.pumpAndSettle();
    expect(repo.publications, isEmpty);
    expect(find.text('图片上传失败'), findsOneWidget);
    expect(find.textContaining('结果待确认'), findsNothing);
    for (final label in ['问题标题', '问题描述', '知识标签']) {
      expect(_input(tester, label).enabled, isTrue);
    }
    await tester.enterText(_field('问题标题'), 'Edited title');
    await tester.enterText(_field('问题描述'), 'Edited body');
    await tester.enterText(_field('知识标签'), 'edited');
    await tester.tap(find.byTooltip('移除图片'));
    await tester.pumpAndSettle();
    await _tapButton(tester, '发布问题');
    await tester.pumpAndSettle();
    expect(repo.publications.single.title, 'Edited title');
    expect(repo.publications.single.body, 'Edited body');
    expect(repo.publications.single.tags, ['edited']);
    expect(repo.publications.single.images, isEmpty);
    expect(find.byType(QuestionDetailPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'answer success clears only after confirmation and renews token',
    (tester) async {
      final repo = _SubmissionRepository()..answerResponse = Completer<void>();
      await _pumpPage(
        tester,
        QuestionDetailPage(questionId: 'fixture-question', repository: repo),
      );
      await tester.enterText(_field('写下你的回答'), 'First answer');
      await _tapButton(tester, '发布回答');
      await tester.pump();
      expect(repo.replies, hasLength(1));
      expect(_input(tester, '写下你的回答').controller!.text, 'First answer');
      _expectLocked(tester, '写下你的回答');
      repo.answerResponse!.complete();
      await tester.pumpAndSettle();
      expect(_input(tester, '写下你的回答').controller!.text, isEmpty);
      expect(_input(tester, '写下你的回答').enabled, isTrue);
      await tester.enterText(_field('写下你的回答'), 'Second answer');
      await _tapButton(tester, '发布回答');
      await tester.pumpAndSettle();
      expect(repo.replies.last.body, 'Second answer');
      expect(repo.replies.last.token, isNot(repo.replies.first.token));
      expect(repo.storedAnswers, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  for (final failure in [
    TimeoutException('Response lost after commit'),
    const CloudFailure('网络已断开'),
  ]) {
    testWidgets('answer ${failure.runtimeType} retries without losing text', (
      tester,
    ) async {
      final repo = _SubmissionRepository()..answerFailure = failure;
      await _pumpPage(
        tester,
        QuestionDetailPage(questionId: 'fixture-question', repository: repo),
      );
      await tester.enterText(_field('写下你的回答'), 'Original answer');
      await _tapButton(tester, '发布回答');
      await tester.pumpAndSettle();
      expect(_input(tester, '写下你的回答').controller!.text, 'Original answer');
      _expectLocked(tester, '写下你的回答');
      expect(find.textContaining('结果待确认，请重试确认'), findsOneWidget);
      await _tapButton(tester, '重试确认');
      await tester.pumpAndSettle();
      expect(repo.replies, hasLength(2));
      expect(repo.replies.first.body, 'Original answer');
      expect(repo.replies.last, repo.replies.first);
      expect(repo.storedAnswers.values.single, 'Original answer');
      expect(_input(tester, '写下你的回答').controller!.text, isEmpty);
      expect(_input(tester, '写下你的回答').enabled, isTrue);
      expect(find.textContaining('结果待确认'), findsNothing);
      expect(repo.questionLoads, ['fixture-question', 'fixture-question']);
      expect(repo.answerLoads, 2);
      expect(repo.bookmarkLoads, 2);
      expect(tester.takeException(), isNull);
    });
  }
}
