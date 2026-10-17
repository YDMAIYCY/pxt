import 'support/empty_learning_task_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/auth_repository.dart';
import 'package:pxt1/database/knowledge_library_repository.dart';
import 'package:pxt1/database/models/knowledge_library_record.dart';
import 'package:pxt1/database/models/source_document_record.dart';
import 'package:pxt1/database/models/user_profile.dart';
import 'package:pxt1/database/source_document_repository.dart';
import 'package:pxt1/ui/pages/tabs/home_tab_page.dart';

void main() {
  testWidgets('HomeTabPage opens QSClaw agent entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            learningTaskRepository: EmptyLearningTaskRepository(),
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
            qsClawPageBuilder: () => const _MarkerPage('qsclaw-opened'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('问 EClaw'), 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text('问 EClaw'));
    await tester.pumpAndSettle();

    expect(find.text('qsclaw-opened'), findsOneWidget);
  });

  testWidgets('HomeTabPage shows the AI interview quick entry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            learningTaskRepository: EmptyLearningTaskRepository(),
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 旧版占位式入口的文案不应再出现。
    expect(find.text('AI 面试官'), findsNothing);
    await tester.scrollUntilVisible(find.text('AI 面试'), 120);
    await tester.pumpAndSettle();
    expect(find.text('AI 面试'), findsOneWidget);
  });

  testWidgets('HomeTabPage renders core Chinese labels without mojibake', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeTabPage(
            learningTaskRepository: EmptyLearningTaskRepository(),
            authRepository: _FakeAuthRepository(),
            sourceDocumentRepository: _FakeSourceDocumentRepository(),
            knowledgeLibraryRepository: _FakeKnowledgeLibraryRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const labels = [
      '\u4eca\u5929\u7684\u5b66\u4e60',
      '\u5b66\u4e60\u6982\u89c8',
      '\u62cd\u7167\u8bc6\u522b',
      '\u5bfc\u5165\u8d44\u6599',
      '\u4e3a\u4f60\u63a8\u8350',
      '\u6211\u7684\u77e5\u8bc6\u5e93',
    ];
    for (final label in labels) {
      await tester.scrollUntilVisible(find.text(label), 120);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    }

    expect(find.textContaining('\u9396'), findsNothing);
    expect(find.textContaining('\u9422'), findsNothing);
  });
}

class _MarkerPage extends StatelessWidget {
  const _MarkerPage(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text(label)));
  }
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

class _FakeSourceDocumentRepository extends SourceDocumentRepository {
  @override
  Future<List<SourceDocumentRecord>> fetchRecentSourceDocuments({
    required int userId,
    int? libraryId,
    bool includeBatchPages = true,
    int limit = 5,
  }) async {
    return const [];
  }
}

class _FakeKnowledgeLibraryRepository extends KnowledgeLibraryRepository {
  @override
  Future<List<KnowledgeLibraryRecord>> fetchLibraries(int userId, {String source = 'all'}) async {
    return const [];
  }

  @override
  Future<List<KnowledgeLibraryStudySummary>> fetchStudySummaries({
    required int userId,
  }) async {
    return const [];
  }
}
