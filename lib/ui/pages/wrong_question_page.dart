import 'package:flutter/material.dart';

import '../../database/ai_generation_repository.dart';
import '../../database/models/ai_result_records.dart';

class WrongQuestionPage extends StatefulWidget {
  const WrongQuestionPage({
    required this.item,
    this.aiGenerationRepository,
    super.key,
  });

  final PracticeQuestionWithDocument item;
  final AiGenerationRepository? aiGenerationRepository;

  @override
  State<WrongQuestionPage> createState() => _WrongQuestionPageState();
}

class _WrongQuestionPageState extends State<WrongQuestionPage> {
  late final AiGenerationRepository _aiGenerationRepository;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
  }

  Future<void> _markMastered() async {
    await _runAction(() {
      return _aiGenerationRepository.markPracticeQuestionMastered(
        widget.item.question.id,
      );
    });
  }

  Future<void> _retryQuestion() async {
    await _runAction(() {
      return _aiGenerationRepository.resetPracticeQuestionForReview(
        widget.item.question.id,
      );
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
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

  @override
  Widget build(BuildContext context) {
    final question = widget.item.question;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('处理错题'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0B1324),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _InfoCard(
            title: widget.item.documentTitle,
            children: [
              _TextBlock(label: '题目', text: question.questionText),
              if (question.lastUserAnswer?.isNotEmpty == true)
                _TextBlock(label: '上次作答', text: question.lastUserAnswer!),
              _TextBlock(label: '正确答案', text: question.answerText ?? '暂无答案'),
              _TextBlock(label: '解析', text: question.analysisText ?? '暂无解析'),
              _TextBlock(label: '错题次数', text: '${question.wrongCount} 次'),
            ],
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
                  onPressed: _isSaving ? null : _markMastered,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('我已掌握'),
                ),
              ),
            ],
          ),
        ],
      ),
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
              color: const Color(0xFF0B1324),
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
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF0B1324),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
