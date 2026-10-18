import 'package:flutter/material.dart';
import '../../database/import_record_repository.dart';
import 'home_page.dart';

import '../theme/app_theme.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_generation_task_record.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/llm_provider_config.dart';
import '../../database/models/ocr_text_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../../generator/ai_generation_orchestrator.dart';

class AiGenerationPage extends StatefulWidget {
  const AiGenerationPage({
    required this.documentId,
    this.authRepository,
    this.sourceDocumentRepository,
    this.ocrTextRepository,
    this.aiGenerationRepository,
    this.llmConfigRepository,
    this.aiGenerationOrchestrator,
    super.key,
  });

  final int documentId;
  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final OcrTextRepository? ocrTextRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiGenerationOrchestrator? aiGenerationOrchestrator;

  @override
  State<AiGenerationPage> createState() => _AiGenerationPageState();
}

class _AiGenerationPageState extends State<AiGenerationPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final OcrTextRepository _ocrTextRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiGenerationOrchestrator _aiGenerationOrchestrator;

  late Future<_AiPageData> _pageFuture;

  SourceDocumentRecord? _document;
  OcrTextRecord? _ocrRecord;

  int? _importRecordId;
  bool _isGeneratingAll = false;
  final Set<String> _generatingTaskTypes = <String>{};

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _ocrTextRepository = widget.ocrTextRepository ?? OcrTextRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _aiGenerationOrchestrator =
        widget.aiGenerationOrchestrator ?? AiGenerationOrchestrator();
    _pageFuture = _loadPageData();
  }

  Future<_AiPageData> _loadPageData() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();
    if (currentUser == null) {
      throw StateError('登录状态已失效，请重新登录');
    }

    final document = await _sourceDocumentRepository.getSourceDocumentById(
      userId: currentUser.id,
      documentId: widget.documentId,
    );
    if (document == null) {
      throw StateError('资料不存在或无权访问');
    }

    final ocrRecord = await _ocrTextRepository.getByDocumentId(
      widget.documentId,
    );
    final llmConfig = await _llmConfigRepository.getByUserId(currentUser.id);
    final tasks = await _aiGenerationRepository.fetchLatestTasksByDocument(
      widget.documentId,
    );
    final cards = await _aiGenerationRepository.fetchKnowledgeCards(
      widget.documentId,
    );
    final outline = await _aiGenerationRepository.fetchReviewOutline(
      widget.documentId,
    );
    final mindmap = await _aiGenerationRepository.fetchMindmapText(
      widget.documentId,
    );
    final questions = await _aiGenerationRepository.fetchPracticeQuestions(
      widget.documentId,
    );

    _importRecordId = document.importRecordId;
    _document = document;
    _ocrRecord = ocrRecord;

    return _AiPageData(
      document: document,
      ocrRecord: ocrRecord,
      llmConfig: llmConfig,
      tasksByType: {for (final task in tasks) task.taskType: task},
      knowledgeCards: cards,
      reviewOutline: outline,
      mindmapText: mindmap,
      practiceQuestions: questions,
    );
  }

  Future<void> _reloadPageData() async {
    final future = _loadPageData();
    setState(() {
      _pageFuture = future;
    });
    await future;
  }

  Future<LlmProviderConfig?> _loadLatestLlmConfig() async {
    await _authRepository.ensureInitialized();
    final currentUser = await _authRepository.getCurrentUserProfile();
    if (currentUser == null) {
      return null;
    }

    final latestConfig = await _llmConfigRepository.getByUserId(currentUser.id);
    return latestConfig;
  }

  Future<String> _generationText() async {
    final document = _document!;
    if (document.importRecordId == null) return _ocrRecord!.effectiveText;
    final repo = ImportRecordRepository();
    final record = await repo.get(document.userId, document.importRecordId!);
    if (record == null) throw StateError('导入记录不存在');
    if (record.pages.any((p) => !p.ocrDone)) {
      throw StateError('请先完成本次记录所有页面的 OCR 识别与校对');
    }
    return repo.sourceText(record);
  }

  Future<void> _generateSingle(String taskType) async {
    if (_isGeneratingAll || _generatingTaskTypes.contains(taskType)) {
      return;
    }

    final llmConfig = await _loadLatestLlmConfig();
    if (!mounted) {
      return;
    }

    final document = _document;
    final ocrRecord = _ocrRecord;

    if (!_canGenerate(document, ocrRecord, llmConfig)) {
      return;
    }

    setState(() {
      _generatingTaskTypes.add(taskType);
    });

    try {
      final result = await _aiGenerationOrchestrator.generateSingle(
        documentId: document!.id,
        ocrText: await _generationText(),
        taskType: taskType,
        llmConfig: llmConfig,
        appendResults: true,
      );

      if (!mounted) {
        return;
      }

      _showMessage(result.message);
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('AI 生成失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingTaskTypes.remove(taskType);
        });
      }
    }
  }

  Future<void> _generateAll() async {
    if (_isGeneratingAll || _generatingTaskTypes.isNotEmpty) {
      return;
    }

    final llmConfig = await _loadLatestLlmConfig();
    if (!mounted) {
      return;
    }

    final document = _document;
    final ocrRecord = _ocrRecord;

    if (!_canGenerate(document, ocrRecord, llmConfig)) {
      return;
    }

    setState(() {
      _isGeneratingAll = true;
    });

    try {
      final batchResult = await _aiGenerationOrchestrator.generateAll(
        documentId: document!.id,
        ocrText: await _generationText(),
        llmConfig: llmConfig,
        appendResults: true,
      );

      if (!mounted) {
        return;
      }

      final successCount = batchResult.results
          .where((item) => item.success)
          .length;
      final failureCount = batchResult.results.length - successCount;
      _showMessage('一键生成完成：成功 $successCount，失败 $failureCount');
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('AI 生成失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAll = false;
        });
      }
    }
  }

  Future<void> _refineResult({
    required String taskType,
    required String currentResultText,
  }) async {
    if (_isGeneratingAll || _generatingTaskTypes.contains(taskType)) {
      return;
    }

    final feedback = await _askRefinementFeedback(taskType);
    if (feedback == null || feedback.trim().isEmpty || !mounted) {
      return;
    }

    final llmConfig = await _loadLatestLlmConfig();
    if (!mounted) {
      return;
    }

    final document = _document;
    final ocrRecord = _ocrRecord;
    if (!_canGenerate(document, ocrRecord, llmConfig)) {
      return;
    }

    setState(() {
      _generatingTaskTypes.add(taskType);
    });

    try {
      final result = await _aiGenerationOrchestrator.regenerateWithFeedback(
        documentId: document!.id,
        ocrText: await _generationText(),
        taskType: taskType,
        currentResultText: currentResultText,
        feedback: feedback,
        llmConfig: llmConfig,
        appendResults: true,
      );

      if (!mounted) return;
      _showMessage(result.message);
      await _reloadPageData();
    } catch (error) {
      if (mounted) {
        _showMessage('AI 修改失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _generatingTaskTypes.remove(taskType);
        });
      }
    }
  }

  Future<String?> _askRefinementFeedback(String taskType) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改${AiTaskType.labelOf(taskType)}'),
        contentPadding: const EdgeInsets.all(24),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: '说明要调整的地方，例如补充易错点',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
  }

  bool _canGenerate(
    SourceDocumentRecord? document,
    OcrTextRecord? ocrRecord,
    LlmProviderConfig? llmConfig,
  ) {
    if (document == null) {
      _showMessage('资料信息未加载完成，请稍后再试');
      return false;
    }
    if (ocrRecord == null || ocrRecord.effectiveText.trim().isEmpty) {
      _showMessage('请先完成 OCR，并确保 finalText 或清洗后文本不为空');
      return false;
    }
    if (!ocrRecord.isUsableForAutomation) {
      _showMessage('OCR 质量较低，请先在 OCR 页面框选重试、AI 修复或确认 finalText');
      return false;
    }
    if (llmConfig == null || !llmConfig.isConfigured) {
      _showMessage('请先到“我的”页配置 AI 大模型 API Key');
      return false;
    }
    return true;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _knowledgeCardsText(List<KnowledgeCardRecord> cards) {
    return cards.map((card) => '${card.title}\n${card.content}').join('\n\n');
  }

  String _practiceQuestionsText(List<PracticeQuestionRecord> questions) {
    return questions
        .map(
          (question) =>
              '题目：${question.questionText}\n答案：${question.answerText ?? ''}\n解析：${question.analysisText ?? ''}',
        )
        .join('\n\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI 生成结果'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: FutureBuilder<_AiPageData>(
        future: _pageFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _AiStatePanel(
              icon: Icons.error_outline_rounded,
              title: 'AI 页面加载失败',
              description: '请稍后重试，或返回资料详情重新进入。',
              actionLabel: '重新加载',
              onPressed: _reloadPageData,
            );
          }

          final data = snapshot.data!;
          final canGenerate =
              data.ocrRecord != null &&
              data.ocrRecord!.isUsableForAutomation &&
              data.llmConfig != null &&
              data.llmConfig!.isConfigured;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (_importRecordId != null)
                TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HomePage(
                        initialTab: 1,
                        initialRecordId: _importRecordId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories_outlined),
                  label: const Text('进入本次导入记录'),
                ),
              _GenerationHeader(
                document: data.document,
                llmConfig: data.llmConfig,
                canGenerate: canGenerate,
                isGeneratingAll: _isGeneratingAll,
                onGenerateAll: _generateAll,
              ),
              const SizedBox(height: 14),
              ...AiTaskType.all.map(
                (taskType) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TaskActionCard(
                    taskType: taskType,
                    taskRecord: data.tasksByType[taskType],
                    isRunning: _generatingTaskTypes.contains(taskType),
                    canRun: canGenerate && !_isGeneratingAll,
                    onRun: () => _generateSingle(taskType),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              _ResultSection(
                title: '知识卡片',
                child: data.knowledgeCards.isEmpty
                    ? const _EmptyResultHint(text: '暂无知识卡片结果')
                    : _RefinableResultGroup(
                        isRunning: _generatingTaskTypes.contains(
                          AiTaskType.knowledgeCards,
                        ),
                        onRefine: () => _refineResult(
                          taskType: AiTaskType.knowledgeCards,
                          currentResultText: _knowledgeCardsText(
                            data.knowledgeCards,
                          ),
                        ),
                        child: Column(
                          children: data.knowledgeCards
                              .map(
                                (item) => _SimpleResultCard(
                                  title: item.title,
                                  content: item.content,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              _ResultSection(
                title: '复习提纲',
                child: data.reviewOutline == null
                    ? const _EmptyResultHint(text: '暂无复习提纲结果')
                    : _RefinableResultGroup(
                        isRunning: _generatingTaskTypes.contains(
                          AiTaskType.reviewOutline,
                        ),
                        onRefine: () => _refineResult(
                          taskType: AiTaskType.reviewOutline,
                          currentResultText:
                              '${data.reviewOutline!.title}\n${data.reviewOutline!.outlineText}',
                        ),
                        child: _SimpleResultCard(
                          title: data.reviewOutline!.title,
                          content: data.reviewOutline!.outlineText,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              _ResultSection(
                title: '思维导图文字版',
                child: data.mindmapText == null
                    ? const _EmptyResultHint(text: '暂无思维导图文字结果')
                    : _RefinableResultGroup(
                        isRunning: _generatingTaskTypes.contains(
                          AiTaskType.mindmapText,
                        ),
                        onRefine: () => _refineResult(
                          taskType: AiTaskType.mindmapText,
                          currentResultText: data.mindmapText!.mindmapText,
                        ),
                        child: _SimpleResultCard(
                          title: 'Mindmap',
                          content: data.mindmapText!.mindmapText,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              _ResultSection(
                title: '练习题',
                child: data.practiceQuestions.isEmpty
                    ? const _EmptyResultHint(text: '暂无练习题结果')
                    : _RefinableResultGroup(
                        isRunning: _generatingTaskTypes.contains(
                          AiTaskType.practiceQuestions,
                        ),
                        onRefine: () => _refineResult(
                          taskType: AiTaskType.practiceQuestions,
                          currentResultText: _practiceQuestionsText(
                            data.practiceQuestions,
                          ),
                        ),
                        child: Column(
                          children: data.practiceQuestions
                              .map(
                                (item) => _QuestionResultCard(
                                  questionText: item.questionText,
                                  answerText: item.answerText,
                                  analysisText: item.analysisText,
                                  difficulty: item.difficulty,
                                  questionKind: item.questionKind,
                                  options: item.options,
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GenerationHeader extends StatelessWidget {
  const _GenerationHeader({
    required this.document,
    required this.llmConfig,
    required this.canGenerate,
    required this.isGeneratingAll,
    required this.onGenerateAll,
  });

  final SourceDocumentRecord document;
  final LlmProviderConfig? llmConfig;
  final bool canGenerate;
  final bool isGeneratingAll;
  final VoidCallback onGenerateAll;

  @override
  Widget build(BuildContext context) {
    final modelText = llmConfig == null || !llmConfig!.isConfigured
        ? '未配置 AI 大模型'
        : '${llmConfig!.provider.toUpperCase()} / ${llmConfig!.effectiveModel}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            document.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            canGenerate
                ? 'OCR 文本和 AI 配置已就绪，可进行单项生成或一键生成全部结果。'
                : '请先完成 OCR，并到“我的”页配置 AI 大模型 API Key。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            modelText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canGenerate && !isGeneratingAll ? onGenerateAll : null,
              icon: isGeneratingAll
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: const Text('一键生成全部'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskActionCard extends StatelessWidget {
  const _TaskActionCard({
    required this.taskType,
    required this.taskRecord,
    required this.isRunning,
    required this.canRun,
    required this.onRun,
  });

  final String taskType;
  final AiGenerationTaskRecord? taskRecord;
  final bool isRunning;
  final bool canRun;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final taskLabel = AiTaskType.labelOf(taskType);
    final status = taskRecord?.status ?? AiTaskStatus.pending;
    final statusLabel = _taskStatusLabel(status);
    final statusColor = _taskStatusColor(status);
    final hasFailed = status == AiTaskStatus.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  taskLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (taskRecord?.errorMessage?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              '失败原因：${taskRecord!.errorMessage}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB91C1C),
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: canRun && !isRunning ? onRun : null,
              icon: isRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Icon(
                      hasFailed
                          ? Icons.replay_rounded
                          : Icons.play_arrow_rounded,
                    ),
              label: Text(hasFailed ? '重试' : '生成'),
            ),
          ),
        ],
      ),
    );
  }

  String _taskStatusLabel(String status) {
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

  Color _taskStatusColor(String status) {
    switch (status) {
      case AiTaskStatus.running:
        return AppColors.primary;
      case AiTaskStatus.completed:
        return const Color(0xFF166534);
      case AiTaskStatus.failed:
        return const Color(0xFFB91C1C);
      case AiTaskStatus.pending:
      default:
        return const Color(0xFF9A3412);
    }
  }
}

class _ResultSection extends StatelessWidget {
  const _ResultSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _RefinableResultGroup extends StatelessWidget {
  const _RefinableResultGroup({
    required this.child,
    required this.isRunning,
    required this.onRefine,
  });

  final Widget child;
  final bool isRunning;
  final VoidCallback onRefine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: isRunning ? null : onRefine,
            icon: isRunning
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.edit_note_rounded),
            label: Text(isRunning ? '正在修改' : '修改'),
          ),
        ),
      ],
    );
  }
}

class _SimpleResultCard extends StatelessWidget {
  const _SimpleResultCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            content,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionResultCard extends StatelessWidget {
  const _QuestionResultCard({
    required this.questionText,
    this.answerText,
    this.analysisText,
    this.difficulty,
    this.questionKind,
    this.options = const <String>[],
  });

  final String questionText;
  final String? answerText;
  final String? analysisText;
  final String? difficulty;
  final String? questionKind;
  final List<String> options;

  @override
  Widget build(BuildContext context) {
    final isMultipleChoice =
        questionKind == PracticeQuestionKind.multipleChoice;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionText,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (difficulty?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              '难度：$difficulty',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (options.isNotEmpty) ...[
            const SizedBox(height: 8),
            _QuestionOptionList(options: options),
          ] else if (isMultipleChoice) ...[
            const SizedBox(height: 8),
            Text(
              '选项缺失，请重新生成练习题',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (answerText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            SelectableText(
              '答案：$answerText',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF166534),
                height: 1.45,
              ),
            ),
          ],
          if (analysisText?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            SelectableText(
              '解析：$analysisText',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF475569),
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionOptionList extends StatelessWidget {
  const _QuestionOptionList({required this.options});

  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: options
          .map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(
                option,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _EmptyResultHint extends StatelessWidget {
  const _EmptyResultHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF854D0E),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AiStatePanel extends StatelessWidget {
  const _AiStatePanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onPressed(),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiPageData {
  const _AiPageData({
    required this.document,
    required this.ocrRecord,
    required this.llmConfig,
    required this.tasksByType,
    required this.knowledgeCards,
    required this.reviewOutline,
    required this.mindmapText,
    required this.practiceQuestions,
  });

  final SourceDocumentRecord document;
  final OcrTextRecord? ocrRecord;
  final LlmProviderConfig? llmConfig;
  final Map<String, AiGenerationTaskRecord> tasksByType;
  final List<KnowledgeCardRecord> knowledgeCards;
  final ReviewOutlineRecord? reviewOutline;
  final MindmapTextRecord? mindmapText;
  final List<PracticeQuestionRecord> practiceQuestions;
}
