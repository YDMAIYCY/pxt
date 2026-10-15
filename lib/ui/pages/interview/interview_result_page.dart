import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../database/import_record_repository.dart';
import '../../../database/interview_repository.dart';
import '../../../database/models/import_record.dart';
import '../../../interview/avatar/interview_avatar.dart';
import '../../../interview/interview_models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_app_chrome.dart';
import '../record_results_page.dart';
import '../record_source_page.dart';
import 'interview_prepare_page.dart';

// ========== 面试结果页 ==========
// 所有分数都来自数据库中的真实评分记录，不显示任何设计稿示例分数。

class InterviewResultPage extends StatefulWidget {
  const InterviewResultPage({
    required this.userId,
    required this.sessionId,
    this.repository,
    this.database,
    this.preparationRoute,
    super.key,
  });

  final int userId;
  final int sessionId;
  final InterviewRepository? repository;
  final AppDatabase? database;
  final Route<dynamic>? preparationRoute;

  @override
  State<InterviewResultPage> createState() => _InterviewResultPageState();
}

class _InterviewResultPageState extends State<InterviewResultPage> {
  late Future<_ResultData?> _future;
  bool _opening = false;

  InterviewRepository get _repo =>
      widget.repository ?? InterviewRepository(database: widget.database);

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ResultData?> _load() async {
    final session = await _repo.getSession(widget.userId, widget.sessionId);
    if (session == null) return null;
    final questions = await _repo.questions(widget.userId, widget.sessionId);
    final evaluations = await _repo.evaluations(
      widget.userId,
      widget.sessionId,
    );
    final turns = await _repo.turns(widget.userId, widget.sessionId);
    return _ResultData(
      session: session,
      questions: questions,
      evaluations: evaluations,
      turns: turns,
    );
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _inScope(_ResultData data, ImportRecord record) =>
      record.userId == widget.userId &&
      record.libraryId == data.session.libraryId &&
      (data.session.recordId == null || record.id == data.session.recordId);

  Future<void> _openScoped(String type, String title) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final data = await _future;
      if (data == null || !mounted) return;
      final repository = ImportRecordRepository(database: widget.database);
      final records = await repository.list(
        widget.userId,
        libraryId: data.session.libraryId,
      );
      final choices = <_ReviewChoice>[];
      final weakPoints = data.weakPoints;
      for (final record in records.where((record) => _inScope(data, record))) {
        if ((record.counts[type] ?? 0) == 0) continue;
        final rows = await repository.results(widget.userId, record.id, type);
        if (rows.isEmpty) continue;
        final sourceQuestions = data.questions
            .where(
              (question) =>
                  question.sourceRecordId == record.id &&
                  record.sources.any(
                    (source) =>
                        source.id == question.sourcePageId &&
                        source.userId == widget.userId,
                  ),
            )
            .toList();
        final matchingPoint = weakPoints
            .where(
              (point) => rows.any(
                (row) =>
                    '${row['title'] ?? ''} ${row['content'] ?? row['outline_text'] ?? ''}'
                        .toLowerCase()
                        .contains(point.toLowerCase()),
              ),
            )
            .firstOrNull;
        final selectedRecord = data.session.recordId == record.id;
        if (matchingPoint == null &&
            sourceQuestions.isEmpty &&
            !selectedRecord) {
          continue;
        }
        final query = matchingPoint ?? '';
        final matchedCount = query.isEmpty
            ? rows.length
            : rows
                  .where(
                    (row) => row.values
                        .join(' ')
                        .toLowerCase()
                        .contains(query.toLowerCase()),
                  )
                  .length;
        choices.add(
          _ReviewChoice(
            record: record,
            query: query,
            count: matchedCount,
            reason: matchingPoint != null
                ? '薄弱知识点：$matchingPoint'
                : sourceQuestions.isNotEmpty
                ? '第 ${sourceQuestions.map((q) => q.orderIndex + 1).join('、')} 题的来源资料'
                : '本次选中的资料',
          ),
        );
      }
      if (!mounted) return;
      if (choices.isEmpty) {
        _notice('本次所选知识库内没有关联的$title，来源资料可能已删除、移出本库或尚未生成成果。');
        return;
      }
      choices.sort(
        (a, b) =>
            (b.query.isNotEmpty ? 1 : 0).compareTo(a.query.isNotEmpty ? 1 : 0),
      );
      final choice = await showModalBottomSheet<_ReviewChoice>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    '选择本次知识库内的$title',
                    style: AppTextStyles.h3(sheetContext),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final choice in choices)
                        ListTile(
                          title: Text(choice.record.title),
                          subtitle: Text(
                            '${choice.reason}\n已有 ${choice.count} 项$title',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(sheetContext, choice),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (choice == null || !mounted) return;
      // Re-read after selection: records may have been moved or deleted.
      final record = await repository.get(widget.userId, choice.record.id);
      if (record == null || !_inScope(data, record)) {
        _notice('这份资料已删除或移出本次知识库，无法打开。');
        return;
      }
      final results = await repository.results(
        widget.userId,
        record.id,
        type,
        query: choice.query,
      );
      if (!mounted) return;
      if (results.isEmpty) {
        _notice('关联的$title已删除，请重新选择已有成果。');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordResultsPage(
            record: record,
            type: type,
            title: title,
            query: choice.query,
            database: widget.database,
          ),
        ),
      );
    } catch (error) {
      _notice('暂时无法打开复习内容');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openSource(_ResultData data, int documentId) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final question = data.questions
          .where((q) => q.sourcePageId == documentId)
          .firstOrNull;
      if (question == null) {
        _notice('这条参考来源不在本次面试资料中。');
        return;
      }
      final record = await ImportRecordRepository(
        database: widget.database,
      ).get(widget.userId, question.sourceRecordId);
      if (!mounted) return;
      if (record == null || !_inScope(data, record)) {
        _notice('来源资料已删除或移出本次知识库，无法打开原文。');
        return;
      }
      final source = record.sources
          .where(
            (s) =>
                s.id == documentId &&
                s.userId == widget.userId &&
                s.importRecordId == record.id,
          )
          .firstOrNull;
      if (source == null) {
        _notice('这页原始资料已删除，无法打开；本次保存的参考要点仍可查看。');
        return;
      }
      // RecordSourcePage normally excludes the PDF container. Never silently
      // fall back to another page when the reference is that exact container.
      final sourceRecord =
          record.pages.any((page) => page.id == documentId) ||
              record.pages.isEmpty
          ? record
          : ImportRecord(
              id: record.id,
              userId: record.userId,
              libraryId: record.libraryId,
              title: record.title,
              createdAt: record.createdAt,
              sources: [source],
              counts: record.counts,
            );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordSourcePage(
            record: sourceRecord,
            initialDocumentId: documentId,
            database: widget.database,
          ),
        ),
      );
    } catch (error) {
      _notice('暂时无法打开原文');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _retry() async {
    final route = widget.preparationRoute;
    if (route != null && route.isActive) {
      Navigator.of(
        context,
      ).popUntil((candidate) => identical(candidate, route));
      return;
    }
    final data = await _future;
    if (!mounted || data == null) return;
    final session = data.session;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => InterviewPreparePage(
          userId: widget.userId,
          libraryId: session.libraryId,
          recordId: session.recordId,
          database: widget.database,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('面试结果')),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed: _opening ? null : _retry,
          child: const Text('再来一次'),
        ),
      ),
    ),
    body: FutureBuilder<_ResultData?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _future = _load()),
              child: const Text('读取失败，点击重试'),
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        if (data == null) {
          return const Center(child: Text('面试记录不存在或已删除'));
        }
        return PremiumPageBackground(child: _content(data));
      },
    ),
  );

  Widget _content(_ResultData data) {
    final report = data.report;
    final overall = report['overall_score'] as int?;
    final knowledgeRaw = report['knowledge_score'] as int?;
    final expressionRaw = report['expression_score'] as int?;
    // Older reports stored weighted subscores out of 70 and 30.
    final knowledge = report['score_scale'] == 100
        ? knowledgeRaw
        : knowledgeRaw == null
        ? null
        : (knowledgeRaw * 100 / 70).round();
    final expression = report['score_scale'] == 100
        ? expressionRaw
        : expressionRaw == null
        ? null
        : (expressionRaw * 100 / 30).round();
    final completed =
        report['completed_count'] as int? ??
        data.session.completedQuestionCount;
    final target =
        report['target_count'] as int? ?? data.session.targetQuestionCount;
    final strengths = _stringList(report['strengths']);
    final weaknesses = _stringList(report['weaknesses']);
    final suggestions = _stringList(report['suggestions']);
    final weakPoints = data.weakPoints;
    final cancelled = report['cancelled'] == true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF2F8FF), Colors.white],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Row(
            children: [
              InterviewAvatar(
                size: 64,
                mood: cancelled || overall == null
                    ? AvatarMood.idle
                    : AvatarMood.happy,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cancelled ? '本次面试提前结束' : '本次 AI 面试已完成',
                      style: AppTextStyles.h3(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.session.scopeName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (overall == null)
          _card('暂无有效评分', [const Text('本次面试没有产生可用评价，无法计算总分。请重新开始一轮面试。')])
        else ...[
          _scoreCard(overall, knowledge, expression, completed, target),
          const SizedBox(height: 16),
        ],
        if (strengths.isNotEmpty)
          _listCard(
            '优点',
            strengths,
            Icons.thumb_up_alt_outlined,
            const Color(0xFF10B981),
          ),
        if (weaknesses.isNotEmpty || suggestions.isNotEmpty)
          _card('问题与建议', [
            if (weaknesses.isNotEmpty) ...[
              for (final item in weaknesses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(item, style: AppTextStyles.bodySmall(context)),
                ),
              if (suggestions.isNotEmpty) const Divider(height: 20),
            ],
            for (final item in suggestions)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(item, style: AppTextStyles.body(context)),
              ),
          ]),
        if (weakPoints.isNotEmpty)
          _card('需要加强', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final point in weakPoints.take(8))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(AppRadii.chip),
                      border: Border.all(color: AppColors.primaryLight),
                    ),
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
              ],
            ),
          ]),
        const SizedBox(height: 8),
        PremiumSurface(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('查看逐题分析', style: AppTextStyles.h3(context)),
            children: data.questions
                .map((q) => _questionCard(data, q))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                label: const Text('复习提纲'),
                onPressed: _opening
                    ? null
                    : () => _openScoped('review_outlines', '复习提纲'),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.style_outlined, size: 18),
                label: const Text('知识卡片'),
                onPressed: _opening
                    ? null
                    : () => _openScoped('knowledge_cards', '知识卡片'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _scoreCard(
    int overall,
    int? knowledge,
    int? expression,
    int completed,
    int target,
  ) {
    final level = overall >= 90
        ? '优秀'
        : overall >= 75
        ? '良好'
        : overall >= 60
        ? '合格'
        : '需要加强';
    final hint = switch (level) {
      '优秀' => '表现优秀，继续保持！',
      '良好' => '表现不错，继续保持！',
      '合格' => '已掌握部分内容，继续查漏补缺。',
      _ => '建议结合下方薄弱点重点复习。',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 108,
                height: 108,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: CircularProgressIndicator(
                        value: overall / 100,
                        strokeWidth: 9,
                        backgroundColor: const Color(0xFFE3ECF7),
                        color: AppColors.primary,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$overall',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const Text(
                          '分',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadii.chip),
                      ),
                      child: Text(
                        level,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(hint, style: AppTextStyles.caption(context)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.graphic_eq_rounded,
                  label: '表达与逻辑',
                  value: expression == null ? '—' : '$expression / 30',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.menu_book_rounded,
                  label: '知识掌握',
                  value: knowledge == null ? '—' : '$knowledge / 70',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '完成题数 $completed / $target',
              style: AppTextStyles.caption(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.borderLight),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h3(context)),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _listCard(
    String title,
    List<String> items,
    IconData icon,
    Color color,
  ) => _card(title, [
    for (final item in items)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(item, style: AppTextStyles.body(context))),
          ],
        ),
      ),
  ]);

  Widget _questionCard(_ResultData data, InterviewQuestion question) {
    final evaluation = data.evaluationFor(question.id);
    final dialogue =
        data.turns
            .where(
              (turn) =>
                  turn.questionId == question.id &&
                  (turn.speaker == 'user' || turn.speaker == 'assistant'),
            )
            .toList()
          ..sort((a, b) {
            final round = a.round.compareTo(b.round);
            return round != 0 ? round : a.id.compareTo(b.id);
          });
    final answers = dialogue
        .where((turn) => turn.speaker == 'user' && turn.status == 'final')
        .toList();
    final sourceIds = {question.sourcePageId, ...?evaluation?.evidenceRefs};
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: Text(
            '第 ${question.orderIndex + 1} 题',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            evaluation == null
                ? '暂无评分'
                : '最终评分 ${evaluation.totalScore} 分 · ${answers.length} 轮回答',
            style: TextStyle(
              fontSize: 12,
              color: evaluation == null
                  ? AppColors.textTertiary
                  : AppColors.primary,
            ),
          ),
          children: [
            _labeled('问题', question.questionText),
            if (question.knowledgePoint.isNotEmpty)
              _labeled('知识点', question.knowledgePoint),
            if (question.referencePoints.isNotEmpty)
              _labeled('参考要点', question.referencePoints.join('；')),
            for (final turn in dialogue)
              if (turn.speaker == 'user') ...[
                _labeled(
                  '第 ${turn.round + 1} 轮回答${turn.status == 'final' ? '' : '（未提交）'}',
                  turn.text,
                ),
                if (data.evaluationForTurn(turn.id) case final turnEvaluation?)
                  _labeled('本轮评分', '${turnEvaluation.totalScore} 分'),
              ] else if (turn.isFollowUp)
                _labeled('追问 ${turn.round}', turn.text),
            if (answers.isEmpty) _labeled('我的回答', '本题尚无已提交的回答'),
            if (evaluation != null) ...[
              _labeled(
                '最终评分（结合已提交的多轮回答）',
                '准确性 ${evaluation.accuracyScore}/50 · 完整性 '
                    '${evaluation.completenessScore}/20 · 逻辑 '
                    '${evaluation.logicScore}/15 · 表达 '
                    '${evaluation.expressionScore}/15',
              ),
              if (evaluation.strengths.isNotEmpty)
                _labeled('答对', evaluation.strengths.join('；')),
              if (evaluation.weaknesses.isNotEmpty)
                _labeled('遗漏', evaluation.weaknesses.join('；')),
              if (evaluation.suggestions.isNotEmpty)
                _labeled('建议', evaluation.suggestions.join('；')),
            ],
            _labeled('参考依据', switch (question.sourceKind) {
              'ocr' => '原文 OCR',
              'knowledge_cards' => '由原文生成的知识卡片',
              'review_outlines' => '由原文生成的复习提纲',
              'practice_questions' => '由原文生成的练习题',
              _ => '本次保存的学习资料',
            }),
            for (final sourceId in sourceIds)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _opening
                      ? null
                      : () => _openSource(data, sourceId),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(
                    sourceId == question.sourcePageId ? '查看题目来源原文' : '查看评分参考原文',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _labeled(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.body(context)),
      ],
    ),
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadii.input),
    ),
    child: Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ResultData {
  const _ResultData({
    required this.session,
    required this.questions,
    required this.evaluations,
    required this.turns,
  });

  final InterviewSession session;
  final List<InterviewQuestion> questions;
  final List<InterviewEvaluation> evaluations;
  final List<InterviewTurn> turns;

  Map<String, Object?> get report {
    final raw = session.reportJson;
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.map((key, value) => MapEntry('$key', value))
          : const {};
    } catch (_) {
      return const {};
    }
  }

  /// 每道基础题取最后一次评价；追问轮次只刷新同一题的得分。
  InterviewEvaluation? evaluationFor(int questionId) =>
      (evaluations.where((e) => e.questionId == questionId).toList()
            ..sort((a, b) => a.id.compareTo(b.id)))
          .lastOrNull;

  InterviewEvaluation? evaluationForTurn(int turnId) =>
      evaluations.where((evaluation) => evaluation.turnId == turnId).lastOrNull;

  List<String> get weakPoints => {
    ..._stringList(report['weak_points']),
    for (final question in questions)
      if (evaluationFor(question.id) case final evaluation?)
        if (evaluation.totalScore < 75 || evaluation.weaknesses.isNotEmpty)
          question.knowledgePoint.trim(),
  }.where((point) => point.isNotEmpty).toList();
}

class _ReviewChoice {
  const _ReviewChoice({
    required this.record,
    required this.query,
    required this.count,
    required this.reason,
  });
  final ImportRecord record;
  final String query;
  final int count;
  final String reason;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
