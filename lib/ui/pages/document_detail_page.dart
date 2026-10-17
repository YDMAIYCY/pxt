import 'dart:io';

import 'package:flutter/material.dart';

import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/ocr_text_record.dart';
import '../../database/models/source_document_record.dart';
import '../../database/ocr_text_repository.dart';
import '../../database/source_document_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import 'ai_generation_page.dart';
import 'ocr_result_page.dart';
import 'feishu_source_view.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('资料详情'),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
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
          if (data.document.sourceType == SourceDocumentSourceType.feishuDocx) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(data.document.title, style: Theme.of(context).textTheme.titleLarge),
                SelectableText(data.ocrRecord?.effectiveText ?? ''),
                OutlinedButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(
                    builder: (_) => FeishuSourceView(source: data.document),
                  )),
                  child: const Text('原文 / 知识点 / 同步'),
                ),
              ],
            );
          }
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
                _AiResultSection(data: data, onOpenAi: _openAi),
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
    final isPdfDocument =
        document.sourceType == SourceDocumentSourceType.pdfDocument;
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
              child: isPdfDocument
                  ? Container(
                      color: const Color(0xFFEFF6FF),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.picture_as_pdf_rounded,
                        size: 64,
                        color: AppColors.error,
                      ),
                    )
                  : Image.file(
                      File(document.imagePath),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFFE2E8F0),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          size: 42,
                        ),
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
                    color: AppColors.textPrimary,
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ocrRecord!.isLowQuality && !ocrRecord!.hasFinalText) ...[
                  const _QualityWarning(
                    text: 'OCR 质量较低，建议进入 OCR 页面框选重试、AI 修复或确认 finalText 后再生成。',
                  ),
                  const SizedBox(height: 10),
                ],
                if (ocrRecord!.hasFinalText) ...[
                  const _Tag(text: '已使用 finalText'),
                  const SizedBox(height: 10),
                ],
                SelectableText(
                  ocrRecord!.effectiveText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
    );
  }
}

class _QualityWarning extends StatelessWidget {
  const _QualityWarning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF9A3412),
          fontWeight: FontWeight.w700,
          height: 1.4,
        ),
      ),
    );
  }
}

class _AiResultSection extends StatelessWidget {
  const _AiResultSection({required this.data, required this.onOpenAi});

  final _DocumentDetailData data;
  final VoidCallback onOpenAi;

  /// A summary section must stay scannable: past this many questions the rest
  /// belong in the AI result page, not stacked onto the document page.
  static const _questionPreviewLimit = 6;

  @override
  Widget build(BuildContext context) {
    final hasAnyResult =
        data.cards.isNotEmpty ||
        data.outline != null ||
        data.mindmap != null ||
        data.questions.isNotEmpty;
    if (!hasAnyResult) {
      return const _Section(
        title: 'AI 结果',
        child: _EmptyHint(text: '暂无 AI 结果，请先进入 AI 生成页。'),
      );
    }

    final summary = <String>[
      if (data.cards.isNotEmpty) '卡片 ${data.cards.length} 张',
      if (data.questions.isNotEmpty) '练习 ${data.questions.length} 道',
      if (data.outline != null) '复习提纲',
      if (data.mindmap != null) '思维导图',
    ].join(' · ');

    return _Section(
      title: 'AI 结果',
      subtitle: '已生成 $summary',
      accent: AppColors.accentViolet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (data.cards.isNotEmpty) ...[
            _GroupLabel(
              icon: Icons.style_outlined,
              label: '知识卡片',
              count: data.cards.length,
              accent: AppColors.accentViolet,
            ),
            const SizedBox(height: 8),
            for (final (i, card) in data.cards.indexed)
              _CardResultTile(
                index: i + 1,
                title: card.title,
                body: card.content,
              ),
            const SizedBox(height: 12),
          ],
          if (data.outline != null) ...[
            _GroupLabel(
              icon: Icons.list_alt_rounded,
              label: '复习提纲',
              accent: AppColors.accentSky,
            ),
            const SizedBox(height: 8),
            _LongTextBlock(text: data.outline!.outlineText),
            const SizedBox(height: 12),
          ],
          if (data.mindmap != null) ...[
            _GroupLabel(
              icon: Icons.account_tree_outlined,
              label: '思维导图文字版',
              accent: AppColors.accentMint,
            ),
            const SizedBox(height: 8),
            _LongTextBlock(text: data.mindmap!.mindmapText),
            const SizedBox(height: 12),
          ],
          if (data.questions.isNotEmpty) ...[
            _GroupLabel(
              icon: Icons.quiz_outlined,
              label: '练习题',
              count: data.questions.length,
              accent: AppColors.accentAmber,
            ),
            const SizedBox(height: 2),
            Text(
              '轻点题目展开答案与解析',
              style: AppTextStyles.caption(context),
            ),
            const SizedBox(height: 8),
            // Questions are long and repetitive; a collapsed list of stems with
            // tap-to-reveal answers keeps the page scannable instead of a wall
            // of "练习题 N / 答案 / 解析" plain text.
            for (final (i, question) in data.questions
                .take(_questionPreviewLimit)
                .indexed)
              _QuestionResultTile(index: i + 1, question: question),
            if (data.questions.length > _questionPreviewLimit)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '还有 ${data.questions.length - _questionPreviewLimit} 道题未展示',
                        style: AppTextStyles.caption(context),
                      ),
                    ),
                    TextButton(
                      onPressed: onOpenAi,
                      child: const Text('查看全部'),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Small category line inside the AI section: icon, name, optional count.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.icon,
    required this.label,
    required this.accent,
    this.count,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final int? count;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 15, color: accent),
      const SizedBox(width: 6),
      Text(
        label,
        style: AppTextStyles.label(
          context,
        ).copyWith(color: accent, fontWeight: FontWeight.w700),
      ),
      if (count != null) ...[
        const SizedBox(width: 6),
        Text(
          '$count',
          style: AppTextStyles.labelSmall(
            context,
          ).copyWith(color: AppColors.textTertiary),
        ),
      ],
    ],
  );
}

class _CardResultTile extends StatelessWidget {
  const _CardResultTile({
    required this.index,
    required this.title,
    required this.body,
  });

  final int index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.tintOf(AppColors.accentViolet, 0.05),
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.tintOf(AppColors.accentViolet, 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                index.toString().padLeft(2, '0'),
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: AppColors.tintOf(AppColors.accentViolet, 0.75),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.title(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          SelectableText(
            body,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(height: 1.55, color: AppColors.slate),
          ),
        ],
      ),
    );
  }
}

/// One practice question: stem always visible, answer/analysis on demand.
class _QuestionResultTile extends StatefulWidget {
  const _QuestionResultTile({required this.index, required this.question});

  final int index;
  final PracticeQuestionRecord question;

  @override
  State<_QuestionResultTile> createState() => _QuestionResultTileState();
}

class _QuestionResultTileState extends State<_QuestionResultTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final answer = q.answerText?.trim();
    final analysis = q.analysisText?.trim();
    final hasDetail =
        (answer != null && answer.isNotEmpty) ||
        (analysis != null && analysis.isNotEmpty);
    final difficulty = q.difficulty?.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(
          color: _open
              ? AppColors.tintOf(AppColors.accentAmber, 0.45)
              : AppColors.borderLight,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.cardSmall),
          onTap: hasDetail ? () => setState(() => _open = !_open) : null,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.tintOf(AppColors.accentAmber, 0.16),
                          borderRadius: BorderRadius.circular(AppRadii.chipSmall),
                        ),
                        child: Text(
                          '${widget.index}',
                          style: AppTextStyles.labelSmall(context).copyWith(
                            color: AppColors.accentAmber,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (difficulty != null && difficulty.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        AppTag(
                          label: difficulty,
                          accent: AppColors.accentSky,
                          filled: false,
                        ),
                      ],
                      const Spacer(),
                      if (hasDetail)
                        Icon(
                          _open
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 20,
                          color: AppColors.textTertiary,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    q.questionText,
                    maxLines: _open ? null : 3,
                    overflow: _open ? null : TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(color: AppColors.textPrimary, height: 1.55),
                  ),
                  if (_open) ...[
                    if (answer != null && answer.isNotEmpty)
                      _AnswerBlock(
                        label: '答案',
                        text: answer,
                        accent: AppColors.accentMint,
                      ),
                    if (analysis != null && analysis.isNotEmpty)
                      _AnswerBlock(
                        label: '解析',
                        text: analysis,
                        accent: AppColors.accentViolet,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({
    required this.label,
    required this.text,
    required this.accent,
  });

  final String label;
  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.tintOf(accent, 0.06),
        borderRadius: BorderRadius.circular(AppRadii.chipSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.labelSmall(
              context,
            ).copyWith(color: accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          SelectableText(
            text,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(height: 1.55, color: AppColors.slate),
          ),
        ],
      ),
    ),
  );
}

/// Long-form generated text (outline / mindmap). Collapsed by default so one
/// artifact cannot push everything else below the fold.
class _LongTextBlock extends StatefulWidget {
  const _LongTextBlock({required this.text});

  final String text;

  @override
  State<_LongTextBlock> createState() => _LongTextBlockState();
}

class _LongTextBlockState extends State<_LongTextBlock> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 140;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            widget.text,
            maxLines: _open || !long ? null : 5,
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(height: 1.55, color: AppColors.slate),
          ),
          if (long)
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Text(
                      _open ? '收起' : '展开全部',
                      style: AppTextStyles.labelSmall(
                        context,
                      ).copyWith(color: AppColors.primary),
                    ),
                    Icon(
                      _open
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.accent,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSectionHeader(
            title: title,
            subtitle: subtitle,
            accent: accent ?? AppColors.primary,
          ),
          const SizedBox(height: 12),
          child,
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
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primary,
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
        color: AppColors.textSecondary,
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
