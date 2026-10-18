import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/favorite_repository.dart';
import '../../database/models/ai_result_records.dart';

class PracticeReviewPage extends StatefulWidget {
  const PracticeReviewPage({
    this.initialQuestionId,
    this.recordId,
    this.authRepository,
    this.aiGenerationRepository,
    this.favoriteRepository,
    super.key,
  });

  final int? initialQuestionId;
  final int? recordId;
  final AuthRepository? authRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final FavoriteRepository? favoriteRepository;

  @override
  State<PracticeReviewPage> createState() => _PracticeReviewPageState();
}

class _PracticeReviewPageState extends State<PracticeReviewPage> {
  late final AuthRepository _authRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final FavoriteRepository _favoriteRepository;
  late Future<List<PracticeQuestionWithDocument>> _future;
  final TextEditingController _answerController = TextEditingController();
  Set<String> _favoriteKeys = const <String>{};
  int? _userId;
  int _currentIndex = 0;
  bool _answerRevealed = false;
  bool _isSaving = false;
  bool _isFavoriteSaving = false;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _favoriteRepository = widget.favoriteRepository ?? FavoriteRepository();
    _future = _loadQuestions();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<List<PracticeQuestionWithDocument>> _loadQuestions() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }
    _userId = user.id;

    final questions = widget.recordId != null
        ? await _aiGenerationRepository.fetchPracticeQuestionsByUser(
            userId: user.id,
            recordId: widget.recordId,
            limit: 100000,
          )
        : await _aiGenerationRepository.fetchReviewQueueByUser(
            userId: user.id,
            limit: 300,
          );
    final favoriteKeys = await _favoriteRepository.fetchFavoriteKeys(user.id);
    if (mounted) {
      setState(() => _favoriteKeys = favoriteKeys);
    } else {
      _favoriteKeys = favoriteKeys;
    }

    final initialId = widget.initialQuestionId;
    if (initialId != null) {
      final index = questions.indexWhere(
        (item) => item.question.id == initialId,
      );
      if (index >= 0) {
        _currentIndex = index;
      } else {
        final selected = await _aiGenerationRepository
            .fetchPracticeQuestionByUserAndId(
              userId: user.id,
              questionId: initialId,
            );
        if (selected != null && widget.recordId == null) {
          return [selected, ...questions];
        }
      }
    }
    return questions;
  }

  Future<void> _reload() async {
    _answerController.clear();
    _answerRevealed = false;
    final future = _loadQuestions();
    setState(() {
      _future = future;
    });
    await future;
  }

  void _completeAnswer() {
    if (_answerController.text.trim().isEmpty) {
      _showMessage('请先输入你的答案');
      return;
    }
    setState(() {
      _answerRevealed = true;
    });
  }

  Future<void> _toggleFavorite(PracticeQuestionRecord question) async {
    final userId = _userId;
    if (userId == null || _isFavoriteSaving) {
      return;
    }
    setState(() => _isFavoriteSaving = true);
    try {
      final favorited = await _favoriteRepository.toggleFavorite(
        userId: userId,
        targetType: FavoriteTargetType.practiceQuestion,
        targetId: question.id,
      );
      final key = FavoriteRepository.favoriteKey(
        FavoriteTargetType.practiceQuestion,
        question.id,
      );
      if (!mounted) return;
      setState(() {
        final next = Set<String>.of(_favoriteKeys);
        if (favorited) {
          next.add(key);
        } else {
          next.remove(key);
        }
        _favoriteKeys = next;
      });
      _showMessage(favorited ? '已加入收藏' : '已取消收藏');
    } catch (error) {
      if (mounted) _showMessage('收藏操作失败：$error');
    } finally {
      if (mounted) setState(() => _isFavoriteSaving = false);
    }
  }

  Future<void> _markMastered(PracticeQuestionRecord question) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _aiGenerationRepository.markPracticeQuestionCorrect(
        questionId: question.id,
        userAnswer: _answerController.text,
      );
      if (!mounted) {
        return;
      }
      _showMessage('已掌握，题目已移出待刷列表');
      await _reload();
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _retryQuestion(PracticeQuestionRecord question) async {
    if (_isSaving) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      await _aiGenerationRepository.markPracticeQuestionWrong(
        questionId: question.id,
        userAnswer: _answerController.text,
      );
      if (!mounted) {
        return;
      }
      _showMessage('已保留在待刷列表，可以重新作答');
      setState(() {
        _answerRevealed = false;
        _answerController.clear();
      });
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '练习',
          style: AppTextStyles.title(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        scrolledUnderElevation: 0,
      ),
      body: FutureBuilder<List<PracticeQuestionWithDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const AppLoadingState(label: '正在准备练习题…');
          }
          if (snapshot.hasError) {
            return AppEmptyState(
              icon: Icons.cloud_off_rounded,
              accent: AppColors.error,
              title: '练习题加载失败',
              description: '请稍后重试。',
              actionLabel: '重新加载',
              onAction: _reload,
            );
          }

          final questions =
              snapshot.data ?? const <PracticeQuestionWithDocument>[];
          if (questions.isEmpty) {
            return AppEmptyState(
              icon: Icons.check_circle_rounded,
              accent: AppColors.success,
              title: '暂无待刷练习题',
              description: '生成练习题后，会自动出现在这里。',
              actionLabel: '返回',
              onAction: () async => Navigator.of(context).maybePop(),
            );
          }

          if (_currentIndex >= questions.length) {
            _currentIndex = questions.length - 1;
          }
          final current = questions[_currentIndex];
          final question = current.question;
          final favoriteKey = FavoriteRepository.favoriteKey(
            FavoriteTargetType.practiceQuestion,
            question.id,
          );
          final isFavorited = _favoriteKeys.contains(favoriteKey);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 28),
            children: [
              _ProgressHeader(
                currentIndex: _currentIndex,
                total: questions.length,
                documentTitle: current.documentTitle,
              ),
              const SizedBox(height: 12),

              // ---- 题目 + 作答：one surface ----
              // Two separate cards made the act of answering feel like filling
              // a second form. A hairline inside one card reads as one task.
              AppCard.plain(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _QuestionBody(
                      question: question,
                      isFavorited: isFavorited,
                      isFavoriteSaving: _isFavoriteSaving,
                      onFavorite: () => _toggleFavorite(question),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: AppColors.borderLight),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _answerController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: InputDecoration(
                        hintText: '写下你的答案',
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadii.cardSmall,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.borderLight,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppRadii.cardSmall,
                          ),
                          borderSide: const BorderSide(
                            color: AppColors.borderLight,
                          ),
                        ),
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!_answerRevealed)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: _completeAnswer,
                        icon: const Icon(Icons.done_rounded, size: 18),
                        label: const Text('完成'),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                              ),
                              onPressed: _isSaving
                                  ? null
                                  : () => _retryQuestion(question),
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
                              onPressed: _isSaving
                                  ? null
                                  : () => _markMastered(question),
                              icon: const Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                              ),
                              label: const Text('已掌握'),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              if (_answerRevealed) ...[
                const SizedBox(height: 12),
                _AnswerCard(question: question),
              ],

              if (questions.length > 1) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _currentIndex == 0
                            ? null
                            : () {
                                setState(() {
                                  _currentIndex--;
                                  _answerController.clear();
                                  _answerRevealed = false;
                                });
                              },
                        icon: const Icon(Icons.chevron_left_rounded),
                        label: const Text('上一题'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _currentIndex == questions.length - 1
                            ? null
                            : () {
                                setState(() {
                                  _currentIndex++;
                                  _answerController.clear();
                                  _answerRevealed = false;
                                });
                              },
                        icon: const Icon(Icons.chevron_right_rounded),
                        label: const Text('下一题'),
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

/// Quiz progress: position, a thin bar, and the source document. No card — the
/// header should read as a status line, not as a content block.
class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.currentIndex,
    required this.total,
    required this.documentTitle,
  });

  final int currentIndex;
  final int total;
  final String documentTitle;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : (currentIndex + 1) / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '第 ${currentIndex + 1} / $total 题',
              style: AppTextStyles.labelSmall(context).copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                documentTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.caption(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppProgressBar(value: ratio, height: 5),
      ],
    );
  }
}

/// The question body. It has no card of its own: it lives inside the single
/// task surface together with the answer field.
class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    required this.question,
    required this.isFavorited,
    required this.isFavoriteSaving,
    required this.onFavorite,
  });

  final PracticeQuestionRecord question;
  final bool isFavorited;
  final bool isFavoriteSaving;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (question.difficulty?.isNotEmpty == true)
              AppTag(
                label: question.difficulty!,
                accent: AppColors.accentAmber,
              ),
            const Spacer(),
            IconButton(
              tooltip: isFavorited ? '取消收藏' : '收藏',
              onPressed: isFavoriteSaving ? null : onFavorite,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              icon: Icon(
                isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
                size: 20,
                color: isFavorited
                    ? AppColors.accentAmber
                    : AppColors.textQuiet,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          question.questionText,
          style: AppTextStyles.h2(context).copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.55,
          ),
        ),
        if (question.options.isNotEmpty) ...[
          const SizedBox(height: 14),
          _QuestionOptionList(options: question.options),
        ] else if (question.questionKind ==
            PracticeQuestionKind.multipleChoice) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: AppColors.tintOf(AppColors.accentAmber, 0.10),
              borderRadius: BorderRadius.circular(AppRadii.chipSmall),
            ),
            child: Text(
              '选项缺失，请回到 AI 生成结果页重新生成练习题',
              style: AppTextStyles.caption(
                context,
              ).copyWith(color: AppColors.accentAmber),
            ),
          ),
        ],
        const SizedBox(height: 14),
        _MetricsRow(question: question),
      ],
    );
  }
}

/// Mastery / wrong count / next review as one quiet status line.
///
/// Three filled pills competed with the question for attention. A coloured dot
/// plus neutral text keeps the same meaning at a fraction of the weight.
class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.question});

  final PracticeQuestionRecord question;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 6,
    children: [
      _StatusItem(
        accent: AppColors.accentMint,
        label: '掌握度 ${question.masteryScore}',
      ),
      _StatusItem(
        accent: question.wrongCount > 0
            ? AppColors.accentRose
            : AppColors.border,
        label: '错 ${question.wrongCount} 次',
      ),
      if (question.nextReviewAt != null)
        _StatusItem(
          accent: AppColors.accentSky,
          label: '${_formatTime(question.nextReviewAt!)} 复习',
        ),
    ],
  );
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.accent, required this.label});

  final Color accent;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: AppTextStyles.labelSmall(
          context,
        ).copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _QuestionOptionList extends StatelessWidget {
  const _QuestionOptionList({required this.options});

  final List<String> options;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadii.chipSmall),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: SelectableText(
              option,
              style: AppTextStyles.bodySmall(
                context,
              ).copyWith(color: AppColors.textPrimary, height: 1.45),
            ),
          ),
      ],
    );
  }
}

/// Answer + explanation, revealed after the user commits to an answer. Green
/// because this is the "check yourself" moment, not another input block.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.question});

  final PracticeQuestionRecord question;

  @override
  Widget build(BuildContext context) {
    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: '正确答案', accent: AppColors.success),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: BoxDecoration(
              color: AppColors.tintOf(AppColors.success, 0.07),
              borderRadius: BorderRadius.circular(AppRadii.cardSmall),
              border: Border.all(
                color: AppColors.tintOf(AppColors.success, 0.18),
              ),
            ),
            child: SelectableText(
              question.answerText?.isNotEmpty == true
                  ? question.answerText!
                  : '暂无答案',
              style: AppTextStyles.body(
                context,
              ).copyWith(color: AppColors.textPrimary, height: 1.55),
            ),
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
            question.analysisText?.isNotEmpty == true
                ? question.analysisText!
                : '暂无解析',
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(height: 1.55, color: AppColors.slate),
          ),
        ],
      ),
    );
  }
}

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
