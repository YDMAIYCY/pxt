import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/favorite_repository.dart';
import '../../database/models/ai_result_records.dart';

class PracticeReviewPage extends StatefulWidget {
  const PracticeReviewPage({
    this.initialQuestionId,
    this.authRepository,
    this.aiGenerationRepository,
    this.favoriteRepository,
    super.key,
  });

  final int? initialQuestionId;
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

    final questions = await _aiGenerationRepository.fetchReviewQueueByUser(
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
        if (selected != null) {
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
        title: const Text('刷练习题'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
      ),
      body: FutureBuilder<List<PracticeQuestionWithDocument>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatePanel(
              icon: Icons.error_outline_rounded,
              title: '练习题加载失败',
              description: '请稍后重试。',
              actionLabel: '重新加载',
              onPressed: _reload,
            );
          }

          final questions =
              snapshot.data ?? const <PracticeQuestionWithDocument>[];
          if (questions.isEmpty) {
            return _StatePanel(
              icon: Icons.check_circle_rounded,
              title: '暂无待刷练习题',
              description: '生成练习题后，会自动出现在这里。',
              actionLabel: '返回',
              onPressed: () async => Navigator.of(context).maybePop(),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _ProgressHeader(
                currentIndex: _currentIndex,
                total: questions.length,
                documentTitle: current.documentTitle,
              ),
              const SizedBox(height: 14),
              _QuestionCard(
                question: question,
                isFavorited: isFavorited,
                isFavoriteSaving: _isFavoriteSaving,
                onFavorite: () => _toggleFavorite(question),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _answerController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: '我的答案',
                  hintText: '写下你的作答或简单判断',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (!_answerRevealed)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _completeAnswer,
                        icon: const Icon(Icons.done_rounded),
                        label: const Text('完成'),
                      ),
                    )
                  else ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _retryQuestion(question),
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('重新刷题'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () => _markMastered(question),
                        icon: const Icon(Icons.check_circle_rounded),
                        label: const Text('已掌握'),
                      ),
                    ),
                  ],
                ],
              ),
              if (_answerRevealed) ...[
                const SizedBox(height: 14),
                _AnswerCard(question: question),
              ],
              const SizedBox(height: 10),
              if (questions.length > 1)
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
          );
        },
      ),
    );
  }
}

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
            '第 ${currentIndex + 1} / $total 题',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            documentTitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  question.questionText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: isFavorited ? '取消收藏' : '收藏',
                onPressed: isFavoriteSaving ? null : onFavorite,
                icon: Icon(
                  isFavorited ? Icons.star_rounded : Icons.star_border_rounded,
                  color: isFavorited
                      ? const Color(0xFFF59E0B)
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (question.difficulty?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            _ChipText(text: '难度：${question.difficulty}'),
          ],
          if (question.options.isNotEmpty) ...[
            const SizedBox(height: 12),
            _QuestionOptionList(options: question.options),
          ] else if (question.questionKind ==
              PracticeQuestionKind.multipleChoice) ...[
            const SizedBox(height: 12),
            Text(
              '选项缺失，请回到 AI 生成结果页重新生成练习题',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFFB45309),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipText(text: '掌握度 ${question.masteryScore}'),
              _ChipText(text: '错 ${question.wrongCount} 次'),
              if (question.nextReviewAt != null)
                _ChipText(text: '下次 ${_formatTime(question.nextReviewAt!)}'),
            ],
          ),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textPrimary,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.question});

  final PracticeQuestionRecord question;

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
            '正确答案',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            question.answerText?.isNotEmpty == true
                ? question.answerText!
                : '暂无答案',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textPrimary,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '解析',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            question.analysisText?.isNotEmpty == true
                ? question.analysisText!
                : '暂无解析',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChipText extends StatelessWidget {
  const _ChipText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
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
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
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

String _formatTime(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.month}-${two(time.day)} ${two(time.hour)}:${two(time.minute)}';
}
