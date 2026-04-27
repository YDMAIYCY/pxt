import 'package:flutter/material.dart';

import '../../../database/ai_generation_repository.dart';
import '../../../database/auth_repository.dart';
import '../../../database/models/ai_generation_task_record.dart';
import '../../../database/models/ai_result_records.dart';
import '../../../database/models/source_document_record.dart';
import '../../../database/source_document_repository.dart';
import '../document_detail_page.dart';
import '../practice_review_page.dart';
import '../wrong_question_page.dart';

// ========== 任务中心 Tab ==========
// 首页只展示任务入口，点击后进入对应列表页处理具体任务。

class TasksTabPage extends StatefulWidget {
  const TasksTabPage({
    this.authRepository,
    this.sourceDocumentRepository,
    this.aiGenerationRepository,
    super.key,
  });

  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final AiGenerationRepository? aiGenerationRepository;

  @override
  State<TasksTabPage> createState() => _TasksTabPageState();
}

class _TasksTabPageState extends State<TasksTabPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late Future<_TaskCenterData> _future;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _future = _loadData();
  }

  Future<_TaskCenterData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }

    final documents = await _sourceDocumentRepository.fetchAllSourceDocuments(
      userId: user.id,
      limit: 300,
    );
    final aiTasks = await _aiGenerationRepository.fetchAiTasksByUser(
      userId: user.id,
      limit: 300,
    );
    final pendingPractice = await _aiGenerationRepository
        .fetchPracticeQuestionsByUser(
          userId: user.id,
          reviewStatus: PracticeQuestionReviewStatus.pending,
          limit: 300,
        );
    final wrongQuestions = await _aiGenerationRepository
        .fetchPracticeQuestionsByUser(
          userId: user.id,
          reviewStatus: PracticeQuestionReviewStatus.wrong,
          limit: 300,
        );
    final masteredQuestions = await _aiGenerationRepository
        .fetchPracticeQuestionsByUser(
          userId: user.id,
          reviewStatus: PracticeQuestionReviewStatus.mastered,
          limit: 300,
        );
    return _TaskCenterData(
      documents: documents,
      aiTasks: aiTasks,
      pendingPractice: pendingPractice,
      wrongQuestions: wrongQuestions,
      masteredQuestions: masteredQuestions,
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openTaskList(_TaskListKind kind) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TaskListPage(
          kind: kind,
          authRepository: _authRepository,
          sourceDocumentRepository: _sourceDocumentRepository,
          aiGenerationRepository: _aiGenerationRepository,
        ),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TaskCenterData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _StatePanel(
            icon: Icons.error_outline_rounded,
            title: '任务中心加载失败',
            description: '请稍后重试。',
            onPressed: _refresh,
          );
        }

        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Header(),
                      const SizedBox(height: 14),
                      _TaskBoard(data: data, onOpenList: _openTaskList),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskListPage extends StatefulWidget {
  const _TaskListPage({
    required this.kind,
    required this.authRepository,
    required this.sourceDocumentRepository,
    required this.aiGenerationRepository,
  });

  final _TaskListKind kind;
  final AuthRepository authRepository;
  final SourceDocumentRepository sourceDocumentRepository;
  final AiGenerationRepository aiGenerationRepository;

  @override
  State<_TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<_TaskListPage> {
  late Future<_TaskListData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadData();
  }

  Future<_TaskListData> _loadData() async {
    await widget.authRepository.ensureInitialized();
    final user = await widget.authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }

    switch (widget.kind) {
      case _TaskListKind.pendingPractice:
        return _TaskListData(
          questions: await widget.aiGenerationRepository
              .fetchPracticeQuestionsByUser(
                userId: user.id,
                reviewStatus: PracticeQuestionReviewStatus.pending,
                limit: 300,
              ),
        );
      case _TaskListKind.wrongQuestions:
        return _TaskListData(
          questions: await widget.aiGenerationRepository
              .fetchPracticeQuestionsByUser(
                userId: user.id,
                reviewStatus: PracticeQuestionReviewStatus.wrong,
                limit: 300,
              ),
        );
      case _TaskListKind.activeFlow:
        return _TaskListData(
          documents: await widget.sourceDocumentRepository
              .fetchAllSourceDocuments(userId: user.id, limit: 300),
          aiTasks: await widget.aiGenerationRepository.fetchAiTasksByUser(
            userId: user.id,
            limit: 300,
          ),
        );
      case _TaskListKind.masteredQuestions:
        return _TaskListData(
          questions: await widget.aiGenerationRepository
              .fetchPracticeQuestionsByUser(
                userId: user.id,
                reviewStatus: PracticeQuestionReviewStatus.mastered,
                limit: 300,
              ),
        );
    }
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openPractice([int? questionId]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeReviewPage(initialQuestionId: questionId),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openWrongQuestion(PracticeQuestionWithDocument item) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => WrongQuestionPage(item: item)));
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openDocument(int documentId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentDetailPage(documentId: documentId),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(_titleOf(widget.kind)),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0B1324),
      ),
      body: FutureBuilder<_TaskListData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatePanel(
              icon: Icons.error_outline_rounded,
              title: '列表加载失败',
              description: '请稍后重试。',
              onPressed: _refresh,
            );
          }

          final data = snapshot.data ?? const _TaskListData();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              physics: const AlwaysScrollableScrollPhysics(),
              children: _buildItems(data),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildItems(_TaskListData data) {
    switch (widget.kind) {
      case _TaskListKind.pendingPractice:
        if (data.questions.isEmpty) {
          return [const _EmptyHint(text: '暂无待刷复习题。生成复习题后会出现在这里。')];
        }
        return data.questions
            .map(
              (item) => _TaskTile(
                title: item.question.questionText,
                subtitle: item.documentTitle,
                status: '待刷',
                onTap: () => _openPractice(item.question.id),
              ),
            )
            .toList(growable: false);
      case _TaskListKind.wrongQuestions:
        if (data.questions.isEmpty) {
          return [const _EmptyHint(text: '暂无待处理错题。')];
        }
        return data.questions
            .map(
              (item) => _TaskTile(
                title: item.question.questionText,
                subtitle: '${item.documentTitle} / 正确答案可点入查看',
                status: '待处理',
                onTap: () => _openWrongQuestion(item),
              ),
            )
            .toList(growable: false);
      case _TaskListKind.activeFlow:
        final tiles = <Widget>[
          ...data.documents
              .where(
                (document) =>
                    document.ocrStatus != SourceDocumentOcrStatus.success,
              )
              .map(
                (document) => _TaskTile(
                  title: document.title,
                  subtitle: 'OCR ${document.ocrStatusLabel}',
                  status: _statusLabel(document.ocrStatus),
                  onTap: () => _openDocument(document.id),
                ),
              ),
          ...data.aiTasks
              .where((task) => task.status != AiTaskStatus.completed)
              .map(
                (task) => _TaskTile(
                  title: '${task.documentTitle} -> ${task.taskLabel}',
                  subtitle: task.errorMessage?.isNotEmpty == true
                      ? task.errorMessage!
                      : _formatTime(task.updatedAt),
                  status: _statusLabel(task.status),
                  onTap: () => _openDocument(task.documentId),
                ),
              ),
        ];
        if (tiles.isEmpty) {
          return [const _EmptyHint(text: '暂无进行中的 OCR 或 AI 任务。')];
        }
        return tiles;
      case _TaskListKind.masteredQuestions:
        if (data.questions.isEmpty) {
          return [const _EmptyHint(text: '暂无已掌握题目。')];
        }
        return data.questions
            .map(
              (item) => _TaskTile(
                title: item.question.questionText,
                subtitle:
                    '${item.documentTitle} / 答案：${item.question.answerText ?? '暂无'}',
                status: '已掌握',
                onTap: () => _openDocument(item.question.documentId),
              ),
            )
            .toList(growable: false);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFEF2F2), Color(0xFFFFFBEB)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '任务中心',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF0B1324),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点击任务标签，进入对应列表处理。',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskBoard extends StatelessWidget {
  const _TaskBoard({required this.data, required this.onOpenList});

  final _TaskCenterData data;
  final ValueChanged<_TaskListKind> onOpenList;

  @override
  Widget build(BuildContext context) {
    final items = [
      _BoardItem(
        kind: _TaskListKind.pendingPractice,
        title: '待刷复习题',
        value: '${data.pendingPractice.length}',
        icon: Icons.quiz_rounded,
        color: const Color(0xFFFFF7ED),
      ),
      _BoardItem(
        kind: _TaskListKind.wrongQuestions,
        title: '待处理错题',
        value: '${data.wrongQuestions.length}',
        icon: Icons.report_problem_rounded,
        color: const Color(0xFFFEF2F2),
      ),
      _BoardItem(
        kind: _TaskListKind.activeFlow,
        title: '进行中任务',
        value: '${data.activeFlowCount}',
        icon: Icons.auto_mode_rounded,
        color: const Color(0xFFEFF6FF),
      ),
      _BoardItem(
        kind: _TaskListKind.masteredQuestions,
        title: '已掌握题目',
        value: '${data.masteredQuestions.length}',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFFF0FDF4),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: _BoardCard(
                    item: item,
                    onTap: () => onOpenList(item.kind),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _BoardCard extends StatelessWidget {
  const _BoardCard({required this.item, required this.onTap});

  final _BoardItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: item.color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: const Color(0xFF9A3412)),
              const SizedBox(height: 8),
              Text(
                item.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: const Color(0xFF7C2D12),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF7C2D12),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF9A3412),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0B1324),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEDD5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Color(0xFF9A3412),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: const Color(0xFF64748B)),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => onPressed(), child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

class _TaskCenterData {
  const _TaskCenterData({
    required this.documents,
    required this.aiTasks,
    required this.pendingPractice,
    required this.wrongQuestions,
    required this.masteredQuestions,
  });

  final List<SourceDocumentRecord> documents;
  final List<AiTaskWithDocument> aiTasks;
  final List<PracticeQuestionWithDocument> pendingPractice;
  final List<PracticeQuestionWithDocument> wrongQuestions;
  final List<PracticeQuestionWithDocument> masteredQuestions;

  int get activeFlowCount {
    final activeOcr = documents
        .where((item) => item.ocrStatus != SourceDocumentOcrStatus.success)
        .length;
    final activeAi = aiTasks
        .where((item) => item.status != AiTaskStatus.completed)
        .length;
    return activeOcr + activeAi;
  }
}

class _TaskListData {
  const _TaskListData({
    this.documents = const <SourceDocumentRecord>[],
    this.aiTasks = const <AiTaskWithDocument>[],
    this.questions = const <PracticeQuestionWithDocument>[],
  });

  final List<SourceDocumentRecord> documents;
  final List<AiTaskWithDocument> aiTasks;
  final List<PracticeQuestionWithDocument> questions;
}

class _BoardItem {
  const _BoardItem({
    required this.kind,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final _TaskListKind kind;
  final String title;
  final String value;
  final IconData icon;
  final Color color;
}

enum _TaskListKind {
  pendingPractice,
  wrongQuestions,
  activeFlow,
  masteredQuestions,
}

String _titleOf(_TaskListKind kind) {
  switch (kind) {
    case _TaskListKind.pendingPractice:
      return '待刷复习题';
    case _TaskListKind.wrongQuestions:
      return '待处理错题';
    case _TaskListKind.activeFlow:
      return '进行中任务';
    case _TaskListKind.masteredQuestions:
      return '已掌握题目';
  }
}

String _statusLabel(String status) {
  if (status == SourceDocumentOcrStatus.processing) {
    return '进行中';
  }
  if (status == SourceDocumentOcrStatus.success) {
    return '已完成';
  }
  if (status == SourceDocumentOcrStatus.failed) {
    return '失败';
  }

  switch (status) {
    case AiTaskStatus.running:
      return '进行中';
    case AiTaskStatus.completed:
      return '已完成';
    case AiTaskStatus.failed:
      return '失败';
    case AiTaskStatus.pending:
    default:
      return '待处理';
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
