import 'package:flutter/material.dart';

import '../../agent/qsclaw_agent_service.dart';
import '../../agent/qsclaw_tool_registry.dart';
import '../../database/ai_chat_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/knowledge_context_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_chat_records.dart';
import '../../database/models/knowledge_context_source.dart';
import '../../database/models/user_profile.dart';
import '../../generator/ai_chat_service.dart';
import '../theme/app_theme.dart';
import 'practice_review_page.dart';
import 'tabs/knowledge_tab_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({
    this.authRepository,
    this.llmConfigRepository,
    this.aiChatRepository,
    this.knowledgeContextRepository,
    this.aiChatService,
    this.qsClawAgentService,
    super.key,
  });

  final AuthRepository? authRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiChatRepository? aiChatRepository;
  final KnowledgeContextRepository? knowledgeContextRepository;
  final AiChatService? aiChatService;
  final QsClawAgentService? qsClawAgentService;

  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final AuthRepository _authRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiChatRepository _aiChatRepository;
  late final KnowledgeContextRepository _knowledgeContextRepository;
  late final AiChatService _aiChatService;
  late final QsClawAgentService _qsClawAgentService;

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
    _qsClawAgentService = widget.qsClawAgentService ?? QsClawAgentService();
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
      _showMessage('QSClaw 加载失败：$error');
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
      _showMessage('请输入指令或问题');
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

      final isAgentCommand = _isAgentCommand(text);
      final assistantContent = isAgentCommand
          ? await _runAgentCommand(user.id, text)
          : await _answerKnowledgeQuestion(user.id, text);

      final assistantMessage = await _aiChatRepository.appendMessage(
        sessionId: session.id,
        role: AiChatMessageRole.assistant,
        content: assistantContent,
        provider: isAgentCommand ? 'qsclaw' : null,
        model: isAgentCommand ? 'app-tools' : null,
      );
      await _aiChatRepository.touchSessionPreview(
        sessionId: session.id,
        preview: assistantContent,
      );

      if (!mounted) return;
      setState(() => _messages = [..._messages, assistantMessage]);
      await _reloadSessions(preferSessionId: session.id);
      _scrollToBottom();
    } catch (error) {
      if (mounted) _showMessage('QSClaw 执行失败：$error');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<String> _answerKnowledgeQuestion(int userId, String text) async {
    final config = await _llmConfigRepository.getByUserId(userId);
    if (config == null || !config.isConfigured) {
      return '我还不能回答资料问题。请先到“我的”页面配置 AI 大模型 API Key。';
    }

    final contextSources = await _knowledgeContextRepository.search(
      userId: userId,
      query: text,
    );
    final reply = await _aiChatService.generateReply(
      config: config,
      messages: _messages,
      contextSources: contextSources,
    );
    return _appendSources(reply, contextSources);
  }

  Future<String> _runAgentCommand(int userId, String text) async {
    final result = await _qsClawAgentService.runCommand(
      userId: userId,
      command: text,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _performNavigation(result);
    });
    return _formatAgentReport(result);
  }

  Future<void> _performNavigation(QsClawRunResult result) async {
    final target = result.navigationTarget;
    if (target == null || !mounted) return;

    switch (target) {
      case QsClawNavigationTarget.knowledge:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('知识库')),
              body: const KnowledgeTabPage(),
            ),
          ),
        );
        break;
      case QsClawNavigationTarget.practice:
        await Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const PracticeReviewPage()));
        break;
      case QsClawNavigationTarget.home:
      case QsClawNavigationTarget.aiChat:
        break;
    }
  }

  String _formatAgentReport(QsClawRunResult result) {
    final lines = <String>['已完成：'];
    if (result.library != null) {
      lines.add('- 准备知识库：${result.library!.name}');
    }
    if (result.matchedDocuments.isNotEmpty) {
      lines.add('- 找到 ${result.matchedDocuments.length} 份匹配资料');
    }
    if (result.movedCount > 0) {
      lines.add('- 移动 ${result.movedCount} 份资料到知识库');
    }
    if (result.navigationTarget != null) {
      lines.add(
        '- 打开${QsClawNavigationTarget.labelOf(result.navigationTarget!)}',
      );
    }
    for (final step in result.executedSteps) {
      lines.add('- ${step.message}');
    }
    if (result.status == QsClawRunStatus.waitingForSources) {
      lines.add('\n没有找到匹配资料。你可以先导入资料，或者让我搜索全部资料。');
    }
    if (lines.length == 1) {
      lines.add('- 我已处理这条指令');
    }
    return lines.join('\n');
  }

  bool _isAgentCommand(String text) {
    final lower = text.toLowerCase();
    const commandWords = [
      '打开',
      '进入',
      '去',
      '创建',
      '新建',
      '整理',
      '移动',
      '归类',
      '生成',
      '植入',
      '注入',
      '演示数据',
      '复习',
      '面试',
      '知识库',
      'pdf',
      'qsclaw',
    ];
    return commandWords.any((word) => text.contains(word)) ||
        lower.contains('open') ||
        lower.contains('create') ||
        lower.contains('move');
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
                Text('历史对话', style: AppTextStyles.h3(sheetContext)),
                const SizedBox(height: 8),
                if (_sessions.isEmpty)
                  const _EmptyChatHint(text: '暂无历史对话')
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
                                ? '空白对话'
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
      _showMessage('请先发送一条消息，再重命名对话');
      return;
    }

    final controller = TextEditingController(text: session.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('重命名对话'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(hintText: '输入对话标题'),
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
      _showMessage('对话标题不能为空');
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
      _showMessage('当前没有可删除的对话');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除对话'),
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
      return '新的对话';
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('QSClaw'),
        actions: [
          IconButton(
            tooltip: '历史对话',
            onPressed: _isLoading ? null : _showHistorySheet,
            icon: const Icon(Icons.history_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: '对话菜单',
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'new', child: Text('新建对话')),
              PopupMenuItem(value: 'rename', child: Text('重命名对话')),
              PopupMenuItem(value: 'delete', child: Text('删除对话')),
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
                      ? const _EmptyChatHint(text: 'QSClaw')
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
            topLeft: const Radius.circular(8),
            topRight: const Radius.circular(8),
            bottomLeft: Radius.circular(isUser ? 8 : 2),
            bottomRight: Radius.circular(isUser ? 2 : 8),
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
          borderRadius: BorderRadius.circular(8),
          boxShadow: AppShadows.cardSoftList,
        ),
        child: Text('QSClaw 正在处理...', style: AppTextStyles.bodySmall(context)),
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
                  hintText: '问知识点，或让我操作 App',
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
        child: Text(text, style: AppTextStyles.h1(context)),
      ),
    );
  }
}
