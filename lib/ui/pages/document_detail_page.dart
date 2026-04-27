import 'dart:io';

import 'package:flutter/material.dart';

import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/ocr_text_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import 'ai_generation_page.dart';
import 'ocr_result_page.dart';

class DocumentDetailPage extends StatefulWidget {
  const DocumentDetailPage({
    required this.documentId,
    this.authRepository,
    this.sourceDocumentRepository,
    this.ocrTextRepository,
    this.aiGenerationRepository,
    super.key,
  });

  final int documentId;
  final AuthRepository? authRepository;
  final SourceDocumentRepository? sourceDocumentRepository;
  final OcrTextRepository? ocrTextRepository;
  final AiGenerationRepository? aiGenerationRepository;

  @override
  State<DocumentDetailPage> createState() => _DocumentDetailPageState();
}

class _DocumentDetailPageState extends State<DocumentDetailPage> {
  late final AuthRepository _authRepository;
  late final SourceDocumentRepository _sourceDocumentRepository;
  late final OcrTextRepository _ocrTextRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late Future<_DocumentDetailData> _future;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _sourceDocumentRepository =
        widget.sourceDocumentRepository ?? SourceDocumentRepository();
    _ocrTextRepository = widget.ocrTextRepository ?? OcrTextRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _future = _loadData();
  }

  Future<_DocumentDetailData> _loadData() async {
    await _authRepository.ensureInitialized();
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      throw StateError('登录状态已失效');
    }

    final document = await _sourceDocumentRepository.getSourceDocumentById(
      userId: user.id,
      documentId: widget.documentId,
    );
    if (document == null) {
      throw StateError('资料不存在或无权访问');
    }

    final ocrRecord = await _ocrTextRepository.getByDocumentId(
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

    return _DocumentDetailData(
      document: document,
      ocrRecord: ocrRecord,
      cards: cards,
      outline: outline,
      mindmap: mindmap,
      questions: questions,
    );
  }

  Future<void> _refresh() async {
    final future = _loadData();
    setState(() {
      _future = future;
    });
    await future;
  }

  Future<void> _openOcr() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OcrResultPage(documentId: widget.documentId),
      ),
    );
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openAi() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiGenerationPage(documentId: widget.documentId),
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
        title: const Text('资料详情'),
        backgroundColor: Colors.transparent,
        foregroundColor: const Color(0xFF0B1324),
      ),
      body: FutureBuilder<_DocumentDetailData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StatePanel(
              icon: Icons.error_outline_rounded,
              title: '资料读取失败',
              description: '请稍后重试。',
              onPressed: _refresh,
            );
          }

          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _ImageSection(document: data.document),
                const SizedBox(height: 14),
                _ActionSection(
                  document: data.document,
                  onOpenOcr: _openOcr,
                  onOpenAi: _openAi,
                ),
                const SizedBox(height: 14),
                _OcrSection(ocrRecord: data.ocrRecord),
                const SizedBox(height: 14),
                _AiResultSection(data: data),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ImageSection extends StatelessWidget {
  const _ImageSection({required this.document});

  final SourceDocumentRecord document;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Image.file(
                File(document.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: const Color(0xFFE2E8F0),
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined, size: 42),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: const Color(0xFF0B1324),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(text: document.sourceTypeLabel),
                    _Tag(text: 'OCR ${document.ocrStatusLabel}'),
                    _Tag(text: document.aiDone ? 'AI 已生成' : 'AI 待生成'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({
    required this.document,
    required this.onOpenOcr,
    required this.onOpenAi,
  });

  final SourceDocumentRecord document;
  final VoidCallback onOpenOcr;
  final VoidCallback onOpenAi;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '处理入口',
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onOpenOcr,
              icon: const Icon(Icons.text_snippet_rounded),
              label: Text(document.ocrDone ? '查看 / 重试 OCR' : '开始 OCR'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: document.ocrDone ? onOpenAi : null,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('查看 / 生成 AI 结果'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrSection extends StatelessWidget {
  const _OcrSection({required this.ocrRecord});

  final OcrTextRecord? ocrRecord;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'OCR 文本',
      child: ocrRecord == null
          ? const _EmptyHint(text: '暂无 OCR 文本，请先执行 OCR。')
          : SelectableText(
              ocrRecord!.cleanText.trim().isNotEmpty
                  ? ocrRecord!.cleanText
                  : ocrRecord!.rawText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF0B1324),
                height: 1.5,
              ),
            ),
    );
  }
}

class _AiResultSection extends StatelessWidget {
  const _AiResultSection({required this.data});

  final _DocumentDetailData data;

  @override
  Widget build(BuildContext context) {
    final hasAnyResult =
        data.cards.isNotEmpty ||
        data.outline != null ||
        data.mindmap != null ||
        data.questions.isNotEmpty;

    return _Section(
      title: 'AI 结果',
      child: hasAnyResult
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.cards.isNotEmpty)
                  _ResultBlock(
                    title: '知识卡片',
                    text: data.cards
                        .map((item) => '${item.title}\n${item.content}')
                        .join('\n\n'),
                  ),
                if (data.outline != null)
                  _ResultBlock(title: '复习提纲', text: data.outline!.outlineText),
                if (data.mindmap != null)
                  _ResultBlock(
                    title: '思维导图文字版',
                    text: data.mindmap!.mindmapText,
                  ),
                if (data.questions.isNotEmpty)
                  _ResultBlock(
                    title: '复习题',
                    text: data.questions
                        .map(
                          (item) =>
                              '${item.questionText}\n答案：${item.answerText ?? ''}\n解析：${item.analysisText ?? ''}',
                        )
                        .join('\n\n'),
                  ),
              ],
            )
          : const _EmptyHint(text: '暂无 AI 结果，请先进入 AI 生成页。'),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0B1324),
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFE0F2FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF0C4A6E),
          fontWeight: FontWeight.w700,
          fontSize: 12,
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
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: const Color(0xFF64748B),
        fontWeight: FontWeight.w600,
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

class _DocumentDetailData {
  const _DocumentDetailData({
    required this.document,
    required this.ocrRecord,
    required this.cards,
    required this.outline,
    required this.mindmap,
    required this.questions,
  });

  final SourceDocumentRecord document;
  final OcrTextRecord? ocrRecord;
  final List<KnowledgeCardRecord> cards;
  final ReviewOutlineRecord? outline;
  final MindmapTextRecord? mindmap;
  final List<PracticeQuestionRecord> questions;
}
