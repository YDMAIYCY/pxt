import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/ui/pages/community/social_pages.dart';

class _SearchRepository extends CommunityRepository {
  final calls = <(String, int)>[];
  final pending = <Completer<List<Json>>>[];

  @override
  Future<List<Json>> searchUsers(String query, {int offset = 0}) {
    calls.add((query, offset));
    final result = Completer<List<Json>>();
    pending.add(result);
    return result.future;
  }
}

Json _user(String nickname) => {
  'id': nickname,
  'nickname': nickname,
  'public_id': 'ZX-$nickname',
};

void main() {
  testWidgets(
    'typing yk automatically searches after debounce; clearing resets',
    (tester) async {
      final repo = _SearchRepository();
      await tester.pumpWidget(
        MaterialApp(home: UserSearchPage(repository: repo)),
      );
      await tester.enterText(find.byType(TextField), 'y');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'yk');
      await tester.pump(const Duration(milliseconds: 349));
      expect(repo.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(repo.calls, [('yk', 0)]);
      repo.pending.single.complete([_user('yk')]);
      await tester.pumpAndSettle();
      expect(find.text('yk'), findsNWidgets(2));
      expect(find.text('ID：ZX-yk'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('输入昵称或公开 ID 搜索同学'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    },
  );

  testWidgets(
    'new query ignores late responses and supports empty/error/retry',
    (tester) async {
      final repo = _SearchRepository();
      await tester.pumpWidget(
        MaterialApp(home: UserSearchPage(repository: repo)),
      );
      await tester.enterText(find.byType(TextField), 'old');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'yk');
      await tester.tap(find.byTooltip('搜索用户'));
      await tester.pump();
      repo.pending[1].complete([_user('yk')]);
      await tester.pumpAndSettle();
      repo.pending[0].complete(List.generate(20, (_) => _user('old')));
      await tester.pumpAndSettle();
      expect(find.text('ID：ZX-yk'), findsOneWidget);
      expect(find.text('ID：ZX-old'), findsNothing);
      expect(find.text('加载更多'), findsNothing);
      await tester.enterText(find.byType(TextField), 'empty');
      await tester.pump(const Duration(milliseconds: 350));
      repo.pending[2].complete([]);
      await tester.pumpAndSettle();
      expect(find.text('没有找到用户'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'retry');
      await tester.pump(const Duration(milliseconds: 350));
      repo.pending[3].completeError(const CloudFailure('网络已断开'));
      await tester.pumpAndSettle();
      expect(find.textContaining('网络已断开'), findsOneWidget);
      await tester.tap(find.text('重新加载'));
      await tester.pump();
      repo.pending[4].complete([_user('retry')]);
      await tester.pumpAndSettle();
      expect(find.text('ID：ZX-retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
