import 'dart:convert';
import 'package:flutter/material.dart';
import '../../agent/eclaw_context.dart';
import '../widgets/ask_eclaw_button.dart';
import '../../database/app_database.dart';
import '../../database/auth_repository.dart';
import '../../database/import_record_repository.dart';
import '../../database/knowledge_library_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/import_record.dart';
import '../../database/models/knowledge_library_record.dart';
import '../../database/practice_session_repository.dart';
import '../../generator/library_practice_service.dart';
import '../../generator/wrong_question_training_service.dart';
import '../../database/ai_generation_repository.dart';
import '../../learning/learning_events.dart';
import '../theme/app_theme.dart';
import '../widgets/app_kit.dart';
import 'document_detail_page.dart';
import 'ocr_result_page.dart';
import 'source_version_page.dart';

class LibraryPracticePage extends StatefulWidget {
  const LibraryPracticePage({
    this.libraryId,
    this.recordId,
    this.initialConceptId,
    this.initialQuestionId,
    this.documentId,
    this.questionIds,
    this.database,
    this.embedded = false,
    this.wrongOnly = false,
    super.key,
  });
  final int? libraryId;
  final int? recordId;
  final int? initialConceptId;
  final int? initialQuestionId;
  final int? documentId;
  final List<int>? questionIds;
  final AppDatabase? database;
  final bool embedded;
  final bool wrongOnly;
  @override
  State<LibraryPracticePage> createState() => _LibraryPracticePageState();
}

class _LibraryPracticePageState extends State<LibraryPracticePage> {
  late Future<_PracticeData> _future;
  int? _libraryId;
  int? _recordId;
  int? _conceptId;
  late bool _wrongOnly;
  bool _dueOnly = false;
  bool _busy = false;
  int _count = 5;
  String _difficulty = '基础理解';
  bool get _scopeLocked =>
      widget.recordId != null ||
      widget.documentId != null ||
      widget.initialConceptId != null ||
      widget.initialQuestionId != null ||
      widget.questionIds != null;
  List<int>? get _questionIds =>
      widget.questionIds ??
      (widget.initialQuestionId == null ? null : [widget.initialQuestionId!]);
  @override
  void initState() {
    super.initState();
    _libraryId = widget.libraryId;
    _recordId = widget.recordId;
    _conceptId = widget.initialConceptId;
    _wrongOnly = widget.wrongOnly;
    _future = _load();
    LearningEvents.changed.addListener(_learningChanged);
  }

  @override
  void dispose() {
    LearningEvents.changed.removeListener(_learningChanged);
    super.dispose();
  }

  void _learningChanged() {
    if (mounted) _refresh();
  }

  Future<_PracticeData> _load() async {
    if (widget.initialQuestionId != null && widget.questionIds != null &&
        !widget.questionIds!.contains(widget.initialQuestionId)) {
      throw StateError('起始题目不在指定题目列表中');
    }
    final user = await AuthRepository(
      database: widget.database,
    ).getCurrentUserProfile();
    if (user == null) throw StateError('请先登录');
    final libraries = await KnowledgeLibraryRepository(
      database: widget.database,
    ).fetchLibraries(user.id);
    final db = await (widget.database ?? AppDatabase.instance).database;
    if (_scopeLocked) {
      final ids = _questionIds;
      final documents = await db.rawQuery(
        '''SELECT DISTINCT d.id, d.library_id, d.import_record_id
        FROM source_documents d WHERE d.user_id = ?
        ${widget.documentId == null ? '' : 'AND d.id = ?'}
        ${widget.recordId == null ? '' : 'AND d.import_record_id = ?'}
        ${widget.initialConceptId == null ? '' : 'AND EXISTS (SELECT 1 FROM knowledge_concepts c WHERE c.id = ? AND c.user_id = d.user_id AND c.document_id = d.id)'}
        ${ids == null
            ? ''
            : ids.isEmpty
            ? 'AND 0'
            : 'AND EXISTS (SELECT 1 FROM practice_questions q WHERE q.document_id = d.id AND q.id IN (${List.filled(ids.length, '?').join(',')}))'}''',
        [
          user.id,
          ?widget.documentId,
          ?widget.recordId,
          ?widget.initialConceptId,
          if (ids != null) ...ids,
        ],
      );
      if (documents.isEmpty) throw StateError('所选练习来源不存在或无权访问');
      final libraryIds = documents.map((d) => d['library_id']).toSet();
      if (widget.libraryId != null &&
          libraryIds.any((id) => id != widget.libraryId)) {
        throw StateError('所选练习不在指定知识库');
      }
      _libraryId =
          widget.libraryId ??
          (libraryIds.length == 1 ? libraryIds.single as int? : null);
    } else {
      _libraryId ??= libraries.firstOrNull?.id;
      if (_libraryId == null) throw StateError('请先创建知识库');
    }
    final records = await ImportRecordRepository(
      database: widget.database,
    ).list(user.id, libraryId: _libraryId);
    final scope = PracticeScope(
      userId: user.id,
      libraryId: _libraryId,
      recordId: _recordId,
      conceptId: _conceptId,
      documentId: widget.documentId,
      wrongOnly: _wrongOnly,
    );
    final concepts = await db.rawQuery(
      '''SELECT DISTINCT c.id, c.name
      FROM knowledge_concepts c JOIN source_documents d ON d.id=c.document_id
      WHERE c.user_id = ? AND d.user_id=c.user_id
        ${_libraryId == null ? '' : 'AND d.library_id = ?'}
        ${_recordId == null ? '' : 'AND d.import_record_id = ?'}
        ${widget.documentId == null ? '' : 'AND d.id = ?'}
      ORDER BY c.name''',
      [user.id, ?_libraryId, ?_recordId, ?widget.documentId],
    );
    final questions = await PracticeSessionRepository(database: widget.database)
        .questions(
          scope,
          dueOnly: _dueOnly,
          questionIds: _questionIds,
          limit: _questionIds?.length ?? 500,
        );
    if (_questionIds != null) {
      if (questions.length != _questionIds!.toSet().length) {
        throw StateError('部分指定题目已删除或不在当前范围');
      }
      final order = <int>{
        ?widget.initialQuestionId,
        ..._questionIds!,
      }.toList();
      questions.sort(
        (a, b) => order
            .indexOf(a.question.id)
            .compareTo(order.indexOf(b.question.id)),
      );
    }
    return _PracticeData(scope, libraries, records, concepts, questions);
  }

  void _refresh() {
    setState(() => _future = _load());
  }

  Future<void> _generate(_PracticeData data) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final config = await LlmConfigRepository(
        database: widget.database,
      ).getByUserId(data.scope.userId);
      if (config?.isConfigured != true) throw StateError('请先在“我的”配置 AI 模型');
      final scope = PracticeScope(
        userId: data.scope.userId,
        libraryId: _libraryId,
        recordId: _recordId,
        conceptId: _conceptId,
        documentId: widget.documentId,
      );
      final ids = await LibraryPracticeService(
        database: widget.database,
      ).generate(scope, config!, count: _count, difficulty: _difficulty);
      final questions = await PracticeSessionRepository(
        database: widget.database,
      ).questions(scope, questionIds: ids);
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScopedPracticeRunner(
              scope: scope,
              questions: questions,
              database: widget.database,
            ),
          ),
        );
      }
      if (mounted) _refresh();
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
  Widget build(BuildContext context) {
    final body = FutureBuilder<_PracticeData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AppErrorState(
            icon: Icons.error_outline_rounded,
            title: '无法加载练习范围',
            description: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingState(label: '正在准备练习…');
        }
        final data = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Text('围绕自己的知识练习', style: AppTextStyles.h1(context)),
            const SizedBox(height: 6),
            Text(
              '选择范围 → 作答 → 回看来源 → 变式 → 间隔复习。',
              style: AppTextStyles.bodySmall(context),
            ),
            const SizedBox(height: 18),

            // ---- 练习范围 -------------------------------------------------
            AppCard.plain(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(
                    title: '练习范围',
                    subtitle: '不选就练整库',
                    accent: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _libraryId ?? -1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '知识库'),
                    items: [
                      if (_libraryId == null)
                        const DropdownMenuItem(
                          value: -1,
                          child: Text('所选题目的知识库'),
                        ),
                      ...data.libraries.map(
                        (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                      ),
                    ],
                    onChanged: _scopeLocked || _busy
                        ? null
                        : (id) {
                            _libraryId = id;
                            _recordId = null;
                            _conceptId = null;
                            _refresh();
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('record-$_libraryId'),
                    initialValue: _recordId ?? -1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '导入记录'),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('本库全部记录'),
                      ),
                      ...data.records.map(
                        (r) => DropdownMenuItem(value: r.id, child: Text(r.title)),
                      ),
                    ],
                    onChanged: _scopeLocked || _busy
                        ? null
                        : (id) {
                            _recordId = id == -1 ? null : id;
                            _conceptId = null;
                            _refresh();
                          },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey('concept-$_libraryId-$_recordId'),
                    initialValue: _conceptId ?? -1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '知识点'),
                    items: [
                      const DropdownMenuItem(
                        value: -1,
                        child: Text('全部知识点'),
                      ),
                      ...data.concepts.map(
                        (c) => DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['name'] as String),
                        ),
                      ),
                    ],
                    onChanged: _scopeLocked || _busy
                        ? null
                        : (id) {
                            _conceptId = id == -1 ? null : id;
                            _refresh();
                          },
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('只练错题和薄弱题'),
                    value: _wrongOnly,
                    onChanged: _questionIds != null || _busy
                        ? null
                        : (v) {
                            _wrongOnly = v;
                            _refresh();
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('只看已到复习时间'),
                    value: _dueOnly,
                    onChanged: _questionIds != null || _busy
                        ? null
                        : (v) {
                            _dueOnly = v;
                            _refresh();
                          },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- 就绪状态 + 主操作 ----------------------------------------
            // The count and the primary action belong together: "N 道题" is the
            // answer to "what am I about to start", so it is not a bare line.
            AppCard.tinted(
              accent: AppColors.primary,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.playlist_add_check_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前范围：${data.questions.length} 道题',
                          style: AppTextStyles.title(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _busy || data.questions.isEmpty
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ScopedPracticeRunner(
                                  scope: data.scope,
                                  questions: data.questions,
                                  database: widget.database,
                                ),
                              ),
                            );
                            if (mounted) _refresh();
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('开始练习'),
                  ),
                  if (data.questions.isEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '这个范围里还没有题，可以先在下面生成一套专项题。',
                      style: AppTextStyles.caption(context),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ---- 生成新的专项题 -------------------------------------------
            AppCard.outlined(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppSectionHeader(
                    title: '生成新的专项题',
                    subtitle: '让 AI 按当前范围出一套新题',
                    accent: AppColors.accentViolet,
                  ),
                  const SizedBox(height: 16),
                  Text('题量', style: AppTextStyles.label(context)),
                  const SizedBox(height: 8),
                  AppSegmented<int>(
                    value: _count,
                    enabled: !_busy,
                    onChanged: (n) => setState(() => _count = n),
                    options: const [
                      AppSegmentedOption(5, '5 道'),
                      AppSegmentedOption(10, '10 道'),
                      AppSegmentedOption(20, '20 道'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('难度', style: AppTextStyles.label(context)),
                  const SizedBox(height: 8),
                  AppSegmented<String>(
                    variant: AppSegmentedVariant.pill,
                    value: _difficulty,
                    enabled: !_busy,
                    onChanged: (s) => setState(() => _difficulty = s),
                    options: const [
                      AppSegmentedOption('基础理解', '基础理解'),
                      AppSegmentedOption('综合应用', '综合应用'),
                      AppSegmentedOption('深入思考', '深入思考'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_busy) ...[
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                  ],
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _generate(data),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('基于所选范围组卷'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    return widget.embedded
        ? body
        : Scaffold(
            appBar: AppBar(title: const Text('知识库练习')),
            body: body,
          );
  }
}

class _PracticeData {
  _PracticeData(
    this.scope,
    this.libraries,
    this.records,
    this.concepts,
    this.questions,
  );
  final PracticeScope scope;
  final List<KnowledgeLibraryRecord> libraries;
  final List<ImportRecord> records;
  final List<Map<String, Object?>> concepts;
  final List<PracticeQuestionWithDocument> questions;
}

bool? evaluateObjectiveAnswer(PracticeQuestionRecord question, String input) {
  String normalize(String s) =>
      s.trim().toUpperCase().replaceAll(RegExp(r'^(参考答案|答案)\s*[:：]\s*'), '');
  if (question.questionKind == 'multiple_choice') {
    final expected = RegExp(
      r'^[A-Z](?:$|[.、:\s])',
    ).firstMatch(normalize(question.answerText ?? ''))?.group(0)?.trim()[0];
    final answer = RegExp(
      r'^[A-Z](?:$|[.、:\s])',
    ).firstMatch(normalize(input))?.group(0)?.trim()[0];
    return expected == null || answer == null ? null : expected == answer;
  }
  if (question.questionKind == 'true_false') {
    bool? value(String s) => switch (normalize(s)) {
      '对' || '正确' || 'TRUE' || '是' => true,
      '错' || '错误' || 'FALSE' || '否' => false,
      _ => null,
    };
    final expected = value(question.answerText ?? '');
    final answer = value(input);
    return expected == null || answer == null ? null : expected == answer;
  }
  return null;
}

class ScopedPracticeRunner extends StatefulWidget {
  const ScopedPracticeRunner({
    required this.scope,
    required this.questions,
    this.database,
    super.key,
  });
  final PracticeScope scope;
  final List<PracticeQuestionWithDocument> questions;
  final AppDatabase? database;
  @override
  State<ScopedPracticeRunner> createState() => _ScopedPracticeRunnerState();
}

class _ScopedPracticeRunnerState extends State<ScopedPracticeRunner> {
  final _answer = TextEditingController();
  int _index = 0;
  bool _busy = false;
  bool _revealed = false;
  late String _requestId;
  PracticeSubmission? _submission;
  MasteryEvidence? _evidence;
  PracticeSessionRepository get _repo =>
      PracticeSessionRepository(database: widget.database);
  PracticeQuestionRecord get _question => widget.questions[_index].question;
  @override
  void initState() {
    super.initState();
    _newAttempt();
  }

  void _newAttempt() {
    _requestId = 'practice-${DateTime.now().microsecondsSinceEpoch}-$_index';
    _submission = null;
    _evidence = null;
    _revealed = false;
    _answer.clear();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _submit() async {
    if (_answer.text.trim().isEmpty) throw StateError('请先作答');
    var correct = evaluateObjectiveAnswer(_question, _answer.text);
    if (correct == null) {
      setState(() => _revealed = true);
      correct = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('核对参考答案与关键点'),
          content: SingleChildScrollView(
            child: Text(
              '${_question.answerText ?? ''}\n\n${_question.analysisText ?? ''}'
              '\n\n开放题请依据关键点判断；有争议时可以保存后纠正。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('有遗漏 / 答错'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('关键点正确'),
            ),
          ],
        ),
      );
    }
    if (correct == null) return;
    final result = await _repo.submit(
      scope: widget.scope,
      questionId: _question.id,
      requestId: _requestId,
      answer: _answer.text,
      correct: correct,
    );
    final evidence = await _repo.evidence(widget.scope.userId, _question.id);
    if (mounted) {
      setState(() {
        _submission = result;
        _evidence = evidence;
        _revealed = true;
      });
    }
  }

  Future<void> _regrade() async {
    final existing = _submission;
    if (existing == null) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('纠正本次判定'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: '纠正原因'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('保存纠正'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    if (reason == null) return;
    final result = await _repo.regrade(
      widget.scope.userId,
      existing.id,
      expectedRevision: existing.revision,
      correct: !existing.correct,
      reason: reason,
    );
    final evidence = await _repo.evidence(widget.scope.userId, _question.id);
    if (mounted) {
      setState(() {
        _submission = result;
        _evidence = evidence;
      });
    }
  }

  Future<void> _variations() async {
    final config = await LlmConfigRepository(
      database: widget.database,
    ).getByUserId(widget.scope.userId);
    if (config?.isConfigured != true) throw StateError('请先配置 AI 模型');
    final db = await (widget.database ?? AppDatabase.instance).database;
    final current = (await db.query(
      'practice_questions',
      where: 'id = ?',
      whereArgs: [_question.id],
    )).single;
    await WrongQuestionTrainingService(
      aiGenerationRepository: AiGenerationRepository(database: widget.database),
    ).generateForQuestion(
      question: PracticeQuestionRecord.fromMap(current),
      llmConfig: config,
    );
    final all = await _repo.questions(
      PracticeScope(
        userId: widget.scope.userId,
        libraryId: widget.scope.libraryId,
        recordId: widget.scope.recordId,
      ),
    );
    final related = all
        .where((q) => q.question.parentQuestionId == _question.id)
        .toList();
    if (mounted && related.isNotEmpty) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScopedPracticeRunner(
            scope: PracticeScope(
              userId: widget.scope.userId,
              libraryId: widget.scope.libraryId,
              recordId: widget.scope.recordId,
            ),
            questions: related,
            database: widget.database,
          ),
        ),
      );
    }
  }

  Future<void> _history() async {
    final rows = await _repo.history(widget.scope.userId, _question.id);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('学习历史 · ${rows.length} 条记录', style: AppTextStyles.h3(context)),
            ...rows.map(
              (r) => ListTile(
                title: Text(
                  '${r['legacy'] == 1 ? '旧版学习反馈' : r['correct'] == 1 ? '答对' : '答错'} · ${r['created_at']}',
                ),
                subtitle: Text('${r['answer']}\n${r['legacy'] == 1 ? r['feedback'] : '修订 ${r['revision']}'}'),
                onTap: () {
                  final q = r['question_snapshot'] == null ? null
                    : jsonDecode(r['question_snapshot'] as String) as Map;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('作答当时的题目与依据'),
                      content: SingleChildScrollView(
                        child: Text(
                          q == null ? '旧版保留了答案和反馈，没有当时的题目与来源快照。\n${r['feedback']}'
                          : '${q['question_text']}\n\n参考答案：${q['answer_text']}\n\n${q['analysis_text']}',
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('当前范围没有题目')),
      );
    }
    final q = _question;
    return Scaffold(
      appBar: AppBar(
        title: Text('练习 ${_index + 1}/${widget.questions.length}'),
        actions:[AskEClawButton(database:widget.database,scope:EClawContext(
          knowledgeBaseId:widget.scope.libraryId,importRecordId:widget.scope.recordId,
          documentId:q.documentId))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.questions[_index].documentTitle,
            style: AppTextStyles.caption(context),
          ),
          const SizedBox(height: 12),
          Text(q.questionText, style: AppTextStyles.h2(context)),
          ...q.options.asMap().entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                onPressed: _busy || _submission != null
                    ? null
                    : () {
                        _answer.text = String.fromCharCode(65 + e.key);
                      },
                child: Text(e.value),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _answer,
            minLines: 2,
            maxLines: 6,
            enabled: !_busy && _submission == null,
            decoration: const InputDecoration(labelText: '我的答案'),
          ),
          const SizedBox(height: 12),
          if (_busy) const LinearProgressIndicator(),
          if (_submission == null)
            FilledButton(
              onPressed: _busy ? null : () => _run(_submit),
              child: const Text('提交并核对'),
            ),
          if (_revealed) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_submission != null)
                      Text(
                        _submission!.correct ? '本次答对' : '本次答错',
                        style: AppTextStyles.h3(context),
                      ),
                    Text('参考答案：${q.answerText ?? ''}'),
                    Text('解析：${q.analysisText ?? ''}'),
                    if (q.expectedKeywords.isNotEmpty)
                      Text('关键点：${q.expectedKeywords.join('、')}'),
                    if (_evidence != null)
                      Text(
                        '${_evidence!.label} · ${_evidence!.distinctQuestions} 道不同题'
                        ' · ${_evidence!.correctCount} 次连续正确'
                        '\n间隔复习：${_evidence!.delayedSuccess ? '已验证' : '至少相隔 24 小时再验证'}'
                        '\n下次复习：${_evidence!.nextReview?.toLocal() ?? '待安排'}',
                      ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => setState(_newAttempt),
                  child: const Text('原题再练'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(_variations),
                  child: const Text('同概念变式'),
                ),
                if (_submission != null)
                  TextButton(
                    onPressed: _busy ? null : () => _run(_regrade),
                    child: const Text('纠正本次判定'),
                  ),
              ],
            ),
          ],
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DocumentDetailPage(
                            documentId: q.documentId,
                          ),
                        ),
                      ),
                child: const Text('回看对应知识'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              q.sourceVersionId == null
                                ? OcrResultPage(documentId: q.documentId)
                                : SourceVersionPage(userId: widget.scope.userId,
                                    versionId: q.sourceVersionId!, database: widget.database),
                        ),
                      ),
                child: const Text('查看原始来源'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(_history),
                child: const Text('作答历史'),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy || _index == 0
                      ? null
                      : () => setState(() {
                          _index--;
                          _newAttempt();
                        }),
                  child: const Text('上一题'),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _busy || _index >= widget.questions.length - 1
                      ? null
                      : () => setState(() {
                          _index++;
                          _newAttempt();
                        }),
                  child: const Text('下一题'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
