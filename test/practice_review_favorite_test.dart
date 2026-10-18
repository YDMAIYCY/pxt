import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/ai_generation_repository.dart';
import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/favorite_repository.dart';
import 'package:pxt1/database/models/ai_result_records.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/ui/pages/practice_review_page.dart';

void main() {
  testWidgets('practice review page toggles question favorite', (tester) async {
    final favoriteRepository = _FakeFavoriteRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: PracticeReviewPage(
          authRepository: _FakeAuthRepository(),
          aiGenerationRepository: _FakeAiGenerationRepository(),
          favoriteRepository: favoriteRepository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('刷练习题'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('收藏'));
    await tester.pumpAndSettle();

    expect(
      favoriteRepository.lastTargetType,
      FavoriteTargetType.practiceQuestion,
    );
    expect(favoriteRepository.lastTargetId, 21);
    expect(find.byTooltip('取消收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuthRepository extends AuthRepository {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    return const UserProfile(
      id: 7,
      username: 'tester',
      displayName: 'tester',
      bio: '',
      gender: '',
      avatarStyle: ProfilePresetIds.defaultAvatarStyle,
      backgroundStyle: ProfilePresetIds.defaultBackgroundStyle,
    );
  }
}

class _FakeAiGenerationRepository extends AiGenerationRepository {
  @override
  Future<List<PracticeQuestionWithDocument>> fetchReviewQueueByUser({
    required int userId,
    int? libraryId,
    DateTime? now,
    int limit = 100,
  }) async {
    return [
      PracticeQuestionWithDocument(
        question: PracticeQuestionRecord(
          id: 21,
          documentId: 3,
          questionText: '函数单调性如何判断？',
          answerText: '看导数符号。',
          analysisText: '导数大于 0 单调递增，小于 0 单调递减。',
          difficulty: 'easy',
          reviewStatus: PracticeQuestionReviewStatus.pending,
          lastUserAnswer: null,
          lastReviewedAt: null,
          wrongCount: 0,
          nextReviewAt: DateTime(2026),
          masteryScore: 0,
          reviewIntervalDays: 0,
          correctStreak: 0,
          parentQuestionId: null,
          questionKind: PracticeQuestionKind.shortAnswer,
          optionsJson: null,
          rubricJson: null,
          expectedKeywordsJson: null,
          createdAt: DateTime(2026),
        ),
        documentTitle: '高数资料',
      ),
    ];
  }
}

class _FakeFavoriteRepository extends FavoriteRepository {
  final Set<String> keys = <String>{};
  String? lastTargetType;
  int? lastTargetId;

  @override
  Future<Set<String>> fetchFavoriteKeys(int userId) async {
    return keys;
  }

  @override
  Future<bool> toggleFavorite({
    required int userId,
    required String targetType,
    required int targetId,
  }) async {
    lastTargetType = targetType;
    lastTargetId = targetId;
    final key = FavoriteRepository.favoriteKey(targetType, targetId);
    if (keys.contains(key)) {
      keys.remove(key);
      return false;
    }
    keys.add(key);
    return true;
  }
}
