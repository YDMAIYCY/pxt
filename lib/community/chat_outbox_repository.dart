import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../database/auth_repository.dart';
import 'cloud_backend.dart';
import 'community_repository.dart';

class ChatOutboxRepository {
  ChatOutboxRepository({AppDatabase? database, CommunityRepository? community})
    : _db = database ?? AppDatabase.instance,
      _cloud = community ?? CommunityRepository();
  final AppDatabase _db;
  final CommunityRepository _cloud;
  Future<({int user, String uuid})> _owner() async {
    final uuid = await _cloud.identity.requireLinked();
    final local = await AuthRepository(database: _db).getCurrentUserProfile();
    if (local == null) throw const CloudFailure('请先登录');
    return (user: local.id, uuid: uuid);
  }

  Future<void> enqueue(
    String conversation,
    String body, {
    Uint8List? image,
    String? extension,
  }) async {
    final owner = await _owner();
    await (await _db.database).insert('chat_outbox', {
      'token': const Uuid().v4(),
      'user_id': owner.user,
      'auth_uuid': owner.uuid,
      'conversation_id': conversation,
      'body': body,
      'image_bytes': image,
      'image_extension': extension,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Json>> pending(String conversation) async {
    final owner = await _owner();
    return (await (await _db.database).query(
      'chat_outbox',
      where: 'user_id=? AND auth_uuid=? AND conversation_id=?',
      whereArgs: [owner.user, owner.uuid, conversation],
      orderBy: 'created_at',
    )).map(Json.from).toList();
  }

  Future<void> deliver(Json item) async {
    final owner = await _owner();
    if (item['user_id'] != owner.user || item['auth_uuid'] != owner.uuid) {
      throw const CloudFailure('不能发送其他账号的待发消息');
    }
    final db = await _db.database;
    String? path = item['image_path'] as String?;
    if (item['image_bytes'] != null && path == null) {
      path = await _cloud.upload(
        'chat-images',
        item['image_bytes'] as Uint8List,
        item['image_extension'] as String,
        conversation: item['conversation_id'] as String,
        token: item['token'] as String,
      );
      await db.update(
        'chat_outbox',
        {'image_path': path},
        where: 'token=? AND user_id=? AND auth_uuid=?',
        whereArgs: [item['token'], owner.user, owner.uuid],
      );
    }
    await _cloud.sendMessage(
      conversation: item['conversation_id'] as String,
      token: item['token'] as String,
      body: item['body'] as String,
      image: path,
    );
    await db.delete(
      'chat_outbox',
      where: 'token=? AND user_id=? AND auth_uuid=?',
      whereArgs: [item['token'], owner.user, owner.uuid],
    );
  }
}
