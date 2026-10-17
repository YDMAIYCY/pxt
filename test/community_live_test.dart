import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Run ONLY with two dedicated, email-confirmed accounts. Creates persisted
/// test chat messages; never pass credentials for personal production accounts.
void main() {
  const enabled = bool.fromEnvironment('COMMUNITY_LIVE_TEST');
  test(
    'two real users: community, friends, private storage, Realtime, unread and isolation',
    () async {
      HttpOverrides.global = null;
      const url = String.fromEnvironment('SUPABASE_URL');
      const key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
      const emailA = String.fromEnvironment('COMMUNITY_TEST_EMAIL_A'),
          passwordA = String.fromEnvironment('COMMUNITY_TEST_PASSWORD_A');
      const emailB = String.fromEnvironment('COMMUNITY_TEST_EMAIL_B'),
          passwordB = String.fromEnvironment('COMMUNITY_TEST_PASSWORD_B');
      expect(
        url.isNotEmpty &&
            key.isNotEmpty &&
            emailA.isNotEmpty &&
            emailB.isNotEmpty &&
            passwordA.isNotEmpty &&
            passwordB.isNotEmpty,
        isTrue,
        reason: 'Provide both ignored local config files',
      );
      final a = SupabaseClient(
        url,
        key,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final b = SupabaseClient(
        url,
        key,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final anon = SupabaseClient(
        url,
        key,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      String? qid, cid, object;
      RealtimeChannel? channel;
      final run = const Uuid().v4();
      try {
        final authA = await a.auth.signInWithPassword(
          email: emailA,
          password: passwordA,
        );
        final authB = await b.auth.signInWithPassword(
          email: emailB,
          password: passwordB,
        );
        final uidA = authA.user!.id, uidB = authB.user!.id;
        expect(
          uidA,
          isNot(uidB),
          reason: 'Accounts must be distinct verified users',
        );
        expect((await a.auth.getUser()).user!.id, uidA);
        expect((await b.auth.getUser()).user!.id, uidB);
        qid =
            (await a
                    .from('community_questions')
                    .insert({
                      'title': '[验收] 学习社区 $run',
                      'body': '验收用问题，请勿当作真实学习资料',
                      'tags': ['验收'],
                      'client_token': run,
                    })
                    .select('id')
                    .single())['id']
                as String;
        expect(
          (await b.from('community_questions').select().eq('id', qid)).length,
          1,
        );
        final edited = await b
            .from('community_questions')
            .update({'title': '越权修改'})
            .eq('id', qid)
            .select('id');
        expect(edited, isEmpty);
        final answer =
            (await b
                    .from('community_answers')
                    .insert({
                      'question_id': qid,
                      'body': '[验收] 回答',
                      'client_token': const Uuid().v4(),
                    })
                    .select('id')
                    .single())['id']
                as String;
        await expectLater(
          b.rpc('accept_community_answer', params: {'qid': qid, 'aid': answer}),
          throwsA(isA<PostgrestException>()),
        );
        expect(
          (await b
              .from('profiles')
              .select('public_id')
              .eq('id', uidA)
              .single())['public_id'],
          isNotEmpty,
        );
        final replyNotification = await a
            .from('notifications')
            .select('id')
            .eq('kind', 'answer')
            .eq('question_id', qid);
        expect(replyNotification, isNotEmpty);
        expect(
          await b.from('notifications').select('id').eq('recipient_id', uidA),
          isEmpty,
        );
        final comment = (await a
            .from('community_comments')
            .insert({
              'answer_id': answer,
              'body': '[验收] 评论回答',
              'client_token': const Uuid().v4(),
            })
            .select('id')
            .single())['id'];
        await b.from('community_comments').insert({
          'answer_id': answer,
          'parent_id': comment,
          'body': '[验收] 回复评论',
          'client_token': const Uuid().v4(),
        });
        expect(
          (await a
                  .from('community_comments')
                  .select('id')
                  .eq('answer_id', answer))
              .length,
          2,
        );
        await a.rpc(
          'accept_community_answer',
          params: {'qid': qid, 'aid': answer},
        );
        expect(
          (await b
              .from('community_questions')
              .select()
              .eq('id', qid)
              .single())['accepted_answer_id'],
          answer,
        );
        await b.from('community_bookmarks').insert({'question_id': qid});
        expect(
          await a.from('community_bookmarks').select().eq('question_id', qid),
          isEmpty,
        );
        final existing = await a
            .from('friendships')
            .select()
            .or('user_low.eq.$uidB,user_high.eq.$uidB');
        if (existing.isEmpty) {
          final request = await a.rpc(
            'send_friend_request',
            params: {'target': uidB},
          );
          final requestRow = await a
              .from('friend_requests')
              .select('recipient_id')
              .eq('id', request)
              .single();
          final recipient = requestRow['recipient_id'] == uidB ? b : a;
          final sender = requestRow['recipient_id'] == uidB ? a : b;
          await expectLater(
            sender.rpc(
              'respond_friend_request',
              params: {'rid': request, 'accept': true},
            ),
            throwsA(isA<PostgrestException>()),
          );
          await recipient.rpc(
            'respond_friend_request',
            params: {'rid': request, 'accept': true},
          );
        }
        cid =
            await a.rpc('open_direct_conversation', params: {'target': uidB})
                as String;
        expect(
          await b.rpc('open_direct_conversation', params: {'target': uidA}),
          cid,
        );
        final arrived = Completer<void>(), subscribed = Completer<void>();
        final messageToken = const Uuid().v4();
        channel = b
            .channel('live-check-$run')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: cid,
              ),
              callback: (payload) {
                if (payload.newRecord['client_token'] == messageToken &&
                    !arrived.isCompleted) {
                  arrived.complete();
                }
              },
            )
            .subscribe((status, error) {
              if (status == RealtimeSubscribeStatus.subscribed &&
                  !subscribed.isCompleted) {
                subscribed.complete();
              }
            });
        await subscribed.future.timeout(const Duration(seconds: 25));
        final message =
            await a.rpc(
                  'send_chat_message',
                  params: {
                    'cid': cid,
                    'token': messageToken,
                    'message_body': '[验收] Realtime 私信 $run',
                    'image': null,
                    'expected_sender': uidA,
                  },
                )
                as String;
        await arrived.future.timeout(const Duration(seconds: 25));
        await expectLater(
          a.from('chat_messages').insert({
            'conversation_id': cid,
            'client_token': messageToken,
            'body': '重复发送',
          }),
          throwsA(isA<PostgrestException>()),
        );
        expect(
          (await b
                  .from('chat_messages')
                  .select()
                  .eq('client_token', messageToken))
              .length,
          1,
        );
        await expectLater(
          b.from('chat_messages').insert({
            'conversation_id': cid,
            'sender_id': uidA,
            'client_token': const Uuid().v4(),
            'body': '冒充发送',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          anon.from('chat_messages').select().eq('conversation_id', cid),
          throwsA(isA<PostgrestException>()),
        );
        final inbox = await b.rpc('conversation_inbox') as List;
        expect(
          (inbox.firstWhere((c) => c['id'] == cid)['unread'] as num) > 0,
          isTrue,
        );
        await b.rpc(
          'mark_conversation_read',
          params: {'cid': cid, 'through_message': message},
        );
        final read = await b.rpc('conversation_inbox') as List;
        expect(read.firstWhere((c) => c['id'] == cid)['unread'], 0);
        object = '$cid/$uidA/$run.png';
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1cAAAAASUVORK5CYII=',
        );
        await a.storage
            .from('chat-images')
            .uploadBinary(
              object,
              png,
              fileOptions: const FileOptions(contentType: 'image/png'),
            );
        expect(
          (await b.storage.from('chat-images').createSignedUrl(object, 60))
              .isNotEmpty,
          isTrue,
        );
        await expectLater(
          anon.storage.from('chat-images').createSignedUrl(object, 60),
          throwsA(isA<StorageException>()),
        );
        await a.rpc(
          'send_chat_message',
          params: {
            'cid': cid,
            'token': const Uuid().v4(),
            'message_body': '',
            'image': object,
            'expected_sender': uidA,
          },
        );
        expect(
          (await b
                  .from('chat_messages')
                  .select()
                  .eq('conversation_id', cid)
                  .eq('image_path', object))
              .length,
          1,
        );
        await b.rpc('block_user', params: {'target': uidA});
        expect(
          await a.from('chat_messages').select().eq('conversation_id', cid),
          isEmpty,
        );
        await expectLater(
          a.from('chat_messages').insert({
            'conversation_id': cid,
            'client_token': const Uuid().v4(),
            'body': '屏蔽后消息',
          }),
          throwsA(isA<PostgrestException>()),
        );
        await expectLater(
          a.storage.from('chat-images').createSignedUrl(object, 60),
          throwsA(isA<StorageException>()),
        );
        await b.from('user_blocks').delete().eq('blocked_id', uidA);
        // Restore the dedicated accounts' friendship for manual two-device acceptance.
        final request = await a.rpc(
          'send_friend_request',
          params: {'target': uidB},
        );
        await b.rpc(
          'respond_friend_request',
          params: {'rid': request, 'accept': true},
        );
      } finally {
        if (channel != null) await b.removeChannel(channel);
        if (qid != null) {
          try {
            await a.from('community_questions').delete().eq('id', qid);
          } catch (_) {}
        }
        // Image and test messages remain intentionally available for device review.
        await a.dispose();
        await b.dispose();
        await anon.dispose();
      }
    },
    skip: !enabled
        ? 'No live accounts supplied; run explicitly with both local config files'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
