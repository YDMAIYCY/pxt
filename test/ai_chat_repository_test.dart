import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/app_database.dart';
import 'package:pxt1/database/models/ai_chat_records.dart';

void main() {
  group('AI chat persistence contract', () {
    test('database registers chat tables and indexes', () {
      final source = File(
        'lib/database/app_database.dart',
      ).readAsStringSync();

      expect(AppDatabase.tableAiChatSessions, 'ai_chat_sessions');
      expect(AppDatabase.tableAiChatMessages, 'ai_chat_messages');
      expect(source, contains(r'CREATE TABLE $tableAiChatSessions'));
      expect(source, contains(r'CREATE TABLE $tableAiChatMessages'));
      expect(source, contains('idx_ai_chat_sessions_user_id'));
      expect(source, contains('idx_ai_chat_messages_session_id'));
      expect(source, contains('_upgradeAiChatToV10'));
    });

    test('session and message records map database rows', () {
      final session = AiChatSessionRecord.fromMap({
        'id': 1,
        'user_id': 7,
        'title': '函数复习',
        'last_message_preview': '先看定义',
        'created_at': '2026-05-29T08:00:00.000Z',
        'updated_at': '2026-05-29T08:10:00.000Z',
      });
      final message = AiChatMessageRecord.fromMap({
        'id': 2,
        'session_id': 1,
        'role': AiChatMessageRole.assistant,
        'content': '先看定义，再做例题。',
        'provider': 'minimax',
        'model': 'MiniMax-M2.7',
        'created_at': '2026-05-29T08:10:00.000Z',
      });

      expect(session.title, '函数复习');
      expect(session.lastMessagePreview, '先看定义');
      expect(message.isAssistant, isTrue);
      expect(message.provider, 'minimax');
      expect(message.model, 'MiniMax-M2.7');
    });

    test('repository exposes history management operations', () {
      final source = File(
        'lib/database/ai_chat_repository.dart',
      ).readAsStringSync();

      expect(source, contains('Future<AiChatSessionRecord> createSession'));
      expect(source, contains('Future<List<AiChatSessionRecord>> fetchSessions'));
      expect(source, contains('Future<List<AiChatMessageRecord>> fetchMessages'));
      expect(source, contains('Future<void> renameSession'));
      expect(source, contains('Future<void> deleteSession'));
      expect(source, contains('Future<AiChatMessageRecord> appendMessage'));
      expect(source, contains('Future<void> touchSessionPreview'));
      expect(source, contains("orderBy: 'updated_at DESC"));
    });
  });
}
