import 'package:flutter/material.dart';
import '../../agent/eclaw_chat_controller.dart';
import '../../agent/eclaw_context.dart';
import '../../agent/eclaw_task.dart';
import '../../agent/qsclaw_agent_service.dart';
import '../../database/ai_chat_repository.dart';
import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_context_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_chat_records.dart';
import '../../database/models/knowledge_context_source.dart';
import '../../database/practice_session_repository.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/source_document_repository.dart';
import '../../focus/repository/focus_repository.dart';
import '../../learning/learning_task_repository.dart';
import '../../generator/ai_chat_service.dart';
import '../widgets/eclaw_chat_widgets.dart';
import 'document_detail_page.dart';
import 'import_record_detail_page.dart';
import 'interview/interview_history_page.dart';
import 'interview/interview_prepare_page.dart';
import 'knowledge_graph_page.dart';
import 'library_practice_page.dart';
import 'record_source_page.dart';
import 'tabs/focus_tab_page.dart';
import 'home_page.dart';
import 'tabs/tasks_tab_page.dart';
import 'learning_concept_page.dart';

class AiChatPage extends StatefulWidget {
  const AiChatPage({
    this.authRepository,
    this.llmConfigRepository,
    this.aiChatRepository,
    this.knowledgeContextRepository,
    this.aiChatService,
    this.qsClawAgentService,
    this.database,
    this.initialContext = const EClawContext(),
    this.controller,
    super.key,
  });
  final AuthRepository? authRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiChatRepository? aiChatRepository;
  final KnowledgeContextRepository? knowledgeContextRepository;
  final AiChatService? aiChatService;

  /// Retained constructor compatibility for old routes; EClaw uses the safe executor.
  final QsClawAgentService? qsClawAgentService;
  final AppDatabase? database;
  final EClawContext initialContext;
  final EClawChatController? controller;
  @override
  State<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends State<AiChatPage> {
  late final EClawChatController _chat;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _chat =
        widget.controller ??
        EClawChatController(
          database: widget.database,
          authRepository: widget.authRepository,
          aiChatRepository: widget.aiChatRepository,
          llmConfigRepository: widget.llmConfigRepository,
          knowledgeContextRepository: widget.knowledgeContextRepository,
          aiChatService: widget.aiChatService,
          initialContext: widget.initialContext,
        );
    _chat.addListener(_changed);
    _chat.initialize(
      contextual:
          widget.initialContext.importRecordId != null ||
          widget.initialContext.knowledgeBaseId != null ||
          widget.initialContext.documentId != null,
    );
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _chat.removeListener(_changed);
    if (widget.controller == null) _chat.dispose();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_chat.busy || _input.text.trim().isEmpty) return;
    final text = _input.text;
    _input.clear();
    await _chat.send(text);
    if (_chat.tasks.isNotEmpty && _chat.tasks.last.command == text.trim()) {
      await _navigateRequested(_chat.tasks.last);
    }
  }

  Future<void> _continue(AgentTask task, {bool confirm = false}) async {
    await _chat.continueTask(task, confirm: confirm);
    await _navigateRequested(task);
  }

  Future<void> _navigateRequested(AgentTask task) async {
    if (task.status != 'completed' || !mounted) return;
    final navigation = task.steps
        .where(
          (s) =>
              s.tool == 'navigate_to_page' &&
              s.status == AgentStepStatus.completed &&
              s.result['navigationOpened'] != true,
        )
        .lastOrNull;
    if (navigation == null) return;
    navigation.result = {...navigation.result, 'navigationOpened': true};
    await _chat.tasksRepository.save(task);
    if (mounted) await _open(navigation.result);
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  String get _scopeLabel {
    if (_chat.context.importRecordId != null ||
        _chat.context.documentId != null) {
      return '当前记录';
    }
    final id = _chat.context.knowledgeBaseId;
    if (id == null) return '全部知识库';
    return _chat.libraries.where((l) => l.id == id).firstOrNull?.name ??
        '当前知识库（不可用）';
  }

  Future<void> _chooseScope() async {
    if (_chat.busy || _chat.user == null) return;
    final chosen = await showModalBottomSheet<EClawContext>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                '知识库范围',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_chat.recordContext != null)
              ListTile(
                title: const Text('当前记录'),
                subtitle: const Text('仅检索唤起助手时的资料'),
                onTap: () => Navigator.pop(sheet, _chat.recordContext),
              ),
            ListTile(
              title: const Text('全部知识库'),
              onTap: () => Navigator.pop(sheet, const EClawContext()),
            ),
            for (final library in _chat.libraries)
              ListTile(
                title: Text(library.name),
                subtitle: const Text('当前知识库'),
                leading: const Icon(Icons.library_books_outlined),
                trailing:
                    _chat.context.knowledgeBaseId == library.id &&
                        _chat.context.importRecordId == null
                    ? const Icon(Icons.check, color: eclawBlue)
                    : null,
                onTap: () => Navigator.pop(
                  sheet,
                  EClawContext(knowledgeBaseId: library.id),
                ),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _guard(() => _chat.setContext(chosen));
  }

  Future<void> _history() async {
    final selected = await showModalBottomSheet<AiChatSessionRecord>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .55,
          child: Column(
            children: [
              const ListTile(title: Text('历史对话')),
              Expanded(
                child: _chat.sessions.isEmpty
                    ? const Center(child: Text('暂无历史对话'))
                    : ListView.builder(
                        itemCount: _chat.sessions.length,
                        itemBuilder: (_, index) {
                          final session = _chat.sessions[index];
                          return ListTile(
                            title: Text(
                              session.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              session.lastMessagePreview,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: session.id == _chat.session?.id
                                ? const Icon(Icons.check, color: eclawBlue)
                                : null,
                            onTap: () => Navigator.pop(sheet, session),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null) await _guard(() => _chat.select(selected));
  }

  Future<void> _menu(String action) async {
    if (action == 'new') {
      _chat.newChat();
      _input.clear();
      return;
    }
    if (_chat.session == null) return;
    if (action == 'rename') {
      final editor = TextEditingController(text: _chat.session!.title);
      final title = await showDialog<String>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('重命名对话'),
          content: TextField(
            controller: editor,
            maxLength: 30,
            decoration: const InputDecoration(hintText: '输入对话标题'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, editor.text.trim()),
              child: const Text('保存'),
            ),
          ],
        ),
      );
      // The route's exit animation still references the editor until next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => editor.dispose());
      if (title != null && title.isNotEmpty) {
        await _guard(() => _chat.rename(title));
      }
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('删除对话'),
          content: const Text('历史消息和关联任务记录会一起删除，已生成的学习资料会保留。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) await _guard(_chat.delete);
    }
  }

  Future<void> _source(KnowledgeContextSource source) async {
    await _guard(() async {
      final record = await ImportRecordRepository(
        database: _chat.database,
      ).forDocument(_chat.user!.id, source.documentId);
      if (record == null) throw StateError('来源已删除或无权访问');
      if (!mounted) return;
      final open = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheet).height * .65,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  Text(
                    source.documentTitle,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('${source.location} · ${source.sourceLabel}'),
                  const SizedBox(height: 12),
                  SelectableText(source.snippet),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheet, true),
                    child: const Text('打开原始资料'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (open != true || !mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordSourcePage(
            record: record,
            database: _chat.database,
            initialDocumentId: source.documentId,
          ),
        ),
      );
    });
  }

  Future<void> _open(Map<String, dynamic> result) async {
    await _guard(() async {
      final user = _chat.user;
      if (user == null) return;
      final library =
          result['knowledgeBaseId'] as int? ?? result['libraryId'] as int?;
      final record =
          result['importRecordId'] as int? ?? result['recordId'] as int?;
      final destination = result['destination'];
      Widget? page;
      switch (destination) {
        case 'practice':
          final scope = PracticeScope(
            userId: user.id,
            libraryId: library,
            recordId: record,
          );
          if (result['questionIds'] is List) {
            final questions =
                await PracticeSessionRepository(
                  database: _chat.database,
                ).questions(
                  scope,
                  questionIds: List<int>.from(result['questionIds'] as List),
                );
            if (questions.isEmpty) throw StateError('生成的题目已删除或移出当前范围');
            page = ScopedPracticeRunner(
              scope: scope,
              questions: questions,
              database: _chat.database,
            );
          } else {
            page = LibraryPracticePage(
              libraryId: library,
              recordId: record,
              database: _chat.database,
            );
          }
        case 'wrong':
          page = LibraryPracticePage(
            libraryId: library,
            recordId: record,
            database: _chat.database,
            wrongOnly: true,
          );
        case 'graph':
          final ids = result['libraryIds'] is List
              ? List<int>.from(result['libraryIds'] as List)
              : library == null
              ? <int>[]
              : [library];
          page = KnowledgeGraphPage(
            userId: user.id,
            initialLibraryIds: ids,
            database: _chat.database,
          );
        case 'interview':
          page = InterviewPreparePage(
            userId: user.id,
            libraryId: library,
            recordId: record,
            database: _chat.database,
          );
        case 'interview_history':
          page = Scaffold(
            appBar: AppBar(title: const Text('面试报告')),
            body: InterviewHistorySheet(
              userId: user.id,
              libraryId: library,
              recordId: record,
              database: _chat.database,
            ),
          );
        case 'focus':
          page = Scaffold(
            appBar: AppBar(title: const Text('专注与学习任务')),
            body: FocusTabPage(
              authRepository: _chat.auth,
              focusRepository: FocusRepository(database: _chat.database),
              learningTaskRepository: LearningTaskRepository(
                database: _chat.database,
              ),
              initialTaskId: result['taskId'] as int?,
            ),
          );
        case 'tasks':
          page = Scaffold(
            appBar: AppBar(title: const Text('学习任务')),
            body: TasksTabPage(
              authRepository: _chat.auth,
              learningTaskRepository: LearningTaskRepository(
                database: _chat.database,
              ),
              sourceDocumentRepository: SourceDocumentRepository(
                database: _chat.database,
              ),
              aiGenerationRepository: AiGenerationRepository(
                database: _chat.database,
              ),
              onStartFocus: (taskId) async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('专注')),
                      body: FocusTabPage(
                        authRepository: _chat.auth,
                        focusRepository: FocusRepository(
                          database: _chat.database,
                        ),
                        learningTaskRepository: LearningTaskRepository(
                          database: _chat.database,
                        ),
                        initialTaskId: taskId,
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        case 'concept':
          final conceptId = result['conceptId'] as int?;
          if (conceptId == null) throw StateError('缺少知识点，请重新选择');
          page = LearningConceptPage(
            conceptId: conceptId,
            database: _chat.database,
          );
        case 'source':
          page = record != null
              ? ImportRecordDetailPage(
                  recordId: record,
                  userId: user.id,
                  database: _chat.database,
                )
              : result['documentId'] is int
              ? DocumentDetailPage(documentId: result['documentId'] as int)
              : null;
        case 'knowledge':
          // One knowledge base in the product: the shelf. This used to open the
          // older KnowledgeTabPage (a categorised grid), which meant two
          // different "知识库" experiences depending on where you came from.
          page = const HomePage(initialTab: 1);
        case 'home':
          if (mounted) Navigator.pop(context);
          return;
      }
      if (page != null && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
      }
    });
  }

  String _preview(AgentTask task) {
    final step = task.waitingStep;
    if (step == null) return '';
    final args = _chat.executor.resolvedArgs(task, step);
    if (step.tool == 'create_knowledge_library' ||
        step.tool == 'move_document_to_library') {
      final search = task.steps
          .where((s) => s.tool == 'search_documents')
          .firstOrNull;
      final docs = search?.result['documents'] as List? ?? [];
      final name =
          args['name'] ??
          task.steps
              .where((s) => s.tool == 'create_knowledge_library')
              .firstOrNull
              ?.result['libraryName'] ??
          args['libraryId'];
      return '找到 ${docs.length} 份资料。\n准备移动至：「$name」\n${docs.take(5).map((d) => '· ${d['title']}').join('\n')}${docs.length > 5 ? '\n…' : ''}';
    }
    if (step.tool == 'create_practice_task') {
      return '准备基于所选资料生成 ${args['count'] ?? 10} 道练习题，会调用你配置的模型。';
    }
    if (step.tool == 'create_learning_task') {
      return '${args['title']}\n计划 ${args['minutes'] ?? 60} 分钟，确认后创建学习任务。';
    }
    if (step.tool == 'undo_document_move') return '将这次整理的资料移回原知识库。';
    return '此操作会${step.tool.startsWith('generate') ? '调用模型并追加生成内容' : '写入数据'}。确认后开始。';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F8FF),
    resizeToAvoidBottomInset: true,
    appBar: AppBar(
      backgroundColor: const Color(0xFFF4F8FF),
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'EClaw',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: Color(0xFF10274B),
            ),
          ),
          InkWell(
            onTap: _chat.busy ? null : _chooseScope,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _scopeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF4A6C9B),
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    size: 16,
                    color: Color(0xFF4A6C9B),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '历史对话',
          onPressed: _chat.loading || _chat.busy ? null : _history,
          icon: const Icon(Icons.history_rounded),
        ),
        PopupMenuButton<String>(
          tooltip: '对话菜单',
          enabled: !_chat.busy,
          onSelected: _menu,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('新建对话')),
            PopupMenuItem(value: 'rename', child: Text('重命名对话')),
            PopupMenuItem(value: 'delete', child: Text('删除对话')),
          ],
        ),
      ],
    ),
    body: _chat.loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              if (_chat.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Text(
                    _chat.error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              Expanded(
                child: _chat.messages.isEmpty
                    ? EClawWelcome(
                        onPrompt: (prompt) {
                          _input.text = prompt;
                          _focus.requestFocus();
                        },
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        itemCount: _chat.messages.length + (_chat.busy ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index == _chat.messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'EClaw 正在处理…',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueGrey,
                                ),
                              ),
                            );
                          }
                          final message = _chat.messages[index];
                          final task = _chat.tasks
                              .where((t) => t.id == message.metadata['taskId'])
                              .firstOrNull;
                          final citations = _chat.citations(message);
                          if (task != null) {
                            for (final step in task.steps) {
                              for (final raw
                                  in step.result['citations'] as List? ?? []) {
                                final source = KnowledgeContextSource.fromJson(
                                  Map<String, dynamic>.from(raw as Map),
                                );
                                if (!citations.any(
                                  (s) =>
                                      s.sourceId == source.sourceId &&
                                      s.documentId == source.documentId &&
                                      s.sourceType == source.sourceType,
                                )) {
                                  citations.add(source);
                                }
                              }
                            }
                          }
                          return EClawMessageBubble(
                            message: message,
                            citations: citations,
                            onSource: _source,
                            taskCard: task == null
                                ? null
                                : EClawTaskCard(
                                    task: task,
                                    busy: _chat.busy,
                                    preview: _preview(task),
                                    onConfirm: () =>
                                        _continue(task, confirm: true),
                                    onCancel: () =>
                                        _guard(() => _chat.cancelTask(task)),
                                    onRetry: () => _continue(task),
                                    onOpen: _open,
                                    onUndo: (key) =>
                                        _guard(() => _chat.undo(task, key)),
                                  ),
                          );
                        },
                      ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: '问知识点，或让 EClaw 帮你完成任务...',
                            hintStyle: const TextStyle(fontSize: 13),
                            filled: true,
                            fillColor: const Color(0xFFF4F7FC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: '发送',
                        onPressed: _chat.busy || _chat.user == null
                            ? null
                            : _send,
                        style: IconButton.styleFrom(backgroundColor: eclawBlue),
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
