import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/import_record_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/ui/pages/home_page.dart';
import 'package:pxt1/ui/pages/knowledge_record_list_page.dart';
import 'package:pxt1/ui/pages/import_record_detail_page.dart';
import 'package:pxt1/ui/pages/record_source_page.dart';
import 'package:pxt1/ui/pages/record_results_page.dart';
import 'package:pxt1/ui/pages/practice_review_page.dart';
import 'package:pxt1/ui/widgets/knowledge_book_cover.dart';
import 'package:pxt1/ui/theme/app_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('read-only production hierarchy on existing Android database', (
    tester,
  ) async {
    final auth = AuthRepository();
    await auth.ensureInitialized();
    final user = await auth.getCurrentUserProfile();
    expect(user, isNotNull, reason: '需要设备中已有有效登录会话');
    final repository = ImportRecordRepository();
    final records = await repository.list(user!.id);
    expect(records, isNotEmpty, reason: '该验收只读取已有资料，不注入演示数据');
    final libraries = await KnowledgeLibraryRepository().fetchLibraries(
      user.id,
    );
    final record = records.first;
    final library = libraries.singleWhere((l) => l.id == record.libraryId);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const HomePage(initialTab: 1),
      ),
    );
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01-bookshelf');
    final book = find.byWidgetPredicate(
      (w) => w is KnowledgeBookCover && w.title == library.name,
    );
    await tester.ensureVisible(book);
    await tester.tap(book);
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.text('知识库'), findsWidgets);
    await binding.takeScreenshot('02-records');
    final tile = find.byWidgetPredicate(
      (w) => w is ImportRecordTile && w.record.id == record.id,
    );
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.byType(ImportRecordDetailPage), findsOneWidget);
    await binding.takeScreenshot('03-record-detail');
    await tester.ensureVisible(find.text('原始资料 / OCR 文本'));
    await tester.tap(find.text('原始资料 / OCR 文本'));
    await tester.pumpAndSettle();
    expect(find.byType(RecordSourcePage), findsOneWidget);
    await binding.takeScreenshot('04-original-source');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if ((record.counts['knowledge_cards'] ?? 0) > 0) {
      await tester.ensureVisible(find.text('知识卡片'));
      await tester.tap(find.text('知识卡片'));
      await tester.pumpAndSettle();
      expect(find.byType(RecordResultsPage), findsOneWidget);
      await binding.takeScreenshot('05-knowledge-cards');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    if ((record.counts['mindmap_texts'] ?? 0) > 0) {
      await tester.ensureVisible(find.text('思维导图'));
      await tester.tap(find.text('思维导图'));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(-90, -25));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('07-mindmap');
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    if ((record.counts['practice_questions'] ?? 0) > 0) {
      await tester.ensureVisible(find.text('练习题'));
      await tester.tap(find.text('练习题'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始答题').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PracticeReviewPage>(find.byType(PracticeReviewPage))
            .recordId,
        record.id,
      );
      await binding.takeScreenshot('08-record-practice');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('错题解析'));
    await binding.takeScreenshot('06-detail-outcomes');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('学习资料知识库'), findsOneWidget);
    expect(
      (await repository.list(user.id)).map((r) => r.id).toList(),
      records.map((r) => r.id).toList(),
    );
    expect(tester.takeException(), isNull);
  });
}
