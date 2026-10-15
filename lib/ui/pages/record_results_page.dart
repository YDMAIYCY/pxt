import 'package:flutter/material.dart';
import '../../database/app_database.dart';
import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/favorite_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/import_record.dart';
import '../theme/app_theme.dart';
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
      query: _query,
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title),actions:[AskEClawButton(database:widget.database,
      scope:EClawContext(knowledgeBaseId:widget.record.libraryId,importRecordId:widget.record.id))]),
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
              _refresh();
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return KnowledgeEmptyState(
                  title: '读取失败',
                  message: '${snapshot.error}',
                  action: TextButton(
                    onPressed: _refresh,
                    child: const Text('重试'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return KnowledgeEmptyState(
                  title: _query.isEmpty ? '尚无${widget.title}' : '没有匹配的内容',
                  message: '回到记录详情，可继续生成或更换搜索关键词。',
                );
              }
              return Column(
                children: snapshot.data!.map((row) {
                  final id = row['id'] as int,
                      documentId = row['document_id'] as int;
                  final title =
                      row['title'] as String? ??
                      row['question_text'] as String? ??
                      '思维导图';
                  final content =
                      row['content'] as String? ??
                      row['outline_text'] as String? ??
                      row['mindmap_text'] as String? ??
                      '';
                  final isQuestion =
                      widget.type == 'practice_questions' ||
                      widget.type == 'wrong_questions';
                  return Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: AppTextStyles.h3(context),
                                ),
                              ),
                              IconButton(
                                tooltip: '收藏',
                                onPressed: () => _favorite(id),
                                icon: Icon(
                                  _favoriteKeys.contains('$_favoriteType:$id')
                                      ? Icons.star_rounded
                                      : Icons.star_border_rounded,
                                  color: AppColors.accentOrange,
                                ),
                              ),
                            ],
                          ),
                          if (widget.type == 'mindmap_texts')
                            RecordMindmapView(
                              text: content,
                              onSource: () => _source(documentId),
                            )
                          else if (!isQuestion)
                            SelectableText(
                              content,
                              style: AppTextStyles.body(context),
                            ),
                          if (isQuestion) ...[
                            if (widget.type == 'wrong_questions')
                              Text(
                                '错误 ${row['wrong_count']} 次 · 当前待复习',
                                style: AppTextStyles.bodySmall(context),
                              ),
                            FilledButton.icon(
                              onPressed: () => _question(row),
                              icon: const Icon(Icons.edit_note),
                              label: Text(
                                widget.type == 'wrong_questions'
                                    ? '查看解析与复习'
                                    : '开始答题',
                              ),
                            ),
                          ],
                          TextButton.icon(
                            onPressed: () => _source(documentId),
                            icon: const Icon(Icons.source_outlined, size: 17),
                            label: const Text('查看对应原始资料'),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}
