import '../database/models/ai_chat_records.dart';
import '../database/models/knowledge_context_source.dart';
import '../database/models/llm_provider_config.dart';
import '../llm/minimax_client.dart';

// ========== AI Chat 调用服务 ==========
// 将聊天历史与本地知识库证据组装为模型消息，生成可信的伴学回答。

class AiChatService {
  AiChatService({MiniMaxClient? miniMaxClient})
    : _miniMaxClient = miniMaxClient;

  final MiniMaxClient? _miniMaxClient;

  Future<String> generateReply({
    required LlmProviderConfig config,
    required List<AiChatMessageRecord> messages,
    List<KnowledgeContextSource> contextSources = const [],
  }) async {
    if (!config.isConfigured) {
      throw const MiniMaxException('请先到“我的”页面配置 AI 大模型 API Key');
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
    final groundedMessages = _withKnowledgeContext(
      clientMessages,
      contextSources,
    );

    final client = _miniMaxClient ?? MiniMaxClient.fromConfig(config);
    return client.generateChatReply(
      systemPrompt: contextSources.isEmpty
          ? _systemPrompt
          : _groundedSystemPrompt,
      messages: groundedMessages,
    );
  }

  List<Map<String, String>> _withKnowledgeContext(
    List<Map<String, String>> messages,
    List<KnowledgeContextSource> contextSources,
  ) {
    if (contextSources.isEmpty || messages.isEmpty) {
      return messages;
    }

    final lastUserIndex = messages.lastIndexWhere(
      (message) => message['role'] == AiChatMessageRole.user,
    );
    if (lastUserIndex < 0) {
      return messages;
    }

    final original = messages[lastUserIndex];
    final originalContent = original['content'] ?? '';
    final contextText = contextSources
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key + 1;
          final source = entry.value;
          return '''
资料 $index
来源：${source.documentTitle} / ${source.citationTitle}
片段：${source.snippet}
''';
        })
        .join('\n');

    final rewritten = Map<String, String>.from(original);
    rewritten['content'] =
        '''
【本地知识库资料】
$contextText

【用户问题】
$originalContent

请只根据上面的本地资料回答，并在用到资料时用“来源：资料序号 - 资料标题”的形式标注依据。
''';

    return [
      ...messages.take(lastUserIndex),
      rewritten,
      ...messages.skip(lastUserIndex + 1),
    ];
  }

  static const String _systemPrompt =
      '你是拍学通的学习助手，回答要清晰、分步骤、适合不同领域的学习者理解；不要编造来源；不确定时说明需要更多资料。';

  static const String _groundedSystemPrompt =
      '你是拍学通的资料伴学助手。只根据【本地知识库资料】回答；如果资料不足，明确说“当前知识库资料不足以回答”。回答要清晰、分步，并标注来源。不要编造资料中没有的内容。';
}
