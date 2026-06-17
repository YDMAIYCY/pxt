import 'package:flutter/material.dart';

import '../../database/ai_chat_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/knowledge_context_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_chat_records.dart';
import '../../database/models/knowledge_context_source.dart';
import '../../database/models/user_profile.dart';
import '../../generator/ai_chat_service.dart';
import '../theme/app_theme.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({
    this.authRepository,
    this.llmConfigRepository,
    this.aiChatRepository,
    this.knowledgeContextRepository,
    this.aiChatService,
    super.key,
  });

  final AuthRepository? authRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiChatRepository? aiChatRepository;
  final KnowledgeContextRepository? knowledgeContextRepository;
  final AiChatService? aiChatService;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final AuthRepository _authRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiChatRepository _aiChatRepository;
  late final KnowledgeContextRepository _knowledgeContextRepository;
  late final AiChatService _aiChatService;

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  UserProfile? _user;
  List<AiChatSessionRecord> _sessions = const [];
  List<AiChatMessageRecord> _messages = const [];
  AiChatSessionRecord? _currentSession;
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _aiChatRepository = widget.aiChatRepository ?? AiChatRepository();
    _knowledgeContextRepository =
        widget.knowledgeContextRepository ?? KnowledgeContextRepository();
    _aiChatService = widget.aiChatService ?? AiChatService();
    _loadInitialData();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      await _authRepository.ensureInitialized();
      final user = await _authRepository.getCurrentUserProfile();
      if (user == null) {
        throw StateError('登录状态已失效，请重新登录');
      }

      final sessions = await _aiChatRepository.fetchSessions(userId: user.id);
      final current = sessions.isEmpty ? null : sessions.first;
      final messages = current == null
          ? <AiChatMessageRecord>[]
          : await _aiChatRepository.fetchMessages(sessionId: current.id);

      if (!mounted) return;
      setState(() {
        _user = user;
        _sessions = sessions;
        _currentSession = current;
        _messages = messages;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('AI Chat 加载失败：$error');
    }
  }

  Future<void> _reloadSessions({int? preferSessionId}) async {
    final user = _user;
    if (user == null) return;

    final sessions = await _aiChatRepository.fetchSessions(userId: user.id);
    AiChatSessionRecord? current;
    if (preferSessionId != null) {
      current = sessions.cast<AiChatSessionRecord?>().firstWhere(
        (item) => item?.id == preferSessionId,
        orElse: () => null,
      );
    }
    current ??= sessions.isEmpty ? null : sessions.first;
    final messages = current == null
        ? <AiChatMessageRecord>[]
        : await _aiChatRepository.fetchMessages(sessionId: current.id);

    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _currentSession = current;
      _messages = messages;
    });
  }

  Future<void> _startNewChat() async {
    setState(() {
      _currentSession = null;
      _messages = const [];
    });
    _inputController.clear();
  }

  Future<void> _selectSession(AiChatSessionRecord session) async {
    final messages = await _aiChatRepository.fetchMessages(
      sessionId: session.id,
    );
    if (!mounted) return;
    setState(() {
      _currentSession = session;
      _messages = messages;
    });
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;
    final user = _user;
    if (user == null) {
      _showMessage('登录状态已失效，请重新登录');
      return;
    }

    final text = _inputController.text.trim();
    if (text.isEmpty) {
      _showMessage('请输入聊天内容');
      return;
    }

    final config = await _llmConfigRepository.getByUserId(user.id);
    if (config == null || !config.isConfigured) {
      _showMessage('请先到“我的”页配置 AI 大模型 API Key');
      return;
    }

    setState(() => _isSending = true);
    try {
      var session = _currentSession;
      session ??= await _aiChatRepository.createSession(
        userId: user.id,
        title: _titleFromMessage(text),
      );

      final userMessage = await _aiChatRepository.appendMessage(
        sessionId: session.id,
        role: AiChatMessageRole.user,
        content: text,
      );
      await _aiChatRepository.touchSessionPreview(
        sessionId: session.id,
        preview: text,
      );

      if (!mounted) return;
      _inputController.clear();
      setState(() {
        _currentSession = session;
        _messages = [..._messages, userMessage];
      });
      _scrollToBottom();

      final contextSources = await _knowledgeContextRepository.search(
        userId: user.id,
        query: text,
      );
      final reply = await _aiChatService.generateReply(
        config: config,
        messages: _messages,
        contextSources: contextSources,
      );
      final groundedReply = _appendSources(reply, contextSources);
      final assistantMessage = await _aiChatRepository.appendMessage(
        sessionId: session.id,
        role: AiChatMessageRole.assistant,
        content: groundedReply,
        provider: config.provider,
        model: config.effectiveModel,
      );
      await _aiChatRepository.touchSessionPreview(
        sessionId: session.id,
        preview: groundedReply,
      );

      if (!mounted) return;
      setState(() {
        _messages = [..._messages, assistantMessage];
      });
      await _reloadSessions(preferSessionId: session.id);
      _scrollToBottom();
    } catch (error) {
      if (mounted) _showMessage('AI Chat 发送失败：$error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _appendSources(
    String reply,
    List<KnowledgeContextSource> contextSources,
  ) {
    if (contextSources.isEmpty) {
      return '$reply\n\n参考资料：当前知识库没有检索到强相关资料，本回答可能需要你补充更多资料后再确认。';
    }

    final sourceLines = contextSources
        .asMap()
        .entries
        .map((entry) {
          final index = entry.key + 1;
          final source = entry.value;
          return '$index. ${source.documentTitle} / ${source.citationTitle}';
        })
        .join('\n');
    return '$reply\n\n参考资料：\n$sourceLines';
  }

  Future<void> _showHistorySheet() async {
    final selected = await showModalBottomSheet<AiChatSessionRecord>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('历史聊天', style: AppTextStyles.h3(sheetContext)),
                const SizedBox(height: 8),
                if (_sessions.isEmpty)
                  const _EmptyChatHint(text: '暂无历史聊天，先发送第一条消息。')
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _sessions.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final session = _sessions[index];
                        return ListTile(
                          title: Text(session.title),
                          subtitle: Text(
                            session.lastMessagePreview.isEmpty
                                ? '空白聊天'
                                : session.lastMessagePreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: session.id == _currentSession?.id
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(sheetContext).pop(session),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _selectSession(selected);
    }
  }

  Future<void> _renameCurrentSession() async {
    final user = _user;
    final session = _currentSession;
    if (user == null || session == null) {
      _showMessage('请先发送一条消息，再重命名聊天');
      return;
    }

    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重命名聊天'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(hintText: '输入聊天标题'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (title == null) return;
    if (title.trim().isEmpty) {
      _showMessage('聊天标题不能为空');
      return;
    }

    await _aiChatRepository.renameSession(
      userId: user.id,
      sessionId: session.id,
      title: title,
    );
    await _reloadSessions(preferSessionId: session.id);
  }

  Future<void> _deleteCurrentSession() async {
    final user = _user;
    final session = _currentSession;
    if (user == null || session == null) {
      _showMessage('当前没有可删除的聊天');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除聊天'),
          content: Text('确定删除“${session.title}”吗？历史消息会一起删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await _aiChatRepository.deleteSession(
      userId: user.id,
      sessionId: session.id,
    );
    await _reloadSessions();
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'new':
        _startNewChat();
        return;
      case 'rename':
        _renameCurrentSession();
        return;
      case 'delete':
        _deleteCurrentSession();
        return;
    }
  }

  String _titleFromMessage(String message) {
    final normalized = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return '新的聊天';
    }
    return normalized.length > 18 ? normalized.substring(0, 18) : normalized;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _currentSession?.title ?? 'AI Chat';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: '历史聊天',
            onPressed: _isLoading ? null : _showHistorySheet,
            icon: const Icon(Icons.history_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '聊天菜单',
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'new', child: Text('新建聊天')),
              PopupMenuItem(value: 'rename', child: Text('重命名聊天')),
              PopupMenuItem(value: 'delete', child: Text('删除聊天')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const _EmptyChatHint(text: '开始新的 AI Chat')
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: _messages.length + (_isSending ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (_isSending && index == _messages.length) {
                              return const _TypingBubble();
                            }
                            return _MessageBubble(message: _messages[index]);
                          },
                        ),
                ),
                _ChatInputBar(
                  controller: _inputController,
                  isSending: _isSending,
                  onSend: _sendMessage,
                ),
              ],
            ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiChatMessageRecord message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isUser ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 6),
            bottomRight: Radius.circular(isUser ? 6 : 18),
          ),
          boxShadow: isUser ? null : AppShadows.cardSoftList,
        ),
        child: Text(
          message.content,
          style: AppTextStyles.bodySmall(context).copyWith(
            color: isUser ? Colors.white : AppColors.textPrimary,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.cardSoftList,
        ),
        child: Text('AI 正在思考...', style: AppTextStyles.bodySmall(context)),
      ),
    );
  }
}

class _ChatInputBar extends StatelessWidget {
  const _ChatInputBar({
    required this.controller,
    required this.isSending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  if (!isSending) onSend();
                },
                decoration: const InputDecoration(
                  hintText: '输入你的问题',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: '发送',
              onPressed: isSending ? null : onSend,
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyChatHint extends StatelessWidget {
  const _EmptyChatHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            const SizedBox(height: 14),
            Text(text, style: AppTextStyles.h3(context)),
            const SizedBox(height: 6),
            Text(
              '可以问知识点、让 AI 帮你规划复习，也可以继续历史聊天。',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall(context),
            ),
          ],
        ),
      ),
    );
  }
}
