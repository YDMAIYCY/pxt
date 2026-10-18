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
  bool _generateNew = false;
  bool _entryScopeActive = true;
  int _count = 5;
  String _difficulty = '基础理解';
  bool get _hasEntryScope =>
      widget.recordId != null ||
      widget.documentId != null ||
      widget.initialConceptId != null ||
      widget.initialQuestionId != null ||
      widget.questionIds != null;
  int? get _sourceDocumentId => _entryScopeActive ? widget.documentId : null;
  List<int>? get _questionIds => !_entryScopeActive
      ? null
      : widget.questionIds ??
            (widget.initialQuestionId == null
                ? null
                : [widget.initialQuestionId!]);
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
    if (_entryScopeActive &&
        widget.initialQuestionId != null &&
        widget.questionIds != null &&
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
    if (_entryScopeActive && _hasEntryScope) {
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
      final recordIds = documents.map((d) => d['import_record_id']).toSet();
      _recordId =
          widget.recordId ??
          (recordIds.length == 1 ? recordIds.single as int? : null);
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
      documentId: _sourceDocumentId,
      wrongOnly: _wrongOnly,
    );
    final concepts = await db.rawQuery(
      '''SELECT DISTINCT c.id, c.name
      FROM knowledge_concepts c JOIN source_documents d ON d.id=c.document_id
      WHERE c.user_id = ? AND d.user_id=c.user_id
        ${_libraryId == null ? '' : 'AND d.library_id = ?'}
        ${_recordId == null ? '' : 'AND d.import_record_id = ?'}
        ${_sourceDocumentId == null ? '' : 'AND d.id = ?'}
      ORDER BY c.name''',
      [user.id, ?_libraryId, ?_recordId, ?_sourceDocumentId],
    );
    final questions = await PracticeSessionRepository(database: widget.database)
        .questions(
          scope,
          dueOnly: _dueOnly,
          questionIds: _questionIds,
          limit: _questionIds?.length ?? 500,
        );
    if (_questionIds != null) {
      final ids = _questionIds!;
      final selected = ids.isEmpty
          ? <Map<String, Object?>>[]
          : await db.rawQuery(
              '''SELECT q.id FROM practice_questions q
              JOIN source_documents d ON d.id=q.document_id
              WHERE ${scope.ownershipClause}
              AND q.id IN (${List.filled(ids.length, '?').join(',')})''',
              [...scope.args, ...ids],
            );
      if (selected.length != ids.toSet().length) {
        throw StateError('部分指定题目已删除或不在当前范围');
      }
      final order = <int>{?widget.initialQuestionId, ..._questionIds!}.toList();
      questions.sort(
        (a, b) => order
            .indexOf(a.question.id)
            .compareTo(order.indexOf(b.question.id)),
      );
    }
    return _PracticeData(scope, libraries, records, concepts, questions);
  }

  void _refresh() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _generate(_PracticeData data) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_libraryId == null) throw StateError('请先选择一个知识库再生成新题');
      final config = await LlmConfigRepository(
        database: widget.database,
      ).getByUserId(data.scope.userId);
      if (config?.isConfigured != true) throw StateError('请先在“我的”配置 AI 模型');
      final scope = PracticeScope(
        userId: data.scope.userId,
        libraryId: _libraryId,
        recordId: _recordId,
        conceptId: _conceptId,
        documentId: _sourceDocumentId,
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

  Widget _scopeField({
    required String label,
    required Key fieldKey,
    required int value,
    required List<DropdownMenuItem<int>> items,
    required ValueChanged<int?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Text(label, style: AppTextStyles.bodySmall(context)),
          ),
          Expanded(
            child: DropdownButtonFormField<int>(
              key: fieldKey,
              initialValue: value,
              isExpanded: true,
              style: AppTextStyles.body(context),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceAlt,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              items: items,
              onChanged: _busy ? null : onChanged,
            ),
          ),
        ],
      ),
    );
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
            onRetry: () async => _refresh(),
          );
        }
        if (!snapshot.hasData) {
          return const AppLoadingState(label: '正在准备练习…');
        }
        final data = snapshot.data!;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                AppSegmented<bool>(
                  value: _generateNew,
                  enabled: !_busy,
                  onChanged: (value) => setState(() => _generateNew = value),
                  options: const [
                    AppSegmentedOption(false, '练已有题'),
                    AppSegmentedOption(true, 'AI 出新题'),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _generateNew
                      ? '根据已解析的资料生成新题，生成后直接开始练习。'
                      : '练习已保存的题目，作答后查看答案与解析。',
                  style: AppTextStyles.bodySmall(context),
                ),
                const SizedBox(height: 20),
                AppCard.outlined(
                  borderRadius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('选择练习范围', style: AppTextStyles.title(context)),
                      const SizedBox(height: 10),
                      _scopeField(
                        label: '知识库',
                        fieldKey: ValueKey('library-$_libraryId'),
                        value: _libraryId ?? -1,
                        items: [
                          if (_libraryId == null)
                            const DropdownMenuItem(
                              value: -1,
                              child: Text('所选题目的知识库'),
                            ),
                          ...data.libraries.map(
                            (library) => DropdownMenuItem(
                              value: library.id,
                              child: Text(
                                library.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (id) {
                          if (id == null || id == -1) return;
                          _entryScopeActive = false;
                          _libraryId = id;
                          _recordId = null;
                          _conceptId = null;
                          _refresh();
                        },
                      ),
                      _scopeField(
                        label: '资料',
                        fieldKey: ValueKey('record-$_libraryId-$_recordId'),
                        value: _recordId ?? -1,
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('全部导入资料'),
                          ),
                          ...data.records.map(
                            (record) => DropdownMenuItem(
                              value: record.id,
                              child: Text(
                                record.title,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (id) {
                          _entryScopeActive = false;
                          _recordId = id == -1 ? null : id;
                          _conceptId = null;
                          _refresh();
                        },
                      ),
                      _scopeField(
                        label: '知识点',
                        fieldKey: ValueKey(
                          'concept-$_libraryId-$_recordId-$_conceptId',
                        ),
                        value: _conceptId ?? -1,
                        items: [
                          const DropdownMenuItem(
                            value: -1,
                            child: Text('全部知识点'),
                          ),
                          ...data.concepts.map(
                            (concept) => DropdownMenuItem(
                              value: concept['id'] as int,
                              child: Text(
                                concept['name'] as String,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (id) {
                          _entryScopeActive = false;
                          _conceptId = id == -1 ? null : id;
                          _refresh();
                        },
                      ),
                      if (_entryScopeActive && _hasEntryScope) ...[
                        const SizedBox(height: 8),
                        Text(
                          _generateNew
                              ? '将依据所选资料出题，题量与难度在下方设置。'
                              : _questionIds != null
                              ? '当前仅练这 ${_questionIds!.toSet().length} 道题，更换范围后会重新选题。'
                              : '当前练习来自所选资料或知识点，可在上方更换。',
                          style: AppTextStyles.caption(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (!_generateNew) ...[
                  Text('筛选已有题', style: AppTextStyles.label(context)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('只练错题'),
                        selected: _wrongOnly,
                        onSelected: _busy
                            ? null
                            : (value) {
                                _wrongOnly = value;
                                _refresh();
                              },
                      ),
                      FilterChip(
                        label: const Text('到期复习'),
                        selected: _dueOnly,
                        onSelected: _busy
                            ? null
                            : (value) {
                                _dueOnly = value;
                                _refresh();
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppCard.tinted(
                    accent: AppColors.primary,
                    borderRadius: 16,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '当前范围：${data.questions.length} 道题',
                          style: AppTextStyles.title(context),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data.questions.isEmpty
                              ? (_wrongOnly || _dueOnly
                                    ? '没有符合筛选条件的题目，试试取消筛选。'
                                    : '还没有保存的题目，可以切换到「AI 出新题」。')
                              : '按当前范围开始，练习结果会保存到学习记录。',
                          style: AppTextStyles.bodySmall(context),
                        ),
                        const SizedBox(height: 16),
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
                          icon: const Icon(Icons.play_arrow_rounded, size: 20),
                          label: const Text('开始练习'),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  AppCard.outlined(
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('出题设置', style: AppTextStyles.title(context)),
                        const SizedBox(height: 16),
                        Text('题量', style: AppTextStyles.label(context)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final count in [5, 10, 20])
                              ChoiceChip(
                                label: Text('$count 道'),
                                selected: _count == count,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(() => _count = count),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('难度', style: AppTextStyles.label(context)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final difficulty in ['基础理解', '综合应用', '深入思考'])
                              ChoiceChip(
                                label: Text(difficulty),
                                selected: _difficulty == difficulty,
                                onSelected: _busy
                                    ? null
                                    : (_) => setState(
                                        () => _difficulty = difficulty,
                                      ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _libraryId == null
                              ? '请先选择一个知识库再生成新题。'
                              : '使用「我的」中配置的 AI 模型，依据所选资料出题并保存。',
                          style: AppTextStyles.caption(context),
                        ),
                        const SizedBox(height: 16),
                        if (_busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                        ],
                        FilledButton.icon(
                          onPressed: _busy || _libraryId == null
                              ? null
                              : () => _generate(data),
                          icon: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 18,
                          ),
                          label: Text(_busy ? '正在生成，请稍候…' : '生成 $_count 道题并练习'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
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
                  '${r['legacy'] == 1
                      ? '旧版学习反馈'
                      : r['correct'] == 1
                      ? '答对'
                      : '答错'} · ${r['created_at']}',
                ),
                subtitle: Text(
                  '${r['answer']}\n${r['legacy'] == 1 ? r['feedback'] : '修订 ${r['revision']}'}',
                ),
                onTap: () {
                  final q = r['question_snapshot'] == null
                      ? null
                      : jsonDecode(r['question_snapshot'] as String) as Map;
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('作答当时的题目与依据'),
                      content: SingleChildScrollView(
                        child: Text(
                          q == null
                              ? '旧版保留了答案和反馈，没有当时的题目与来源快照。\n${r['feedback']}'
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
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            '练习',
            style: AppTextStyles.title(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        body: const AppEmptyState(
          icon: Icons.inbox_rounded,
          title: '当前范围没有题目',
          description: '换一个范围，或先生成一套专项题。',
        ),
      );
    }
    final q = _question;
    final total = widget.questions.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          '练习 ${_index + 1}/$total',
          style: AppTextStyles.title(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        scrolledUnderElevation: 0,
        actions: [
          AskEClawButton(
            database: widget.database,
            scope: EClawContext(
              knowledgeBaseId: widget.scope.libraryId,
              importRecordId: widget.scope.recordId,
              documentId: q.documentId,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.questions[_index].documentTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(context),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_index + 1} / $total',
                style: AppTextStyles.labelSmall(context).copyWith(
                  color: AppColors.textQuiet,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppProgressBar(value: (_index + 1) / total, height: 4),
          const SizedBox(height: 12),

          // ---- 题目 + 作答 ----
          AppCard.plain(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  q.questionText,
                  style: AppTextStyles.h2(context).copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.55,
                  ),
                ),
                if (q.options.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  for (final (i, option) in q.options.indexed)
                    _ScopedOption(
                      letter: String.fromCharCode(65 + i),
                      text: option,
                      selected:
                          _answer.text.trim().toUpperCase() ==
                          String.fromCharCode(65 + i),
                      onTap: _busy || _submission != null
                          ? null
                          : () => setState(() {
                              _answer.text = String.fromCharCode(65 + i);
                            }),
                    ),
                ],
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppColors.borderLight),
                const SizedBox(height: 14),
                TextField(
                  controller: _answer,
                  minLines: 2,
                  maxLines: 6,
                  enabled: !_busy && _submission == null,
                  decoration: InputDecoration(
                    labelText: '我的答案',
                    hintText: '写下你的答案',
                    filled: true,
                    fillColor: AppColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.cardSmall),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
                const SizedBox(height: 12),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: LinearProgressIndicator(minHeight: 3),
                  ),
                if (_submission == null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: _busy ? null : () => _run(_submit),
                    child: const Text('提交并核对'),
                  ),
              ],
            ),
          ),

          if (_revealed) ...[
            const SizedBox(height: 12),
            _ScopedResultCard(
              correct: _submission?.correct,
              question: q,
              evidence: _evidence,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _QuietAction(
                  label: '原题再练',
                  onTap: _busy ? null : () => setState(_newAttempt),
                ),
                _QuietAction(
                  label: '同概念变式',
                  onTap: _busy ? null : () => _run(_variations),
                ),
                if (_submission != null)
                  _QuietAction(
                    label: '纠正本次判定',
                    onTap: _busy ? null : () => _run(_regrade),
                  ),
              ],
            ),
          ],

          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              DocumentDetailPage(documentId: q.documentId),
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
                          builder: (_) => q.sourceVersionId == null
                              ? OcrResultPage(documentId: q.documentId)
                              : SourceVersionPage(
                                  userId: widget.scope.userId,
                                  versionId: q.sourceVersionId!,
                                  database: widget.database,
                                ),
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
          const Divider(height: 8, color: AppColors.borderLight),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy || _index == 0
                      ? null
                      : () => setState(() {
                          _index--;
                          _newAttempt();
                        }),
                  icon: const Icon(Icons.chevron_left_rounded),
                  label: const Text('上一题'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _busy || _index >= total - 1
                      ? null
                      : () => setState(() {
                          _index++;
                          _newAttempt();
                        }),
                  icon: const Icon(Icons.chevron_right_rounded),
                  label: const Text('下一题'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One answer option as a tappable block with its own letter badge.
class _ScopedOption extends StatelessWidget {
  const _ScopedOption({
    required this.letter,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final String letter;
  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.tintOf(AppColors.primary, 0.08)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadii.cardSmall),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderLight,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  letter,
                  style: AppTextStyles.labelSmall(context).copyWith(
                    color: selected
                        ? AppColors.textOnPrimary
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.bodySmall(context).copyWith(
                    fontSize: 14.5,
                    height: 1.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Check-yourself result: verdict, reference answer, analysis, then the
/// mastery evidence as quiet supporting text.
class _ScopedResultCard extends StatelessWidget {
  const _ScopedResultCard({
    required this.correct,
    required this.question,
    required this.evidence,
  });

  final bool? correct;
  final PracticeQuestionRecord question;
  final MasteryEvidence? evidence;

  @override
  Widget build(BuildContext context) {
    final ok = correct == true;
    final accent = correct == null
        ? AppColors.textSecondary
        : ok
        ? AppColors.success
        : AppColors.error;
    final label = correct == null
        ? '已核对'
        : ok
        ? '本次答对'
        : '本次答错';

    return AppCard.plain(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.tintOf(accent, 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ok
                      ? Icons.check_rounded
                      : correct == null
                      ? Icons.info_outline_rounded
                      : Icons.close_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: AppTextStyles.title(context).copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
              const Spacer(),
              if (evidence != null)
                AppTag(label: evidence!.label, accent: AppColors.accentViolet),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            decoration: BoxDecoration(
              color: AppColors.tintOf(AppColors.success, 0.07),
              borderRadius: BorderRadius.circular(AppRadii.cardSmall),
              border: Border.all(
                color: AppColors.tintOf(AppColors.success, 0.18),
              ),
            ),
            child: SelectableText(
              '参考答案：${question.answerText ?? ''}',
              style: AppTextStyles.bodySmall(
                context,
              ).copyWith(color: AppColors.textPrimary, height: 1.55),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '解析',
            style: AppTextStyles.label(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          SelectableText(
            question.analysisText ?? '暂无解析',
            style: AppTextStyles.bodySmall(
              context,
            ).copyWith(height: 1.6, color: AppColors.slate),
          ),
          if (question.expectedKeywords.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '关键点：${question.expectedKeywords.join('、')}',
              style: AppTextStyles.caption(context),
            ),
          ],
          if (evidence != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 10),
            Text(
              '${evidence!.distinctQuestions} 道不同题 · ${evidence!.correctCount} 次连续正确',
              style: AppTextStyles.caption(context),
            ),
            const SizedBox(height: 3),
            Text(
              '间隔复习：${evidence!.delayedSuccess ? '已验证' : '至少相隔 24 小时再验证'}',
              style: AppTextStyles.caption(context),
            ),
            const SizedBox(height: 3),
            Text(
              '下次复习：${evidence!.nextReview?.toLocal() ?? '待安排'}',
              style: AppTextStyles.caption(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small outlined action used for secondary quiz moves.
class _QuietAction extends StatelessWidget {
  const _QuietAction({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadii.chip),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.chip),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall(context).copyWith(
            color: onTap == null
                ? AppColors.textQuiet
                : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}
