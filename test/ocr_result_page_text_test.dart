import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/models/ocr_text_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/ocr_text_repository.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/ocr_result_page.dart';

void main() {
  testWidgets(
    'OCR result page renders Chinese labels instead of question marks',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: OcrResultPage(
            documentId: 1,
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            ocrTextRepository: _FakeOcrTextRepository(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('OCR 结果'), findsOneWidget);
      expect(find.text('重试 OCR'), findsOneWidget);
      expect(find.text('框选重试'), findsOneWidget);
      expect(find.text('AI 修复'), findsOneWidget);
      expect(find.text('保存修改'), findsOneWidget);
      expect(find.text('OCR 质量'), findsOneWidget);
      expect(find.text('原始识别文本 rawText'), findsOneWidget);
      expect(find.text('清洗后文本 cleanText'), findsOneWidget);
      expect(find.text('确认文本 finalText'), findsOneWidget);
      expect(find.text('确认 finalText 并用于后续 AI 生成'), findsNothing);

      final visibleTexts = tester.widgetList<Text>(find.byType(Text));
      for (final textWidget in visibleTexts) {
        expect(textWidget.data ?? '', isNot(contains('???')));
      }
    },
  );
}

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    return const UserProfile(
      id: 1,
      username: 'tester',
      displayName: 'tester',
      bio: '',
      gender: '',
      avatarStyle: ProfilePresetIds.defaultAvatarStyle,
      backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
    );
  }
}

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<SourceDocumentRecord?> getSourceDocumentById({
    required int userId,
    required int documentId,
  }) async {
    return SourceDocumentRecord(
      id: documentId,
      userId: userId,
      libraryId: 1,
      sourceType: SourceDocumentSourceType.galleryImport,
      imagePath: 'source_documents/page.png',
      title: '拍照资料 06-02 16:50',
      createdAt: DateTime(2026, 6, 2, 16, 50),
      ocrStatus: SourceDocumentOcrStatus.success,
      aiDone: false,
    );
  }
}

class _FakeOcrTextRepository extends OcrTextRepository {
  @override
  Future<OcrTextRecord?> getByDocumentId(int documentId) async {
    return OcrTextRecord(
      id: 1,
      documentId: documentId,
      rawText: '原始 OCR 文本',
      cleanText: '清洗后 OCR 文本',
      finalText: '确认后的 finalText',
      qualityScore: 92,
      qualityLevel: 'high',
      language: 'zh-CN',
      createdAt: DateTime(2026, 6, 2),
      updatedAt: DateTime(2026, 6, 2),
    );
  }
}
