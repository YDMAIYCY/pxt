import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'cloud_backend.dart';
import 'cloud_identity_repository.dart';

typedef Json = Map<String, dynamic>;

class CommunityRepository {
  CommunityRepository({
    SupabaseClient? client,
    CloudIdentityRepository? identity,
  }) : _client = client,
       _identity = identity;
  final SupabaseClient? _client;
  final CloudIdentityRepository? _identity;
  SupabaseClient get client =>
      _client ??
      CloudBackend.instance.client ??
      (throw CloudFailure(CloudBackend.instance.failure ?? '云服务尚未就绪，请稍后重试'));
  CloudIdentityRepository get identity =>
      _identity ?? CloudIdentityRepository(client: client);
  String get uid =>
      client.auth.currentUser?.id ?? (throw const CloudFailure('请先登录智学帮'));
  Future<T> _run<T>(Future<T> Function() action) async {
    await identity.requireLinked();
    return action().timeout(const Duration(seconds: 25));
  }

  static List<Json> rows(dynamic value) =>
      (value as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  static const profileSelect =
      'profile:profiles!author_id(id,public_id,nickname,bio,avatar_path)';

  Future<List<Json>> feed({
    String mode = 'latest',
    String keyword = '',
    int offset = 0,
    String? author,
    bool bookmarks = false,
  }) => _run(
    () async => rows(
      await client.rpc(
        'community_feed',
        params: {
          'mode': mode,
          'keyword': keyword.trim(),
          'page_size': 20,
          'page_offset': offset,
          'author': author,
          'only_bookmarks': bookmarks,
        },
      ),
    ),
  );
  Future<Json> question(String id) => _run(
    () async => await client
        .from('community_questions')
        .select('*, $profileSelect')
        .eq('id', id)
        .single(),
  );
  Future<List<Json>> answers(String id, {int offset = 0}) => _run(
    () async => rows(
      await client
          .from('community_answers')
          .select('*, $profileSelect')
          .eq('question_id', id)
          .order('created_at')
          .order('id')
          .range(offset, offset + 19),
    ),
  );
  Future<List<Json>> comments(String answer, {int offset = 0}) => _run(
    () async => rows(
      await client
          .from('community_comments')
          .select('*, $profileSelect')
          .eq('answer_id', answer)
          .order('created_at')
          .order('id')
          .range(offset, offset + 19),
    ),
  );
  Future<bool> bookmarked(String id) => _run(
    () async =>
        (await client
                .from('community_bookmarks')
                .select('question_id')
                .eq('question_id', id))
            .isNotEmpty,
  );
  Future<void> bookmark(String id, bool save) => _run(() async {
    if (save) {
      await client.from('community_bookmarks').insert({'question_id': id});
    } else {
      await client.from('community_bookmarks').delete().eq('question_id', id);
    }
  });
  Future<String> publish({
    required String title,
    required String body,
    required String token,
    List<String> tags = const [],
    List<String> images = const [],
  }) => _run(() async {
    // Query after uncertain delivery before retrying the same idempotency key.
    final old = await client
        .from('community_questions')
        .select('id')
        .eq('author_id', uid)
        .eq('client_token', token)
        .maybeSingle();
    if (old != null) return old['id'] as String;
    try {
      return (await client
              .from('community_questions')
              .insert({
                'title': title.trim(),
                'body': body.trim(),
                'client_token': token,
                'tags': tags,
                'image_paths': images,
              })
              .select('id')
              .single())['id']
          as String;
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      return (await client
              .from('community_questions')
              .select('id')
              .eq('author_id', uid)
              .eq('client_token', token)
              .single())['id']
          as String;
    }
  });
  Future<void> answer(String question, String body, String token) =>
      _run(() async {
        try {
          await client.from('community_answers').insert({
            'question_id': question,
            'body': body.trim(),
            'client_token': token,
          });
        } on PostgrestException catch (e) {
          if (e.code != '23505') rethrow;
        }
      });
  Future<void> comment(
    String answer,
    String body,
    String token, {
    String? parent,
  }) => _run(() async {
    try {
      await client.from('community_comments').insert({
        'answer_id': answer,
        'body': body.trim(),
        'client_token': token,
        'parent_id': parent,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
    }
  });
  Future<void> deleteContent(String table, String id) => _run(() async {
    if (![
      'community_questions',
      'community_answers',
      'community_comments',
    ].contains(table)) {
      throw ArgumentError('未知内容类型');
    }
    final deleted = await client.rpc(
      'delete_own_community_content',
      params: {'content_table': table, 'content_id': id},
    );
    if (deleted != true) throw const CloudFailure('内容已不存在或无权删除，请刷新查看');
  });
  Future<void> editContent(
    String table,
    String id,
    String body, {
    String? title,
  }) => _run(() async {
    if (!['community_questions', 'community_answers'].contains(table)) {
      throw ArgumentError('未知内容类型');
    }
    await client
        .from(table)
        .update({'body': body.trim(), if (title != null) 'title': title.trim()})
        .eq('id', id);
  });
  Future<void> accept(String question, String? answer) => _run(() async {
    await client.rpc(
      'accept_community_answer',
      params: {'qid': question, 'aid': answer},
    );
  });
  Future<void> report(String type, String id, String reason) => _run(() async {
    if (!['question', 'answer', 'comment'].contains(type)) {
      throw ArgumentError('未知内容类型');
    }
    await client.from('content_reports').insert({
      '${type}_id': id,
      'reason': reason,
    });
  });

  Future<Json> profile(String id) => _run(
    () async => await client.from('profiles').select().eq('id', id).single(),
  );
  Future<void> saveProfile({
    required String nickname,
    required String bio,
    String? avatar,
    String? background,
    bool setImages = false,
  }) => _run(() async {
    await client
        .from('profiles')
        .update({
          'nickname': nickname.trim(),
          'bio': bio.trim(),
          if (setImages) 'avatar_path': avatar,
          if (setImages) 'background_path': background,
        })
        .eq('id', uid);
  });
  Future<Json> stats(String id) => _run(
    () async => Map<String, dynamic>.from(
      await client.rpc('community_user_stats', params: {'target': id}) as Map,
    ),
  );
  Future<List<Json>> searchUsers(String query, {int offset = 0}) =>
      _run(() async {
        // PostgREST filter syntax is never composed from raw user input.
        final safe = query.trim().replaceAll(
          RegExp(r'[^\p{L}\p{N}_\-\s]', unicode: true),
          '',
        );
        if (safe.isEmpty) return <Json>[];
        return rows(
          await client
              .from('profiles')
              .select()
              .or('nickname.ilike.%$safe%,public_id.ilike.%$safe%')
              .order('public_id')
              .range(offset, offset + 19),
        );
      });
  Future<List<Json>> userAnswers(String id, {int offset = 0}) => _run(
    () async => rows(
      await client
          .from('community_answers')
          .select(
            '*, question:community_questions!community_answers_question_id_fkey(title)',
          )
          .eq('author_id', id)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 19),
    ),
  );
  Future<List<Json>> friends() => _run(() async {
    final list = rows(await client.from('friendships').select());
    if (list.isEmpty) return <Json>[];
    final ids = list
        .map(
          (e) => e['user_low'] == uid
              ? e['user_high'] as String
              : e['user_low'] as String,
        )
        .toList();
    return rows(
      await client
          .from('profiles')
          .select()
          .inFilter('id', ids)
          .order('nickname'),
    );
  });
  Future<List<Json>> requests() => _run(
    () async => rows(
      await client
          .from('friend_requests')
          .select(
            '*, sender:profiles!sender_id(id,public_id,nickname,avatar_path), recipient:profiles!recipient_id(id,public_id,nickname,avatar_path)',
          )
          .order('created_at', ascending: false)
          .limit(100),
    ),
  );
  Future<String> friendStatus(String id) => _run(() async {
    if (id == uid) return 'self';
    final friendsList = await client
        .from('friendships')
        .select()
        .eq('user_low', ([uid, id]..sort()).first)
        .eq('user_high', ([uid, id]..sort()).last);
    if (friendsList.isNotEmpty) return 'friend';
    final pending = await client
        .from('friend_requests')
        .select()
        .eq('status', 'pending')
        .or('sender_id.eq.$id,recipient_id.eq.$id');
    if (pending.isEmpty) return 'none';
    return pending.first['sender_id'] == uid ? 'sent' : 'received';
  });
  Future<void> sendRequest(String id) => _run(() async {
    await client.rpc('send_friend_request', params: {'target': id});
  });
  Future<void> respond(String id, bool accept) => _run(() async {
    await client.rpc(
      'respond_friend_request',
      params: {'rid': id, 'accept': accept},
    );
  });
  Future<void> removeFriend(String id) => _run(() async {
    await client.rpc('remove_friend', params: {'target': id});
  });
  Future<void> block(String id) => _run(() async {
    await client.rpc('block_user', params: {'target': id});
  });
  Future<List<Json>> blocks() => _run(
    () async => rows(
      await client
          .from('user_blocks')
          .select()
          .order('created_at', ascending: false),
    ),
  );
  Future<void> unblock(String id) => _run(() async {
    await client.from('user_blocks').delete().eq('blocked_id', id);
  });
  Future<String> openConversation(String id) => _run(
    () async =>
        await client.rpc('open_direct_conversation', params: {'target': id})
            as String,
  );
  Future<List<Json>> inbox() =>
      _run(() async => rows(await client.rpc('conversation_inbox')));
  Future<List<Json>> messages(String id, {Json? before}) => _run(() async {
    var query = client.from('chat_messages').select().eq('conversation_id', id);
    if (before != null) {
      // Both cursor components came from the server, never a text input.
      query = query.or(
        'created_at.lt.${before['created_at']},and(created_at.eq.${before['created_at']},id.lt.${before['id']})',
      );
    }
    return rows(
      await query
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(30),
    );
  });
  Future<void> sendMessage({
    required String conversation,
    required String token,
    required String body,
    String? image,
    String? expectedSender,
  }) => _run(() async {
    final sender = expectedSender ?? uid;
    await client.rpc(
      'send_chat_message',
      params: {
        'cid': conversation,
        'token': token,
        'message_body': body.trim(),
        'image': image,
        'expected_sender': sender,
      },
    );
  });
  Future<void> markRead(String conversation, String message) => _run(() async {
    await client.rpc(
      'mark_conversation_read',
      params: {'cid': conversation, 'through_message': message},
    );
  });
  Future<List<Json>> notifications({int offset = 0}) => _run(
    () async => rows(
      await client
          .from('notifications')
          .select('*, actor:profiles!actor_id(id,nickname,avatar_path)')
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + 29),
    ),
  );
  Future<int> unreadCount() => _run(
    () async => await client
        .from('notifications')
        .count(CountOption.exact)
        .isFilter('read_at', null),
  );
  Future<void> readNotification(String id) => _run(() async {
    await client.rpc('read_notification', params: {'nid': id});
  });

  Future<String> upload(
    String bucket,
    Uint8List bytes,
    String extension, {
    String? conversation,
    String? token,
    String? expectedOwner,
  }) => _run(() async {
    final ext = extension.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext) ||
        bytes.length > 8 * 1024 * 1024) {
      throw const CloudFailure('请选择小于 8 MB 的 JPG、PNG 或 WebP 图片');
    }
    if (![
      'community-images',
      'chat-images',
      'profile-images',
    ].contains(bucket)) {
      throw ArgumentError('未知附件类型');
    }
    final owner = expectedOwner ?? uid;
    if (owner != uid) throw const CloudFailure('登录账号已改变，请重新打开聊天');
    final path =
        '${conversation == null ? '' : '$conversation/'}$owner/${token ?? const Uuid().v4()}.$ext';
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: ext == 'png'
                  ? 'image/png'
                  : ext == 'webp'
                  ? 'image/webp'
                  : 'image/jpeg',
              upsert: false,
            ),
          );
    } on StorageException catch (e) {
      if (e.statusCode != '409' && e.statusCode != '400') rethrow;
      // A timeout may have delivered the upload already. Verify ownership via RLS.
      await client.storage.from(bucket).createSignedUrl(path, 60);
    }
    return path;
  });
  Future<String> imageUrl(String bucket, String path) =>
      _run(() => client.storage.from(bucket).createSignedUrl(path, 120));
  Future<void> saveReference(String question, String? answer) => _run(() async {
    final query = client
        .from('saved_community_knowledge')
        .select('id')
        .eq('question_id', question);
    final existing = answer == null
        ? await query.isFilter('answer_id', null)
        : await query.eq('answer_id', answer);
    if (existing.isEmpty) {
      await client.from('saved_community_knowledge').insert({
        'question_id': question,
        'answer_id': answer,
      });
    }
  });
}
