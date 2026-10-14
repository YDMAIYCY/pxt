import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../database/import_record_repository.dart';
import '../../../database/interview_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/models/import_record.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../theme/app_theme.dart';
import 'interview_chat_page.dart';
import 'interview_history_page.dart';
import 'interview_microphone_check.dart';

// ========== AI 面试准备页 ==========
// 只保留范围、模式、难度、题量与语音设置，避免堆砌参数。

class InterviewPreparePage extends StatefulWidget {
  const InterviewPreparePage({
    required this.userId,
    required this.libraryId,
    this.recordId,
    this.database,
    super.key,
  });

  final int userId;
  final int libraryId;
  final int? recordId;
  final AppDatabase? database;

  @override
  State<InterviewPreparePage> createState() => _InterviewPreparePageState();
}

class _InterviewPreparePageState extends State<InterviewPreparePage> {
  late Future<
    ({List<KnowledgeLibraryRecord> libraries, List<ImportRecord> records})
  >
  _future;
  int? _libraryId;
  int? _recordId;
  String _mode = 'basic';
  String _difficulty = 'medium';
  int _count = 5;
  bool _voiceEnabled = true;
  bool _autoPlay = true;
  double _rate = .5;
  double _volume = 1;
  bool _starting = false;
  final _microphoneKey = GlobalKey<InterviewMicrophoneCheckState>();
  String? _scopeNotice;

  @override
  void initState() {
    super.initState();
    _libraryId = widget.libraryId;
    _recordId = widget.recordId;
    _future = _load();
  }

  Future<({List<KnowledgeLibraryRecord> libraries, List<ImportRecord> records})>
  _load() async {
    final libraries = await KnowledgeLibraryRepository(
      database: widget.database,
    ).fetchLibraries(widget.userId);
    final records = await ImportRecordRepository(
      database: widget.database,
    ).list(widget.userId);
    if (!libraries.any((library) => library.id == _libraryId)) {
      _libraryId = null;
      _recordId = null;
      _scopeNotice = '原知识库已删除，请重新选择面试范围。';
    } else if (_recordId != null &&
        !records.any(
          (record) =>
              record.id == _recordId &&
              record.libraryId == _libraryId &&
              record.userId == widget.userId,
        )) {
      _recordId = null;
      _scopeNotice = '原资料已删除或不在所选知识库，请重新选择面试范围。';
    }
    return (libraries: libraries, records: records);
  }

  Future<void> _start() async {
    if (_starting) return;
    final libraryId = _libraryId;
    if (libraryId == null || _scopeNotice != null) return;
    final recordId = _recordId;
    setState(() => _starting = true);
    try {
      await _microphoneKey.currentState?.stop();
      if (!mounted) return;
      final repository = InterviewRepository(database: widget.database);
      final data = await _future;
      final library = data.libraries.firstWhere((l) => l.id == libraryId);
      final record = recordId == null
          ? null
          : await ImportRecordRepository(
              database: widget.database,
            ).get(widget.userId, recordId);
      if (recordId != null &&
          (record == null ||
              record.libraryId != libraryId ||
              record.userId != widget.userId)) {
        throw StateError('资料已删除或移出所选知识库，请重新选择范围');
      }
      if (!mounted) return;
      final scopeName = record == null
          ? '${library.name} · 整个知识库'
          : '${library.name} · ${record.title}';
      final session = await repository.createSession(
        userId: widget.userId,
        libraryId: libraryId,
        recordId: record?.id,
        scopeName: scopeName,
        mode: _mode,
        difficulty: _difficulty,
        targetQuestionCount: _count,
        voiceEnabled: _voiceEnabled,
        autoPlay: _autoPlay,
        voiceRate: _rate,
        voiceVolume: _volume,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => InterviewChatPage(
            userId: widget.userId,
            sessionId: session.id,
            repository: repository,
            database: widget.database,
          ),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法开始面试：$error')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openHistory() async {
    final libraryId = _libraryId;
    if (libraryId == null) return;
    final recordId = _recordId;
    try {
      await _microphoneKey.currentState?.stop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法停止麦克风测试：$error')));
      }
      return;
    }
    if (!mounted ||
        _starting ||
        _libraryId != libraryId ||
        _recordId != recordId) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InterviewHistoryPage(
          userId: widget.userId,
          libraryId: libraryId,
          recordId: recordId,
          database: widget.database,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI 面试准备'),
      actions: [
        TextButton.icon(
          onPressed: _starting || _scopeNotice != null ? null : _openHistory,
          icon: const Icon(Icons.history_rounded, size: 18),
          label: const Text('历史'),
        ),
      ],
    ),
    body: FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final records = data.records
            .where((r) => r.libraryId == _libraryId)
            .toList(growable: false);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _section('面试范围', [
              DropdownButtonFormField<int>(
                key: ValueKey('interview-library:$_libraryId'),
                initialValue: _libraryId,
                decoration: const InputDecoration(labelText: '知识库'),
                items: data.libraries
                    .map(
                      (l) => DropdownMenuItem(value: l.id, child: Text(l.name)),
                    )
                    .toList(),
                onChanged: _starting
                    ? null
                    : (value) => setState(() {
                        _libraryId = value;
                        _recordId = null;
                        _scopeNotice = null;
                      }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                key: ValueKey('interview-scope:$_libraryId:$_recordId'),
                initialValue: _recordId,
                hint: const Text('整个知识库'),
                decoration: const InputDecoration(labelText: '范围'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('整个知识库'),
                  ),
                  ...records.map(
                    (r) => DropdownMenuItem<int?>(
                      value: r.id,
                      child: Text(r.title),
                    ),
                  ),
                ],
                onChanged: _starting || _libraryId == null
                    ? null
                    : (value) => setState(() {
                        _recordId = value;
                        _scopeNotice = null;
                      }),
              ),
              if (_scopeNotice != null) ...[
                const SizedBox(height: 8),
                Text(
                  _scopeNotice!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ]),
            _section('面试模式', [
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {
                    'basic': '基础问答',
                    'deep': '深度面试',
                    'quick': '快速复习',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _mode == entry.key,
                      onSelected: (_) => setState(() => _mode = entry.key),
                    ),
                ],
              ),
            ]),
            _section('难度与题量', [
              Wrap(
                spacing: 8,
                children: [
                  for (final entry in const {
                    'easy': '简单',
                    'medium': '中等',
                    'hard': '困难',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _difficulty == entry.key,
                      onSelected: (_) =>
                          setState(() => _difficulty = entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final value in const [3, 5, 10])
                    ChoiceChip(
                      label: Text('$value 题'),
                      selected: _count == value,
                      onSelected: (_) => setState(() => _count = value),
                    ),
                ],
              ),
            ]),
            _section('语音设置', [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _voiceEnabled,
                title: const Text('AI 面试官语音播报'),
                onChanged: (value) => setState(() => _voiceEnabled = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoPlay,
                title: const Text('自动播放问题'),
                onChanged: _voiceEnabled
                    ? (value) => setState(() => _autoPlay = value)
                    : null,
              ),
              Text(
                '语速 ${(_rate * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.bodySmall(context),
              ),
              Slider(
                value: _rate,
                onChanged: (value) => setState(() => _rate = value),
              ),
              Text(
                '音量 ${(_volume * 100).toStringAsFixed(0)}%',
                style: AppTextStyles.bodySmall(context),
              ),
              Slider(
                value: _volume,
                onChanged: (value) => setState(() => _volume = value),
              ),
              const Text(
                '离线中文识别首次使用需要下载模型；也可以在面试中使用文字回答。',
                style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 12),
              InterviewMicrophoneCheck(
                key: _microphoneKey,
                enabled: !_starting,
              ),
            ]),
            _section('资料与回答的使用', [
              Text(
                '中文语音识别（ASR）在本机离线运行；语音播报（TTS）使用已安装的本地中文语音。'
                '首次模型下载需要联网。',
                style: AppTextStyles.bodySmall(context),
              ),
              const SizedBox(height: 6),
              Text(
                '出题与评分会将当前选中的${_recordId == null ? '知识库资料' : '单份资料'}和你的回答'
                '发送给已配置的 LLM 服务。只使用所选范围，不混入其他知识库或未选中的资料。',
                style: AppTextStyles.bodySmall(context),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _starting || _libraryId == null || _scopeNotice != null
                  ? null
                  : _start,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(_starting ? '正在创建会话…' : '开始 AI 面试'),
            ),
          ],
        );
      },
    ),
  );

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTextStyles.h3(context)),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}
