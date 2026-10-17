import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pxt1/community/chat_outbox_repository.dart';
import 'package:pxt1/community/cloud_backend.dart';
import 'package:pxt1/community/cloud_identity_repository.dart';
import 'package:pxt1/community/community_repository.dart';
import 'package:pxt1/ui/pages/community/chat_page.dart';
import 'package:pxt1/ui/pages/community/social_pages.dart';

const _a = '10000000-0000-4000-8000-000000000001';
const _b = '20000000-0000-4000-8000-000000000002';

// No SDK connection, database, secure storage, or platform picker is used.
class _Channel implements RealtimeChannel {
  _Channel(this.name);
  final String name;
  void Function(RealtimeSubscribeStatus, Object?)? status;
  VoidCallback? change;

  @override
  RealtimeChannel subscribe([
    void Function(RealtimeSubscribeStatus, Object?)? callback,
    Duration? timeout,
  ]) {
    status = callback;
    return this;
  }

  @override
  RealtimeChannel onPostgresChanges({
    required PostgresChangeEvent event,
    String? schema,
    String? table,
    PostgresChangeFilter? filter,
    List<PostgresChangeFilter>? filters,
    List<String>? select,
    required void Function(PostgresChangePayload) callback,
  }) {
    change = () => callback(
      PostgresChangePayload(
        schema: 'public',
        table: table!,
        commitTimestamp: DateTime.utc(2026),
        eventType: event,
        newRecord: const {},
        oldRecord: const {},
        errors: null,
      ),
    );
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Client implements SupabaseClient {
  final channels = <_Channel>[], removed = <RealtimeChannel>[];
  @override
  RealtimeChannel channel(
    String name, {
    RealtimeChannelConfig opts = const RealtimeChannelConfig(),
  }) {
    final channel = _Channel(name);
    channels.add(channel);
    return channel;
  }

  @override
  Future<String> removeChannel(RealtimeChannel channel) async {
    removed.add(channel);
    return 'ok';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Identity implements CloudIdentityRepository {
  _Identity(this.repo);
  final _Repository repo;
  @override
  Future<String> requireLinked() async {
    final uuid = repo.uid;
    await repo.pause('identity');
    return uuid;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Auth extends ValueNotifier<String?> {
  _Auth() : super(_a);
  bool get listening => hasListeners;
}

class _Repository extends CommunityRepository {
  final auth = _Auth();
  final socket = _Client();
  Future<void> Function(String)? before;
  Future<List<Json>> Function(int)? notificationRequest;
  bool access = true;
  int messageCalls = 0, notificationCalls = 0, readCalls = 0;
  Future<void> pause(String stage) async => await before?.call(stage);
  @override
  String get uid => auth.value ?? (throw const CloudFailure('请先登录智学帮'));
  @override
  SupabaseClient get client => socket;
  @override
  CloudIdentityRepository get identity => _Identity(this);
  @override
  Future<List<Json>> inbox() async {
    await pause('inbox');
    return access
        ? [
            {
              'id': 'conversation',
              'profile': {'nickname': '同学'},
            },
          ]
        : [];
  }

  @override
  Future<List<Json>> messages(String id, {Json? before}) async {
    final uuid = uid;
    messageCalls++;
    await pause(before == null ? 'messages' : 'history');
    return [
      {
        'id': 'message-$uuid',
        'sender_id': uuid,
        'body': 'message:$uuid',
        'created_at': '2026-10-16T00:00:00Z',
      },
    ];
  }

  @override
  Future<void> markRead(String conversation, String message) async {
    readCalls++;
    await pause('markRead');
  }

  @override
  Future<List<Json>> notifications({int offset = 0}) async {
    notificationCalls++;
    if (notificationRequest != null) return notificationRequest!(offset);
    return [_notification(uid)];
  }

  @override
  Future<void> readNotification(String id) => pause('readNotification');
}

Json _notification(String name) => {
  'id': name,
  'kind': 'answer',
  'actor': {'nickname': name},
  'created_at': '2026-10-16T00:00:00Z',
};

class _Outbox implements ChatOutboxRepository {
  _Outbox(this.repo);
  final _Repository repo;
  final items = <Json>[];
  final errors = <String, Object>{};
  @override
  Future<List<Json>> pending(String conversation) async {
    final uuid = repo.uid;
    final rows = items
        .where((row) => row['auth_uuid'] == null || row['auth_uuid'] == uuid)
        .map(Json.from)
        .toList();
    await repo.pause('pending');
    return rows;
  }

  @override
  Future<void> enqueue(
    String conversation,
    String body, {
    Uint8List? image,
    String? extension,
  }) async {
    await repo.pause('enqueue');
  }

  @override
  Future<void> deliver(Json item) async {
    await repo.pause('deliver');
    final error = errors[item['token']];
    if (error != null) throw error;
    items.removeWhere((row) => row['token'] == item['token']);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

Widget _chat(_Repository repo, _Outbox outbox) => MaterialApp(
  home: ChatPage(
    conversationId: 'conversation',
    repository: repo,
    outbox: outbox,
    authChanges: repo.auth,
  ),
);

Widget _notifications(_Repository repo) => MaterialApp(
  home: LearningNotificationsPage(repository: repo, authChanges: repo.auth),
);

void main() {
  for (final stage in [
    'identity',
    'inbox',
    'messages',
    'pending',
    'markRead',
  ]) {
    testWidgets('chat disposed during $stage never recreates listeners', (
      tester,
    ) async {
      final repo = _Repository(), gate = Completer<void>();
      var waiting = false;
      repo.before = (step) async {
        if (step == stage) {
          waiting = true;
          await gate.future;
        }
      };
      await tester.pumpWidget(_chat(repo, _Outbox(repo)));
      await tester.pump();
      expect(waiting, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      final count = repo.socket.channels.length;
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      expect(repo.socket.channels, hasLength(count));
      expect(repo.socket.removed, hasLength(count));
      expect(repo.auth.listening, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  for (final fail in [false, true]) {
    testWidgets('old chat start after logout/login is ignored (error=$fail)', (
      tester,
    ) async {
      final repo = _Repository(), gate = Completer<void>();
      var first = true;
      repo.before = (step) async {
        if (step == 'messages' && first) {
          first = false;
          await gate.future;
        }
      };
      await tester.pumpWidget(_chat(repo, _Outbox(repo)));
      await tester.pump();
      repo.auth.value = null;
      await tester.pumpAndSettle();
      // Same UUID again also needs a new generation, not just a UUID check.
      repo.auth.value = _a;
      await tester.pumpAndSettle();
      if (fail) {
        gate.completeError(const CloudFailure('stale failure'));
      } else {
        gate.complete();
      }
      await tester.pumpAndSettle();
      expect(find.text('message:$_a'), findsOneWidget);
      expect(find.text('stale failure'), findsNothing);
      expect(repo.socket.channels, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'old sync cannot refill a new account; channel and poll restart',
    (tester) async {
      final repo = _Repository();
      final pending = _Outbox(repo);
      await tester.pumpWidget(_chat(repo, pending));
      await tester.pumpAndSettle();
      final oldChannel = repo.socket.channels.single;
      final gate = Completer<void>();
      var first = true;
      repo.before = (stage) async {
        if (stage == 'messages' && first) {
          first = false;
          await gate.future;
        }
      };
      await tester.tap(find.byTooltip('重新同步'));
      await tester.pump();
      expect(first, isFalse);
      repo.auth.value = _b;
      await tester.pumpAndSettle();
      gate.complete();
      oldChannel.status?.call(RealtimeSubscribeStatus.channelError, null);
      oldChannel.change?.call();
      await tester.pumpAndSettle();
      expect(find.text('message:$_a'), findsNothing);
      expect(find.text('message:$_b'), findsOneWidget);
      expect(find.text('连接中断，正在重连…'), findsNothing);
      expect(repo.socket.channels, hasLength(2));
      expect(repo.socket.removed, contains(oldChannel));
      final calls = repo.messageCalls;
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expect(repo.messageCalls, greaterThan(calls));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'new account cannot reuse a conversation missing from its inbox',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(_chat(repo, _Outbox(repo)));
      await tester.pumpAndSettle();
      repo.access = false;
      repo.auth.value = _b;
      await tester.pumpAndSettle();
      expect(find.text('message:$_a'), findsNothing);
      expect(find.text('会话不存在，或好友关系已变化'), findsOneWidget);
      expect(repo.socket.channels, hasLength(1));
      expect(repo.socket.removed, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('old enqueue completion cannot clear the new account draft', (
    tester,
  ) async {
    final repo = _Repository(), gate = Completer<void>();
    await tester.pumpWidget(_chat(repo, _Outbox(repo)));
    await tester.pumpAndSettle();
    repo.before = (stage) async {
      if (stage == 'enqueue') await gate.future;
    };
    await tester.enterText(find.byType(TextField), 'old draft');
    await tester.tap(find.text('发送'));
    await tester.pump();
    repo.auth.value = _b;
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new draft');
    gate.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'new draft',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('old delivery error cannot enter the new account state', (
    tester,
  ) async {
    final repo = _Repository(), gate = Completer<void>();
    final outbox = _Outbox(repo);
    outbox.items.add({
      'token': 'old',
      'auth_uuid': _a,
      'body': 'old pending',
      'created_at': '2026-10-16T00:00:00Z',
    });
    outbox.errors['old'] = const CloudFailure('old delivery failure');
    await tester.pumpWidget(_chat(repo, outbox));
    await tester.pumpAndSettle();
    repo.before = (stage) async {
      if (stage == 'deliver') await gate.future;
    };
    await tester.tap(find.text('等待发送，点击重试'));
    await tester.pump();
    repo.auth.value = _b;
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('old pending'), findsNothing);
    expect(find.text('old delivery failure'), findsNothing);
    expect(find.text('message:$_b'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'revoked conversation clears cached messages and pending bubbles',
    (tester) async {
      final repo = _Repository();
      final outbox = _Outbox(repo);
      outbox.items.add({
        'token': 'pending',
        'body': 'pending before revoke',
        'created_at': '2026-10-16T00:00:00Z',
      });
      await tester.pumpWidget(_chat(repo, outbox));
      await tester.pumpAndSettle();
      repo.access = false;
      await tester.tap(find.byTooltip('重新同步'));
      await tester.pumpAndSettle();
      expect(find.text('message:$_a'), findsNothing);
      expect(find.text('pending before revoke'), findsNothing);
      expect(find.text('会话不存在，或好友关系已变化'), findsOneWidget);
      expect(repo.socket.removed, hasLength(1));
      final calls = repo.messageCalls;
      await tester.pump(const Duration(seconds: 21));
      expect(repo.messageCalls, calls);
      repo.access = true;
      await tester.tap(find.byTooltip('重新同步'));
      await tester.pumpAndSettle();
      expect(find.text('message:$_a'), findsOneWidget);
      expect(repo.socket.channels, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'send errors stay on each token through sync and clear after success',
    (tester) async {
      final repo = _Repository();
      final outbox = _Outbox(repo);
      for (final token in ['one', 'two']) {
        outbox.items.add({
          'token': token,
          'body': token,
          'created_at': '2026-10-16T00:00:00Z',
        });
        outbox.errors[token] = CloudFailure('failure:$token');
      }
      await tester.pumpWidget(_chat(repo, outbox));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('重新同步'));
      await tester.pumpAndSettle();
      for (final token in ['one', 'two']) {
        final bubble = find
            .ancestor(of: find.text(token), matching: find.byType(Column))
            .first;
        expect(
          find.descendant(of: bubble, matching: find.text('failure:$token')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: bubble,
            matching: find.text(token == 'one' ? 'failure:two' : 'failure:one'),
          ),
          findsNothing,
        );
      }
      expect(find.text('已同步'), findsOneWidget);
      outbox.errors.remove('one');
      await tester.tap(find.text('发送失败，点击重试').first);
      await tester.pumpAndSettle();
      expect(find.text('failure:one'), findsNothing);
      expect(find.text('failure:two'), findsOneWidget);
      outbox.errors.clear();
      await tester.tap(find.text('发送失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.text('failure:two'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('notifications disposed before load returns never subscribe', (
    tester,
  ) async {
    final repo = _Repository(), gate = Completer<List<Json>>();
    repo.notificationRequest = (_) => gate.future;
    await tester.pumpWidget(_notifications(repo));
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete([_notification('old')]);
    await tester.pump();
    expect(repo.socket.channels, isEmpty);
    expect(repo.auth.listening, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'notifications ignore old account load and rebuild subscription',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(_notifications(repo));
      await tester.pumpAndSettle();
      final oldChannel = repo.socket.channels.single;
      final gate = Completer<List<Json>>();
      repo.notificationRequest = (_) => gate.future;
      oldChannel.change!();
      await tester.pump();
      repo.notificationRequest = null;
      repo.auth.value = _b;
      await tester.pumpAndSettle();
      gate.complete([_notification('stale')]);
      oldChannel.change!();
      await tester.pumpAndSettle();
      expect(find.textContaining(_a), findsNothing);
      expect(find.textContaining('stale'), findsNothing);
      expect(find.textContaining(_b), findsOneWidget);
      expect(repo.socket.channels, hasLength(2));
      expect(repo.socket.removed, contains(oldChannel));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('latest notification refresh wins over delayed older refresh', (
    tester,
  ) async {
    final repo = _Repository();
    await tester.pumpWidget(_notifications(repo));
    await tester.pumpAndSettle();
    final channel = repo.socket.channels.single;
    final gate = Completer<List<Json>>();
    repo.notificationRequest = (_) => gate.future;
    channel.change!();
    await tester.pump();
    repo.notificationRequest = (_) async => [_notification('newest')];
    channel.change!();
    await tester.pumpAndSettle();
    gate.complete([_notification('older')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('newest'), findsOneWidget);
    expect(find.textContaining('older'), findsNothing);
    expect(repo.socket.channels, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
