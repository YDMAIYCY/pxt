import 'dart:convert';

// ========== AI Chat 数据模型 ==========
// 会话模型用于历史列表，消息模型用于聊天正文回溯。

class AiChatMessageRole {
  const AiChatMessageRole._();

  static const String user = 'user';
  static const String assistant = 'assistant';
  static const String system = 'system';

  static String normalize(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    switch (raw) {
      case assistant:
        return assistant;
      case system:
        return system;
      case user:
      default:
        return user;
    }
  }
}

class AiChatSessionRecord {
  const AiChatSessionRecord({
    required this.id,
    required this.userId,
    required this.title,
    required this.lastMessagePreview,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final int userId;
  final String title;
  final String lastMessagePreview;
  final DateTime createdAt;
  final DateTime updatedAt;

  AiChatSessionRecord copyWith({
    int? id,
    int? userId,
    String? title,
    String? lastMessagePreview,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AiChatSessionRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AiChatSessionRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?)?.trim() ?? '';
    final updatedAt = (map['updated_at'] as String?)?.trim() ?? '';

    return AiChatSessionRecord(
      id: map['id'] as int,
      userId: map['user_id'] as int,
      title: (map['title'] as String?)?.trim() ?? '新的聊天',
      lastMessagePreview:
          (map['last_message_preview'] as String?)?.trim() ?? '',
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
      updatedAt: DateTime.tryParse(updatedAt)?.toLocal() ?? DateTime.now(),
    );
  }
}

class AiChatMessageRecord {
  const AiChatMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.provider,
    this.model,
    this.metadata = const {},
  });

  final int id;
  final int sessionId;
  final String role;
  final String content;
  final String? provider;
  final String? model;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  bool get isUser => role == AiChatMessageRole.user;

  bool get isAssistant => role == AiChatMessageRole.assistant;

  Map<String, String> toClientMessage() {
    return {'role': role, 'content': content};
  }

  factory AiChatMessageRecord.fromMap(Map<String, Object?> map) {
    final createdAt = (map['created_at'] as String?)?.trim() ?? '';
    final provider = (map['provider'] as String?)?.trim();
    final model = (map['model'] as String?)?.trim();

    return AiChatMessageRecord(
      id: map['id'] as int,
      sessionId: map['session_id'] as int,
      role: AiChatMessageRole.normalize(map['role'] as String?),
      content: (map['content'] as String?)?.trim() ?? '',
      provider: provider == null || provider.isEmpty ? null : provider,
      model: model == null || model.isEmpty ? null : model,
      metadata: jsonDecode(map['metadata_json'] as String? ?? '{}') as Map<String, dynamic>,
      createdAt: DateTime.tryParse(createdAt)?.toLocal() ?? DateTime.now(),
    );
  }
}
