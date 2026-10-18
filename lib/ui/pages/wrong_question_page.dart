import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../generator/wrong_question_training_service.dart';
import 'practice_review_page.dart';

class WrongQuestionPage extends StatefulWidget {
  const WrongQuestionPage({
    required this.item,
    this.recordId,
    this.aiGenerationRepository,
    this.authRepository,
    this.llmConfigRepository,
    this.trainingService,
    super.key,
  });

  final PracticeQuestionWithDocument item;
  final int? recordId;
  final AiGenerationRepository? aiGenerationRepository;
  final AuthRepository? authRepository;
  final LlmConfigRepository? llmConfigRepository;
  final WrongQuestionTrainingService? trainingService;

  @override
  State<WrongQuestionPage> createState() => _WrongQuestionPageState();
}

class _WrongQuestionPageState extends State<WrongQuestionPage> {
  late final AiGenerationRepository _aiGenerationRepository;
  late final AuthRepository _authRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final WrongQuestionTrainingService _trainingService;
  late Future<_TrainingData> _trainingFuture;
  bool _isSaving = false;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _authRepository = widget.authRepository ?? AuthRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _trainingService =
        widget.trainingService ??
        WrongQuestionTrainingService(
          aiGenerationRepository: _aiGenerationRepository,
        );
    _trainingFuture = _loadTrainingData();
  }

  Future<_TrainingData> _loadTrainingData() async {
    final questionId = widget.item.question.id;
    final training = await _aiGenerationRepository.fetchWrongQuestionTraining(
      questionId,
    );
    final similarQuestions = await _aiGenerationRepository
        .fetchSimilarQuestions(questionId);
    return _TrainingData(
      training: training,
      similarQuestions: similarQuestions,
    );
  }

  Future<void> _reloadTrainingData() async {
    final future = _loadTrainingData();
    setState(() {
      _trainingFuture = future;
    });
    await future;
  }

  Future<void> _markMastered() async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final mastered = await _aiGenerationRepository
          .markPracticeQuestionMastered(widget.item.question.id);
      if (!mounted) {
        return;
      }
      if (mastered) {
        Navigator.of(context).pop(true);
      } else {
        _showMessage('请先完成相似题强化训练');
        await _reloadTrainingData();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _retryQuestion() async {
    await _runAndPop(() {
      return _aiGenerationRepository.resetPracticeQuestionForReview(
        widget.item.question.id,
      );
    });
  }

  Future<void> _generateTraining() async {
    if (_isGenerating) {
      return;
    }
    setState(() {
      _isGenerating = true;
    });
    try {
      await _authRepository.ensureInitialized();
      final user = await _authRepository.getCurrentUserProfile();
      final config = user == null
          ? null
          : await _llmConfigRepository.getByUserId(user.id);
      if (config == null || !config.isConfigured) {
        throw StateError('请先到“我的”页面配置 AI 大模型，再生成强化训练');
      }
      await _trainingService.generateForQuestion(
        question: widget.item.question,
        llmConfig: config,
      );
      if (!mounted) {
        return;
      }
      _showMessage('强化训练已生成');
      await _reloadTrainingData();
    } catch (error) {
      if (mounted) {
        _showMessage(_trainingErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  String _trainingErrorMessage(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '').trim();
    if (message.isEmpty) {
      return '强化训练生成失败，请检查 AI 配置后重试';
    }
    return message;
  }

  Future<void> _openSimilarQuestion(int questionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PracticeReviewPage(
          initialQuestionId: questionId,
          recordId: widget.recordId,
          authRepository: _authRepository,
          aiGenerationRepository: _aiGenerationRepository,
        ),
      ),
    );
    if (mounted) {
      await _reloadTrainingData();
    }
  }

  Future<void> _runAndPop(Future<void> Function() action) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await action();
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.item.question;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('处理错题'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: FutureBuilder<_TrainingData>(
        future: _trainingFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? const _TrainingData();
          final hasPendingSimilar = data.hasPendingSimilarQuestions;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // ---- 题目 ----
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        AppTag(
                          label: '错 ${question.wrongCount} 次',
                          accent: AppColors.accentRose,
                          icon: Icons.error_outline_rounded,
                        ),
                        const SizedBox(width: 8),
                        _MetricPill(
                          text: '掌握度 ${question.masteryScore} / 100',
                          accent: AppColors.accentMint,
                        ),
                        const Spacer(),
                        if (question.difficulty?.isNotEmpty == true)
                          AppTag(
                            label: question.difficulty!,
                            accent: AppColors.accentSky,
                            filled: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.item.documentTitle,
                      style: AppTextStyles.caption(context),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      question.questionText,
                      style: AppTextStyles.h2(context).copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- 作答对照 ----
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppSectionHeader(
                      title: '作答对照',
                      accent: AppColors.accentRose,
                    ),
                    const SizedBox(height: 12),
                    if (question.lastUserAnswer?.isNotEmpty == true) ...[
                      _CompareBlock(
                        label: '上次作答',
                        text: question.lastUserAnswer!,
                        accent: AppColors.accentRose,
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 10),
                    ],
                    _CompareBlock(
                      label: '正确答案',
                      text: question.answerText ?? '暂无答案',
                      accent: AppColors.success,
                      icon: Icons.check_circle_outline_rounded,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '解析',
                      style: AppTextStyles.label(
                        context,
                      ).copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      question.analysisText ?? '暂无解析',
                      style: AppTextStyles.bodySmall(
                        context,
                      ).copyWith(height: 1.55, color: AppColors.slate),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ---- 强化训练 ----
              _TrainingCard(
                data: data,
                isLoading: snapshot.connectionState == ConnectionState.waiting,
                isGenerating: _isGenerating,
                onGenerate: _generateTraining,
                onOpenQuestion: _openSimilarQuestion,
              ),
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: _isSaving ? null : _retryQuestion,
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: const Text('重新刷题'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                      onPressed: _isSaving || hasPendingSimilar
                          ? null
                          : _markMastered,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('我已掌握'),
                    ),
                  ),
                ],
              ),
              if (hasPendingSimilar) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.lock_clock_rounded,
                      size: 14,
                      color: AppColors.accentAmber,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '完成全部相似题后，原错题会自动进入已掌握。',
                        style: AppTextStyles.caption(
                          context,
                        ).copyWith(color: AppColors.accentAmber),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({
    required this.data,
    required this.isLoading,
    required this.isGenerating,
    required this.onGenerate,
    required this.onOpenQuestion,
  });

  final _TrainingData data;
  final bool isLoading;
  final bool isGenerating;
  final Future<void> Function() onGenerate;
  final ValueChanged<int> onOpenQuestion;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return AppCard.plain(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            AppSectionHeader(
              title: '强化训练',
              accent: AppColors.accentViolet,
            ),
            SizedBox(height: 14),
            AppSkeleton(height: 16),
            SizedBox(height: 8),
            AppSkeleton(height: 16, width: 200),
          ],
        ),
      );
    }

    final training = data.training;
    if (training == null) {
      return AppCard.plain(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppSectionHeader(
              title: '强化训练',
              accent: AppColors.accentViolet,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.tintOf(AppColors.accentViolet, 0.12),
                    borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                  ),
                  child: const Icon(
                    Icons.psychology_alt_outlined,
                    size: 18,
                    color: AppColors.accentViolet,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '生成后会给出错因分析，并补充几道同类型题。',
                    style: AppTextStyles.bodySmall(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: isGenerating ? null : onGenerate,
              icon: isGenerating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(isGenerating ? '生成中...' : '生成强化训练'),
            ),
          ],
        ),
      );
    }

    final total = data.similarQuestions.length;
    final mastered = data.masteredSimilarCount;
    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(
            title: '强化训练',
            accent: AppColors.accentViolet,
          ),
          if (training.causeTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: training.causeTags
                  .map(
                    (tag) => AppTag(
                      label: tag,
                      accent: AppColors.accentAmber,
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '相似题',
                style: AppTextStyles.label(
                  context,
                ).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                '$mastered / $total',
                style: AppTextStyles.label(context).copyWith(
                  color: mastered == total && total > 0
                      ? AppColors.success
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '这次没有生成相似题，可以直接判断是否已掌握。',
                style: AppTextStyles.caption(context),
              ),
            )
          else ...[
            AppProgressBar(
              value: total == 0 ? 0 : mastered / total,
              accent: AppColors.accentViolet,
              height: 5,
            ),
            const SizedBox(height: 6),
            for (final (i, question) in data.similarQuestions.indexed) ...[
              if (i > 0)
                const Divider(height: 1, color: AppColors.borderLight),
              _SimilarQuestionTile(
                index: i + 1,
                question: question,
                onTap: () => onOpenQuestion(question.id),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SimilarQuestionTile extends StatelessWidget {
  const _SimilarQuestionTile({
    required this.index,
    required this.question,
    required this.onTap,
  });

  final int index;
  final PracticeQuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: question.isMastered
                    ? AppColors.tintOf(AppColors.success, 0.14)
                    : AppColors.tintOf(AppColors.accentViolet, 0.12),
                borderRadius: BorderRadius.circular(AppRadii.chipSmall),
              ),
              child: Text(
                '$index',
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: question.isMastered
                      ? AppColors.success
                      : AppColors.accentViolet,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question.questionText,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(color: AppColors.textPrimary, height: 1.5),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    question.isMastered
                        ? '已掌握'
                        : '掌握度 ${question.masteryScore} · 错 ${question.wrongCount} 次',
                    style: AppTextStyles.caption(context).copyWith(
                      color: question.isMastered
                          ? AppColors.success
                          : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              question.isMastered
                  ? Icons.check_circle_rounded
                  : Icons.chevron_right_rounded,
              size: 20,
              color: question.isMastered
                  ? AppColors.success
                  : AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}

/// A labelled comparison block: the user's answer in rose, the correct answer
/// in green, so the gap between them is visible at a glance.
class _CompareBlock extends StatelessWidget {
  const _CompareBlock({
    required this.label,
    required this.text,
    required this.accent,
    required this.icon,
  });

  final String label;
  final String text;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
    decoration: BoxDecoration(
      color: AppColors.tintOf(accent, 0.06),
      borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      border: Border.all(color: AppColors.tintOf(accent, 0.18)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: accent),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppTextStyles.labelSmall(
                context,
              ).copyWith(color: accent, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SelectableText(
          text,
          style: AppTextStyles.bodySmall(
            context,
          ).copyWith(color: AppColors.textPrimary, height: 1.5),
        ),
      ],
    ),
  );
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.text, required this.accent});

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.tintOf(accent, 0.12),
      borderRadius: BorderRadius.circular(AppRadii.chip),
    ),
    child: Text(
      text,
      style: AppTextStyles.labelSmall(context).copyWith(
        color: accent,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _TrainingData {
  const _TrainingData({
    this.training,
    this.similarQuestions = const <PracticeQuestionRecord>[],
  });

  final WrongQuestionTrainingRecord? training;
  final List<PracticeQuestionRecord> similarQuestions;

  int get masteredSimilarCount =>
      similarQuestions.where((item) => item.isMastered).length;

  bool get hasPendingSimilarQuestions =>
      similarQuestions.isNotEmpty &&
      masteredSimilarCount < similarQuestions.length;
}
