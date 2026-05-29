import '../database/models/ai_chat_records.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';

// ========== AI Chat 调用服务 ==========
// 将聊天历史转换为大模型消息，并返回普通文本回复。

class AiChatService {
  AiChatService({MiniMaxClient? miniMaxClient}) : _miniMaxClient = miniMaxClient;

  final MiniMaxClient? _miniMaxClient;

  Future<String> generateReply({
    required LlmProviderConfig config,
    required List<AiChatMessageRecord> messages,
  }) async {
    if (!config.isConfigured) {
      throw const MiniMaxException('请先到“我的”页配置 AI 大模型 API Key');
    }

    final recentMessages = messages.length > 20
        ? messages.sublist(messages.length - 20)
        : messages;
    final clientMessages = recentMessages
        .where(
          (message) =>
              message.role == AiChatMessageRole.user ||
              message.role == AiChatMessageRole.assistant,
        )
        .map((message) => message.toClientMessage())
        .toList(growable: false);

    final client = _miniMaxClient ?? MiniMaxClient.fromConfig(config);
    return client.generateChatReply(
      systemPrompt: _systemPrompt,
      messages: clientMessages,
    );
  }

  static const String _systemPrompt =
      '你是拍学通的学习助手，回答要清晰、分步骤、适合学生理解；不要编造来源；不确定时说明需要更多资料。';
}
