import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../generator/wrong_question_training_service.dart';
import 'practice_review_page.dart';

class WrongQuestionPage extends StatefulWidget {
  const WrongQuestionPage({
    required this.item,
    this.aiGenerationRepository,
    this.authRepository,
    this.llmConfigRepository,
    this.trainingService,
    super.key,
  });

  final PracticeQuestionWithDocument item;
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _InfoCard(
                title: widget.item.documentTitle,
                children: [
                  _TextBlock(label: '题目', text: question.questionText),
                  if (question.lastUserAnswer?.isNotEmpty == true)
                    _TextBlock(label: '上次作答', text: question.lastUserAnswer!),
                  _TextBlock(
                    label: '正确答案',
                    text: question.answerText ?? '暂无答案',
                  ),
                  _TextBlock(
                    label: '解析',
                    text: question.analysisText ?? '暂无解析',
                  ),
                  _TextBlock(label: '错题次数', text: '${question.wrongCount} 次'),
                  _TextBlock(
                    label: '掌握度',
                    text: '${question.masteryScore} / 100',
                  ),
                ],
              ),
              const SizedBox(height: 14),
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
                      onPressed: _isSaving ? null : _retryQuestion,
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('重新刷题'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isSaving || hasPendingSimilar
                          ? null
                          : _markMastered,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('我已掌握'),
                    ),
                  ),
                ],
              ),
              if (hasPendingSimilar) ...[
                const SizedBox(height: 8),
                Text(
                  '完成全部相似题后，原错题会自动进入已掌握。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFFB45309),
                    fontWeight: FontWeight.w700,
                  ),
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
      return const _InfoCard(
        title: '强化训练',
        children: [LinearProgressIndicator()],
      );
    }

    final training = data.training;
    if (training == null) {
      return _InfoCard(
        title: '强化训练',
        children: [
          Text(
            '还没有错因标签和相似题。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: isGenerating ? null : onGenerate,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(isGenerating ? '生成中...' : '生成强化训练'),
          ),
        ],
      );
    }

    return _InfoCard(
      title: '强化训练',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: training.causeTags
              .map((tag) => _TagChip(text: tag))
              .toList(growable: false),
        ),
        const SizedBox(height: 12),
        Text(
          '相似题 ${data.masteredSimilarCount} / ${data.similarQuestions.length}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        ...data.similarQuestions.map(
          (question) => _SimilarQuestionTile(
            question: question,
            onTap: () => onOpenQuestion(question.id),
          ),
        ),
      ],
    );
  }
}

class _SimilarQuestionTile extends StatelessWidget {
  const _SimilarQuestionTile({required this.question, required this.onTap});

  final PracticeQuestionRecord question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(question.questionText, maxLines: 5, softWrap: true),
      subtitle: Text(
        '掌握度 ${question.masteryScore} / 错 ${question.wrongCount} 次',
      ),
      trailing: Icon(
        question.isMastered
            ? Icons.check_circle_rounded
            : Icons.chevron_right_rounded,
        color: question.isMastered
            ? const Color(0xFF16A34A)
            : AppColors.textSecondary,
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      backgroundColor: const Color(0xFFFFF7ED),
      side: const BorderSide(color: Color(0xFFFED7AA)),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
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
