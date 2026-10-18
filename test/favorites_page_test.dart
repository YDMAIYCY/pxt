import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/favorite_repository.dart';
import 'package:pxt1/ui/pages/tabs/profile_tab_page.dart';

void main() {
  testWidgets('favorites page opens full content and supports cancel actions', (
    tester,
  ) async {
    final repository = _FakeFavoriteRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: FavoritesPage(userId: 7, favoriteRepository: repository),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('练习题'), findsOneWidget);
    expect(find.text('错题'), findsNothing);

    await tester.tap(find.text('练习题'));
    await tester.pumpAndSettle();

    expect(find.text('函数单调性如何判断？'), findsOneWidget);
    await tester.tap(find.text('函数单调性如何判断？'));
    await tester.pumpAndSettle();

    expect(find.text('完整内容'), findsOneWidget);
    expect(find.textContaining('题目：函数单调性如何判断？'), findsWidgets);
    expect(find.textContaining('A. 看导数符号'), findsWidgets);
    expect(find.textContaining('答案：A'), findsWidgets);
    expect(find.textContaining('解析：导数大于 0 单调递增。'), findsWidgets);

    await tester.tap(find.text('原有笔记与重点'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('取消高亮'));
    await tester.tap(find.text('取消高亮'));
    await tester.pumpAndSettle();
    expect(repository.lastHighlight, isNull);

    await tester.ensureVisible(find.text('删除笔记'));
    await tester.tap(find.text('删除笔记'));
    await tester.pumpAndSettle();
    expect(repository.lastNote, isNull);

    await tester.tap(find.text('取消收藏'));
    await tester.pumpAndSettle();
    expect(repository.removedFavoriteId, 9);

    expect(tester.takeException(), isNull);
  });
}

class _FakeFavoriteRepository extends FavoriteRepository {
  String? lastNote = '原笔记';
  String? lastHighlight = '原高亮';
  int? removedFavoriteId;

  @override
  Future<List<FavoriteCategorySummary>> fetchCategorySummaries(
    int userId,
  ) async {
    return const [
      FavoriteCategorySummary(
        type: FavoriteTargetType.practiceQuestion,
        title: '练习题',
        count: 1,
        iconName: 'quiz',
      ),
    ];
  }

  @override
  Future<List<FavoriteItemRecord>> fetchFavoritesByType({
    required int userId,
    required String targetType,
    int limit = 200,
  }) async {
    return [
      FavoriteItemRecord(
        favoriteId: 9,
        targetType: FavoriteTargetType.practiceQuestion,
        targetId: 11,
        title: '函数单调性如何判断？',
        subtitle: '高数资料 / 练习题',
        body:
            '难度：easy\n\n题目：函数单调性如何判断？\n\n选项：\nA. 看导数符号\nB. 看图像颜色\n\n答案：A\n\n解析：导数大于 0 单调递增。',
        note: lastNote,
        highlightText: lastHighlight,
        createdAt: DateTime(2026),
      ),
    ];
  }

  @override
  Future<void> updateFavoriteNoteOnly({
    required int favoriteId,
    required String note,
  }) async {
    lastNote = note.trim().isEmpty ? null : note.trim();
  }

  @override
  Future<void> updateFavoriteHighlightOnly({
    required int favoriteId,
    required String highlightText,
  }) async {
    final normalizedHighlight = highlightText.trim();
    lastHighlight = normalizedHighlight.isEmpty ? null : normalizedHighlight;
  }

  @override
  Future<void> removeFavoriteById(int favoriteId) async {
    removedFavoriteId = favoriteId;
  }
}
