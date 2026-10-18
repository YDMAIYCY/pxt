import 'dart:convert';
import 'package:flutter/material.dart';

import '../../database/auth_repository.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/learning_repository.dart';
import '../../database/models/learning_resource_record.dart';
import '../theme/app_theme.dart';
import 'ai_interview_page.dart';
import 'practice_review_page.dart';
import 'wrong_question_page.dart';

class LearningErrorsPage extends StatefulWidget {
  const LearningErrorsPage({this.documentId, super.key});
  final int? documentId;
  @override
  State<LearningErrorsPage> createState() => _LearningErrorsPageState();
}

class _LearningErrorsPageState extends State<LearningErrorsPage> {
  final _repository = LearningRepository();
  late Future<List<LearningErrorRecord>> _future = _load();
  int? _userId;
  bool _busy = false;
  Future<List<LearningErrorRecord>> _load() async {
    final user = await AuthRepository().getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    _userId = user.id;
    return _repository.errors(user.id, documentId: widget.documentId);
  }

  Future<void> _retry(
    LearningErrorRecord error, {
    bool variations = false,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final questionId = await _repository.prepareErrorRetry(
        _userId!,
        error.id,
      );
      if (!mounted) return;
      if (variations) {
        final question = await AiGenerationRepository()
            .fetchPracticeQuestionByUserAndId(
              userId: _userId!,
              questionId: questionId,
            );
        if (question != null && mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WrongQuestionPage(item: question),
            ),
          );
        }
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PracticeReviewPage(
              initialQuestionId: questionId,
              documentId: error.documentId,
            ),
          ),
        );
      }
      if (mounted) setState(() => _future = _load());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('学习错误追踪')),
    body: FutureBuilder<List<LearningErrorRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PracticeReviewPage(
                      documentId: widget.documentId,
                      wrongOnly: true,
                    ),
                  ),
                );
                if (mounted) setState(() => _future = _load());
              },
              child: const Text('重刷已有错题'),
            ),
            if (snapshot.data!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('暂时没有学习错误。面试遗漏、概念误解和练习错误会记录在这里。'),
              ),
            ...snapshot.data!.map(
              (e) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.origin == 'practice'
                            ? '练习错误'
                            : e.origin == 'feynman'
                            ? '费曼讲解遗漏'
                            : '面试理解缺口',
                        style: AppTextStyles.caption(context),
                      ),
                      const SizedBox(height: 8),
                      Text(e.prompt, style: AppTextStyles.h3(context)),
                      Text('我的回答：${e.answer}'),
                      const SizedBox(height: 8),
                      Text(_feedbackText(e.correction)),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : () => _retry(e),
                            child: const Text('重新作答'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _retry(e, variations: true),
                            child: const Text('错因分析与变式训练'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => AiInterviewPage(
                                          documentId: e.documentId,
                                          conceptId: e.conceptId,
                                          initialErrorId: e.id,
                                        ),
                                      ),
                                    );
                                    if (mounted) {
                                      setState(() => _future = _load());
                                    }
                                  },
                            child: const Text('针对性面试'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

String _feedbackText(String feedback) {
  try {
    final data = jsonDecode(feedback) as Map;
    return [
      data['correction'],
      ...(data['missing_points'] as List? ?? []),
      ...(data['misconceptions'] as List? ?? []),
    ].where((v) => v != null).join('\n');
  } catch (_) {
    return feedback;
  }
}
