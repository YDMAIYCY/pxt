import 'package:flutter/foundation.dart';
import 'dart:async';
import '../database/agent_task_repository.dart';
import '../database/ai_chat_repository.dart';
import '../database/app_database.dart';
import '../database/auth_repository.dart';
import '../database/knowledge_context_repository.dart';
import '../database/knowledge_library_repository.dart';
import '../database/llm_config_repository.dart';
import '../database/models/ai_chat_records.dart';
import '../database/models/knowledge_context_source.dart';
import '../database/models/knowledge_library_record.dart';
import '../database/models/user_profile.dart';
import '../generator/ai_chat_service.dart';
import 'agent_task_executor.dart';
import 'eclaw_context.dart';
import 'eclaw_planner.dart';
import 'eclaw_task.dart';
import 'eclaw_tool_registry.dart';

class EClawChatController extends ChangeNotifier {
  EClawChatController({
    AppDatabase? database,
    AuthRepository? authRepository,
    AiChatRepository? aiChatRepository,
    LlmConfigRepository? llmConfigRepository,
    KnowledgeContextRepository? knowledgeContextRepository,
    AiChatService? aiChatService,
    EClawContext initialContext = const EClawContext(),
  }) : database = database ?? AppDatabase.instance,
       auth = authRepository ?? AuthRepository(database: database),
       chats = aiChatRepository ?? AiChatRepository(database: database),
       configs = llmConfigRepository ?? LlmConfigRepository(database: database),
       knowledge =
           knowledgeContextRepository ??
           KnowledgeContextRepository(database: database),
       ai = aiChatService ?? AiChatService(),
       context = initialContext {
    tasksRepository = AgentTaskRepository(database: this.database);
    registry = EClawToolRegistry(database: this.database);
    executor = AgentTaskExecutor(
      registry: registry,
      repository: tasksRepository,
    );
  }
  final AppDatabase database;
  final AuthRepository auth;
  final AiChatRepository chats;
  final LlmConfigRepository configs;
  final KnowledgeContextRepository knowledge;
  final AiChatService ai;
  late final AgentTaskRepository tasksRepository;
  late final EClawToolRegistry registry;
  late final AgentTaskExecutor executor;
  UserProfile? user;
  EClawContext context;
  EClawContext? recordContext;
  List<KnowledgeLibraryRecord> libraries = [];
  List<AiChatSessionRecord> sessions = [];
  List<AiChatMessageRecord> messages = [];
  List<AgentTask> tasks = [];
  AiChatSessionRecord? session;
  bool loading = true, busy = false;
  String? error;
  bool _disposed = false;
  StreamSubscription<String>? _taskUpdates;
  void changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _taskUpdates?.cancel();
    super.dispose();
  }

  Future<void> initialize({bool contextual = false}) async {
    try {
      await auth.ensureInitialized();
      user = await auth.getCurrentUserProfile();
      if (user == null) throw StateError('请先登录');
      libraries = await KnowledgeLibraryRepository(
        database: database,
      ).fetchLibraries(user!.id);
      await knowledge.validateScope(user!.id, context);
      if (context.importRecordId != null || context.documentId != null) {
        recordContext = context;
      }
      sessions = await chats.fetchSessions(userId: user!.id);
      _taskUpdates = AgentTaskExecutor.updates.listen((key) async {
        if (_disposed ||
            session == null ||
            !tasks.any((t) => executor.key(t) == key)) {
          return;
        }
        tasks = await tasksRepository.forSession(user!.id, session!.id);
        changed();
      });
      if (!contextual && sessions.isNotEmpty) await select(sessions.first);
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      changed();
    }
  }

  Future<void> select(AiChatSessionRecord selected) async {
    if (busy) return;
    await chats.requireOwner(user!.id, selected.id);
    final nextContext = await chats.loadContext(user!.id, selected.id);
    // A deleted context remains a closed scope until the user explicitly
    // chooses another one; it must never silently widen to all libraries.
    context = nextContext;
    session = selected;
    if (context.importRecordId != null || context.documentId != null) {
      recordContext = context;
    }
    messages = await chats.fetchMessages(sessionId: selected.id, limit: 500);
    tasks = await tasksRepository.forSession(user!.id, selected.id);
    for (final task in tasks) {
      await executor.recover(task);
    }
    changed();
  }

  void newChat() {
    if (busy) return;
    session = null;
    messages = [];
    tasks = [];
    error = null;
    changed();
  }

  Future<void> setContext(EClawContext value) async {
    if (busy) return;
    await knowledge.validateScope(user!.id, value);
    context = value;
    if (value.importRecordId != null || value.documentId != null) {
      recordContext = value;
    }
    if (session != null) {
      await chats.saveContext(user!.id, session!.id, context);
    }
    changed();
  }

  Future<void> _refreshSessions() async {
    sessions = await chats.fetchSessions(userId: user!.id);
    libraries = await KnowledgeLibraryRepository(
      database: database,
    ).fetchLibraries(user!.id);
    changed();
  }

  Future<void> rename(String title) async {
    if (session == null || busy) return;
    await chats.renameSession(
      userId: user!.id,
      sessionId: session!.id,
      title: title,
    );
    await _refreshSessions();
    session = sessions.where((s) => s.id == session!.id).firstOrNull;
    changed();
  }

  Future<void> delete() async {
    if (session == null || busy) return;
    await chats.deleteSession(userId: user!.id, sessionId: session!.id);
    newChat();
    await _refreshSessions();
  }

  Future<void> send(String text) async {
    if (busy || user == null || text.trim().isEmpty) return;
    busy = true;
    error = null;
    changed();
    try {
      final normalized = text.trim();
      session ??= await chats.createSession(
        userId: user!.id,
        title: normalized.length > 18
            ? normalized.substring(0, 18)
            : normalized,
      );
      await chats.requireOwner(user!.id, session!.id);
      await chats.saveContext(user!.id, session!.id, context);
      final request = await chats.appendMessage(
        sessionId: session!.id,
        role: AiChatMessageRole.user,
        content: normalized,
      );
      messages = [...messages, request];
      changed();
      final local = EClawPlanner.localReply(normalized);
      if (local != null) {
        await _answer(local);
      } else if (EClawPlanner.isToolRequest(normalized)) {
        await knowledge.validateScope(user!.id, context);
        final config = await configs.getByUserId(user!.id);
        final latestLibrary = tasks.reversed
            .expand((t) => t.steps.reversed)
            .where(
              (s) =>
                  s.status == AgentStepStatus.completed &&
                  s.result['libraryId'] is int,
            )
            .firstOrNull
            ?.result['libraryId'];
        final previousName = libraries
            .where((l) => l.id == latestLibrary)
            .firstOrNull
            ?.name;
        final steps = await EClawPlanner().plan(
          normalized,
          context,
          registry,
          config: config,
          previousLibraryName: previousName,
        );
        final task = await tasksRepository.create(
          userId: user!.id,
          sessionId: session!.id,
          requestKey: 'message:${request.id}',
          command: normalized,
          context: context,
          steps: steps,
        );
        tasks = [...tasks, task];
        await _answer(
          '正在处理你的学习任务',
          metadata: {'taskId': task.id},
          provider: 'qsclaw',
          model: 'app-tools',
        );
        await executor.run(task, onChanged: changed);
      } else {
        final citations = await knowledge.search(
          userId: user!.id,
          query: normalized,
          knowledgeBaseId: context.knowledgeBaseId,
          importRecordId: context.importRecordId,
          documentId: context.documentId,
        );
        final config = await configs.getByUserId(user!.id);
        if (config == null || !config.isConfigured) {
          await _answer(
            '请先到“我的”页面配置模型 API Key，再让我回答知识问题。你现在仍可以创建知识库、搜索资料和确认整理操作。',
          );
        } else if (citations.isEmpty &&
            (context.knowledgeBaseId != null ||
                context.importRecordId != null ||
                context.documentId != null ||
                RegExp('我的|资料中|讲义中|知识库中').hasMatch(normalized))) {
          await _answer('无法从当前知识库确认答案：没有检索到相关证据。可以更换关键词或检查资料是否已解析。');
        } else {
          final reply = await ai.generateReply(
            config: config,
            messages: messages,
            contextSources: citations,
          );
          await _answer(
            citations.isEmpty ? '$reply\n\n当前知识库没有相关依据，以上为通用知识回答。' : reply,
            metadata: {'citations': citations.map((s) => s.toJson()).toList()},
            provider: config.provider,
            model: config.effectiveModel,
          );
        }
      }
      await _refreshSessions();
    } catch (e) {
      error = '$e';
      if (session != null) {
        try {
          await _answer('本次未完成：$e');
        } catch (_) {
          /* original error stays visible */
        }
      }
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> _answer(
    String content, {
    Map<String, Object?> metadata = const {},
    String? provider,
    String? model,
  }) async {
    final message = await chats.appendMessage(
      sessionId: session!.id,
      role: AiChatMessageRole.assistant,
      content: content,
      metadata: metadata,
      provider: provider,
      model: model,
    );
    messages = [...messages, message];
    await chats.touchSessionPreview(sessionId: session!.id, preview: content);
    changed();
  }

  Future<void> continueTask(AgentTask task, {bool confirm = false}) async {
    if (busy) return;
    busy = true;
    error = null;
    changed();
    try {
      await executor.run(task, confirm: confirm, onChanged: changed);
      await _refreshSessions();
    } catch (e) {
      error = '$e';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> cancelTask(AgentTask task) async {
    await tasksRepository.cancel(user!.id, task.id);
    if (task.status != 'running') {
      task.status = 'cancelled';
      task.cancelRequested = true;
      for (final step in task.steps.where(
        (s) => s.status != AgentStepStatus.completed,
      )) {
        step.status = AgentStepStatus.cancelled;
      }
      await tasksRepository.save(task);
    } else {
      task.cancelRequested = true;
    }
    changed();
  }

  Future<void> undo(AgentTask task, String key) async {
    if (busy) return;
    final steps = [
      AgentTaskStep(
        tool: 'undo_document_move',
        label: '确认撤销整理',
        args: {'operationKey': key},
      ),
    ];
    final next = await tasksRepository.create(
      userId: user!.id,
      sessionId: session!.id,
      requestKey: 'undo:$key',
      command: '撤销整理',
      context: const EClawContext(),
      steps: steps,
    );
    if (!tasks.any((t) => t.id == next.id)) {
      tasks = [...tasks, next];
      await _answer('撤销整理', metadata: {'taskId': next.id});
    }
    await continueTask(next);
  }

  List<KnowledgeContextSource> citations(AiChatMessageRecord message) =>
      (message.metadata['citations'] as List? ?? [])
          .map(
            (s) => KnowledgeContextSource.fromJson(
              Map<String, dynamic>.from(s as Map),
            ),
          )
          .toList();
}
