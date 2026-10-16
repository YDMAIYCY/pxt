import 'package:flutter/material.dart';

import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/models/knowledge_graph_records.dart';
import '../../database/ocr_text_repository.dart';
import '../../learning/learning_events.dart';
import '../../learning/learning_task_repository.dart';
import '../theme/app_theme.dart';
import 'library_practice_page.dart';
import 'record_source_page.dart';

class LearningConceptPage extends StatefulWidget {
  const LearningConceptPage({
    required this.conceptId,
    this.database,
    this.learningTaskRepository,
    super.key,
  });

  final int conceptId;
  final AppDatabase? database;
  final LearningTaskRepository? learningTaskRepository;

  @override
  State<LearningConceptPage> createState() => _LearningConceptPageState();
}

class _LearningConceptPageState extends State<LearningConceptPage> {
  late Future<_ConceptData> _future;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    LearningEvents.changed.addListener(_changed);
  }

  @override
  void dispose() {
    LearningEvents.changed.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() => _future = _load());
  }

  Future<_ConceptData> _load() async {
    final user = await AuthRepository(
      database: widget.database,
    ).getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    final db = await (widget.database ?? AppDatabase.instance).database;
    final rows = await db.rawQuery(
      '''SELECT c.*, d.original_title document_title,
      d.import_record_id, d.library_id source_library_id, l.name library_name
      FROM knowledge_concepts c
      LEFT JOIN source_documents d ON d.id=c.document_id AND d.user_id=c.user_id
      LEFT JOIN knowledge_libraries l ON l.id=d.library_id AND l.user_id=c.user_id
      WHERE c.id=? AND c.user_id=?''',
      [widget.conceptId, user.id],
    );
    if (rows.isEmpty) throw StateError('知识点不存在或无权访问');
    final row = rows.single;
    final concept = KnowledgeConceptRecord.fromMap(row);
    final wrong = await db.rawQuery('''SELECT q.id FROM practice_questions q
      JOIN source_documents d ON d.id=q.document_id
      JOIN question_concepts qc ON qc.question_id=q.id
      WHERE d.user_id=? AND qc.concept_id=? AND
        (q.review_status='wrong' OR (q.wrong_count>0 AND q.review_status!='mastered'))
      ORDER BY q.next_review_at, q.id''', [user.id, concept.id]);
    final attempts = await db.rawQuery(
      '''SELECT COUNT(DISTINCT s.id) count
      FROM practice_submissions s JOIN question_concepts qc ON qc.question_id=s.question_id
      WHERE s.user_id=? AND qc.concept_id=?''',
      [user.id, concept.id],
    );
    final source = concept.documentId == null
        ? null
        : await OcrTextRepository(
            database: widget.database,
          ).getByDocumentId(concept.documentId!);
    final plans = await db.query('concept_review_schedules',
        where: 'user_id=? AND concept_id=?', whereArgs: [user.id, concept.id]);
    return _ConceptData(
      concept,
      row,
      source?.effectiveText ?? '',
      wrong.map((q) => q['id'] as int).toList(),
      attempts.single['count'] as int,
      plans.firstOrNull,
    );
  }

  Future<void> _practice(_ConceptData data, {bool wrongOnly = false}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LibraryPracticePage(
          initialConceptId: data.concept.id,
          documentId: data.concept.documentId,
          questionIds: wrongOnly ? data.wrongIds : null,
          database: widget.database,
        ),
      ),
    );
    if (mounted) _changed();
  }

  Future<void> _source(_ConceptData data) async {
    final documentId = data.concept.documentId;
    if (documentId == null) return;
    final record = await ImportRecordRepository(
      database: widget.database,
    ).forDocument(data.concept.userId, documentId);
    if (!mounted || record == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordSourcePage(
          record: record,
          initialDocumentId: documentId,
          database: widget.database,
        ),
      ),
    );
    if (mounted) _changed();
  }

  Future<void> _plan(_ConceptData data) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    setState(() => _saving = true);
    try {
      await (widget.learningTaskRepository ??
              LearningTaskRepository(database: widget.database))
          .addConceptReview(data.concept.userId, data.concept.id, dueAt: date);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入复习计划')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('知识点详情')),
    body: FutureBuilder<_ConceptData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!, concept = data.concept;
        return RefreshIndicator(
          onRefresh: () async {
            _changed();
            await _future;
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(concept.name, style: AppTextStyles.h2(context)),
              const SizedBox(height: 8),
              Text(
                [
                  data.row['library_name'],
                  data.row['document_title'],
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
              ),
              const SizedBox(height: 16),
              Text(
                '掌握 ${concept.masteryScore} / 100 · 薄弱 ${concept.weaknessScore} / 100',
              ),
              Text('实际作答 ${data.attempts} 次 · 待巩固错题 ${data.wrongIds.length} 道'),
              if (data.attempts == 0) const Text('尚无关联作答证据，分数不代表已验证掌握。'),
              const SizedBox(height: 20),
              Text('知识内容', style: AppTextStyles.h3(context)),
              const SizedBox(height: 8),
              SelectableText(
                concept.summary?.isNotEmpty == true
                    ? concept.summary!
                    : '该知识点暂无内容摘要。',
              ),
              if (concept.evidenceText?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text('原文依据', style: AppTextStyles.h3(context)),
                const SizedBox(height: 8),
                SelectableText(concept.evidenceText!),
              ],
              const SizedBox(height: 16),
              if (data.sourceText.isNotEmpty)
                ExpansionTile(
                  title: const Text('来源全文'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(data.sourceText),
                    ),
                  ],
                ),
              OutlinedButton.icon(
                onPressed: concept.documentId == null
                    ? null
                    : () => _source(data),
                icon: const Icon(Icons.source_outlined),
                label: const Text('查看原始资料'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: concept.documentId == null
                    ? null
                    : () => _practice(data),
                icon: const Icon(Icons.edit_note),
                label: const Text('练习这个知识点'),
              ),
              if (data.wrongIds.isNotEmpty)
                OutlinedButton(
                  onPressed: () => _practice(data, wrongOnly: true),
                  child: Text('复习关联错题（${data.wrongIds.length}）'),
                ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _plan(data),
                icon: const Icon(Icons.event_note),
                label: Text(_saving ? '保存中…' : '加入复习计划'),
              ),
              Text(data.plan == null ? '尚未设置复习计划' :
                  '计划复习：${DateTime.parse(data.plan!['due_at'] as String).toLocal().toString().split('.').first}'),
            ],
          ),
        );
      },
    ),
  );
}

class _ConceptData {
  const _ConceptData(
    this.concept,
    this.row,
    this.sourceText,
    this.wrongIds,
    this.attempts,
    this.plan,
  );
  final KnowledgeConceptRecord concept;
  final Map<String, Object?> row;
  final String sourceText;
  final List<int> wrongIds;
  final int attempts;
  final Map<String, Object?>? plan;
}
