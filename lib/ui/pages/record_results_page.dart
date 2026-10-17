import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/favorite_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/import_record.dart';
import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import '../widgets/knowledge_components.dart';
import '../widgets/record_mindmap_view.dart';
import 'record_source_page.dart';
import 'practice_review_page.dart';
import 'wrong_question_page.dart';
import '../../agent/eclaw_context.dart';
import '../widgets/ask_eclaw_button.dart';

class RecordResultsPage extends StatefulWidget {
  const RecordResultsPage({
    required this.record,
    required this.type,
    required this.title,
    this.query = '',
    this.database,
    super.key,
  });
  final ImportRecord record;
  final String type, title, query;
  final AppDatabase? database;
  @override
  State<RecordResultsPage> createState() => _RecordResultsPageState();
}

class _RecordResultsPageState extends State<RecordResultsPage> {
  late String _query = widget.query;
  late Future<List<Map<String, Object?>>> _future;
  Set<String> _favoriteKeys = {};
  ImportRecordRepository get _repo =>
      ImportRecordRepository(database: widget.database);
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, Object?>>> _load() async {
    _favoriteKeys = await FavoriteRepository(
      database: widget.database,
    ).fetchFavoriteKeys(widget.record.userId);
    return _repo.results(
      widget.record.userId,
      widget.record.id,
      widget.type,
      query: widget.type == 'mindmap_texts' ? '' : _query,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _source(int documentId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordSourcePage(
          record: widget.record,
          initialDocumentId: documentId,
          database: widget.database,
        ),
      ),
    );
  }

  String get _favoriteType => switch (widget.type) {
    'knowledge_cards' => FavoriteTargetType.knowledgeCard,
    'review_outlines' => FavoriteTargetType.reviewOutline,
    'mindmap_texts' => FavoriteTargetType.mindmapText,
    'wrong_questions' => FavoriteTargetType.wrongQuestion,
    _ => FavoriteTargetType.practiceQuestion,
  };
  Future<void> _favorite(int id) async {
    await FavoriteRepository(database: widget.database).toggleFavorite(
      userId: widget.record.userId,
      targetType: _favoriteType,
      targetId: id,
    );
    if (mounted) await _refresh();
  }

  Future<void> _question(Map<String, Object?> row) async {
    final ai = AiGenerationRepository(database: widget.database);
    final auth = AuthRepository(database: widget.database);
    final question = PracticeQuestionRecord.fromMap(row);
    if (widget.type == 'wrong_questions') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WrongQuestionPage(
            item: PracticeQuestionWithDocument(
              question: question,
              documentTitle: row['document_title'] as String? ?? '',
            ),
            aiGenerationRepository: ai,
            authRepository: auth,
            recordId: widget.record.id,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PracticeReviewPage(
            initialQuestionId: question.id,
            recordId: widget.record.id,
            authRepository: auth,
            aiGenerationRepository: ai,
            favoriteRepository: FavoriteRepository(database: widget.database),
          ),
        ),
      );
    }
    if (mounted) await _refresh();
  }

  bool get _isQuestionType =>
      widget.type == 'practice_questions' || widget.type == 'wrong_questions';

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        AskEClawButton(
          database: widget.database,
          scope: EClawContext(
            knowledgeBaseId: widget.record.libraryId,
            importRecordId: widget.record.id,
          ),
        ),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text(widget.record.title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 12),
          KnowledgeSearchField(
            hint: '搜索本次记录的${widget.title}…',
            onChanged: (v) {
              _query = v;
              if (widget.type == 'mindmap_texts') {
                setState(() {});
              } else {
                _refresh();
              }
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return AppEmptyState(
                  icon: Icons.cloud_off_rounded,
                  accent: AppColors.error,
                  title: '读取失败',
                  description: '${snapshot.error}',
                  actionLabel: '重试',
                  onAction: _refresh,
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return AppEmptyState(
                  icon: Icons.inbox_rounded,
                  title: _query.isEmpty ? '尚无${widget.title}' : '没有匹配的内容',
                  description: '回到记录详情，可继续生成或更换搜索关键词。',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // One primary action for the whole set. Previously every
                  // question card carried its own full-width filled button,
                  // which turned a list into a wall of primary colour.
                  if (_isQuestionType) ...[
                    _StartPracticeBar(
                      count: rows.length,
                      label: widget.type == 'wrong_questions'
                          ? '开始复习错题'
                          : '开始练习',
                      onStart: () => _question(rows.first),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_isQuestionType)
                    AppCard.outlined(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (final (i, row) in rows.indexed) ...[
                            if (i > 0)
                              const Divider(
                                height: 1,
                                indent: 54,
                                color: AppColors.borderLight,
                              ),
                            _QuestionRow(
                              index: i + 1,
                              title:
                                  row['question_text'] as String? ??
                                  row['title'] as String? ??
                                  '题目',
                              meta: widget.type == 'wrong_questions'
                                  ? '错误 ${row['wrong_count'] ?? 0} 次 · 待复习'
                                  : null,
                              favorited: _favoriteKeys.contains(
                                '$_favoriteType:${row['id']}',
                              ),
                              onTap: () => _question(row),
                              onFavorite: () => _favorite(row['id'] as int),
                              onSource: () =>
                                  _source(row['document_id'] as int),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    for (final row in rows)
                      _ResultCard(
                        title:
                            row['title'] as String? ??
                            row['question_text'] as String? ??
                            '思维导图',
                        content:
                            row['content'] as String? ??
                            row['outline_text'] as String? ??
                            row['mindmap_text'] as String? ??
                            '',
                        mindmap: widget.type == 'mindmap_texts',
                        mindmapQuery: _query,
                        favorited: _favoriteKeys.contains(
                          '$_favoriteType:${row['id']}',
                        ),
                        onFavorite: () => _favorite(row['id'] as int),
                        onSource: () => _source(row['document_id'] as int),
                      ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// The single primary action for a question set: count on the left, start on
/// the right. Reads as one call to action instead of N identical buttons.
class _StartPracticeBar extends StatelessWidget {
  const _StartPracticeBar({
    required this.count,
    required this.label,
    required this.onStart,
  });

  final int count;
  final String label;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.tintOf(AppColors.primary, 0.10),
            AppColors.tintOf(AppColors.accentSky, 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.tintOf(AppColors.primary, 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '共 $count 题',
                  style: AppTextStyles.title(context),
                ),
                const SizedBox(height: 2),
                Text(
                  '按掌握度排序，从最该复习的开始',
                  style: AppTextStyles.caption(context),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: onStart,
            child: Text(label),
          ),
        ],
      ),
    );
  }
}

/// A compact question row inside a grouped list: index, stem, overflow menu.
class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.index,
    required this.title,
    required this.favorited,
    required this.onTap,
    required this.onFavorite,
    required this.onSource,
    this.meta,
  });

  final int index;
  final String title;
  final String? meta;
  final bool favorited;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tintOf(AppColors.primary, 0.10),
                borderRadius: BorderRadius.circular(AppRadii.chipSmall),
              ),
              child: Text(
                '$index',
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: AppColors.primary,
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
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall(
                      context,
                    ).copyWith(color: AppColors.textPrimary, height: 1.5),
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta!,
                      style: AppTextStyles.caption(
                        context,
                      ).copyWith(color: AppColors.accentRose),
                    ),
                  ],
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              icon: Icon(
                favorited ? Icons.star_rounded : Icons.more_horiz_rounded,
                size: 20,
                color: favorited
                    ? AppColors.accentAmber
                    : AppColors.textTertiary,
              ),
              onSelected: (value) {
                if (value == 'favorite') onFavorite();
                if (value == 'source') onSource();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(favorited ? '取消收藏' : '收藏'),
                ),
                const PopupMenuItem(value: 'source', child: Text('查看原始资料')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// A full-content result (knowledge card / outline / mindmap): content first,
/// actions on a quiet footer row.
class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.title,
    required this.content,
    required this.mindmap,
    this.mindmapQuery = '',
    required this.favorited,
    required this.onFavorite,
    required this.onSource,
  });

  final String title;
  final String content;
  final bool mindmap;
  final String mindmapQuery;
  final bool favorited;
  final VoidCallback onFavorite;
  final VoidCallback onSource;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard.plain(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.h3(context)),
            const SizedBox(height: 8),
            if (mindmap)
              RecordMindmapView(text: content, onSource: onSource, query: mindmapQuery)
            else
              SelectableText(
                content,
                style: AppTextStyles.body(
                  context,
                ).copyWith(height: 1.6, color: AppColors.slate),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                _FooterAction(
                  icon: favorited ? Icons.star_rounded : Icons.star_border_rounded,
                  label: favorited ? '已收藏' : '收藏',
                  accent: favorited
                      ? AppColors.accentAmber
                      : AppColors.textSecondary,
                  onTap: onFavorite,
                ),
                _FooterAction(
                  icon: Icons.source_outlined,
                  label: '原始资料',
                  accent: AppColors.textSecondary,
                  onTap: onSource,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppRadii.chipSmall),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: accent),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppTextStyles.label(
              context,
            ).copyWith(color: accent, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
