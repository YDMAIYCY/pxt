import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../database/import_record_repository.dart';
import '../../../database/interview_repository.dart';
import '../../../database/knowledge_library_repository.dart';
import '../../../database/llm_config_repository.dart';
import '../../../database/models/import_record.dart';
import '../../../database/models/knowledge_library_record.dart';
import '../../../interview/interview_evidence_service.dart';
import '../../../interview/interview_failure.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/premium_app_chrome.dart';
import 'interview_chat_page.dart';
import 'interview_history_page.dart';
import 'interview_microphone_check.dart';

// ========== AI 面试准备页 ==========
// 只保留开始一次面试真正需要的参数：范围、模式、难度、题量与语音设置。

class InterviewPreparePage extends StatefulWidget {
  const InterviewPreparePage({
    required this.userId,
    this.libraryId,
    this.recordId,
    this.database,
    super.key,
  });

  final int userId;
  final int? libraryId;
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
  double _volume = .7;
  bool _starting = false;
  bool _scopeLoaded = false;
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
    if (_libraryId == null && libraries.isNotEmpty) {
      _libraryId = libraries.first.id;
    }
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
    if (mounted) setState(() => _scopeLoaded = true);
    return (libraries: libraries, records: records);
  }

  Future<void> _start() async {
    if (_starting) return;
    final libraryId = _libraryId;
    if (!_scopeLoaded || libraryId == null || _scopeNotice != null) return;
    final recordId = _recordId;
    setState(() => _starting = true);
    try {
      await _microphoneKey.currentState?.stop();
      if (!mounted) return;
      final config = await LlmConfigRepository(
        database: widget.database,
      ).getByUserId(widget.userId);
      if (config?.isConfigured != true) {
        if (mounted) _toast('请先在“我的”中配置 AI 模型');
        return;
      }
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
      await InterviewEvidenceService(database: widget.database).load(
        userId: widget.userId,
        libraryId: libraryId,
        recordId: recordId,
        mode: _mode,
      );
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
            preparationRoute: ModalRoute.of(context),
          ),
        ),
      );
    } catch (error) {
      if (mounted) _toast(interviewFailure(error, fallback: '暂时无法开始面试，请重试'));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openHistory() async {
    final libraryId = _libraryId;
    final recordId = _recordId;
    try {
      await _microphoneKey.currentState?.stop();
    } catch (error) {
      if (mounted) _toast('麦克风尚未停止，请稍后重试');
      return;
    }
    if (!mounted || _starting || _libraryId != libraryId) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InterviewHistorySheet(
        userId: widget.userId,
        libraryId: libraryId,
        recordId: recordId,
        database: widget.database,
        preparationRoute: ModalRoute.of(context),
      ),
    );
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );

  Future<void> _pickLibrary(List<KnowledgeLibraryRecord> libraries) async {
    final selected = await _pick(
      title: '选择知识库',
      selected: _libraryId ?? 0,
      options: [
        for (final library in libraries)
          _PickOption(
            value: library.id,
            title: library.name,
            subtitle: '${library.documentCount} 份资料',
          ),
      ],
    );
    if (selected == null || !mounted || selected == _libraryId) return;
    setState(() {
      _libraryId = selected;
      _recordId = null;
      _scopeNotice = null;
    });
  }

  Future<void> _pickRecord(List<ImportRecord> records) async {
    // 0 代表“整个知识库”；弹窗被取消时返回 null，不会覆盖当前选择。
    final selected = await _pick(
      title: '选择面试资料',
      selected: _recordId ?? 0,
      options: [
        const _PickOption(value: 0, title: '整个知识库'),
        for (final record in records)
          _PickOption(value: record.id, title: record.title),
      ],
    );
    if (selected == null || !mounted) return;
    setState(() {
      _recordId = selected == 0 ? null : selected;
      _scopeNotice = null;
    });
  }

  Future<int?> _pick({
    required String title,
    required List<_PickOption> options,
    required int selected,
  }) => showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(title, style: AppTextStyles.h3(sheetContext)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final active = option.value == selected;
                  return ListTile(
                    title: Text(
                      option.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: option.subtitle == null
                        ? null
                        : Text(
                            option.subtitle!,
                            style: AppTextStyles.caption(context),
                          ),
                    trailing: active
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                            size: 20,
                          )
                        : null,
                    onTap: () => Navigator.pop(sheetContext, option.value),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('AI 面试准备'),
      actions: [
        IconButton(
          onPressed: _starting ? null : _openHistory,
          tooltip: '面试记录',
          icon: const Icon(Icons.history_rounded, size: 20),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton(
          onPressed:
              !_scopeLoaded ||
                  _starting ||
                  _libraryId == null ||
                  _scopeNotice != null
              ? null
              : _start,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_starting ? '正在准备…' : '开始 AI 面试'),
              if (!_starting) ...[
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ],
          ),
        ),
      ),
    ),
    body: PremiumPageBackground(
      child: FutureBuilder(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _future = _load()),
                child: const Text('加载失败，点击重试'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.libraries.isEmpty) {
            return const Center(child: Text('请先创建知识库并导入资料'));
          }
          final library = data.libraries
              .where((l) => l.id == _libraryId)
              .firstOrNull;
          final records = data.records
              .where((r) => r.libraryId == _libraryId)
              .toList(growable: false);
          final record = records.where((r) => r.id == _recordId).firstOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              _section('面试范围', [
                _PickerRow(
                  label: '知识库',
                  value: library?.name ?? '请选择知识库',
                  enabled: !_starting,
                  onTap: () => _pickLibrary(data.libraries),
                ),
                const SizedBox(height: 10),
                _PickerRow(
                  label: '资料',
                  value: record?.title ?? '整个知识库',
                  enabled: !_starting && _libraryId != null,
                  onTap: () => _pickRecord(records),
                ),
                if (_scopeNotice != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _scopeNotice!,
                    style: AppTextStyles.caption(
                      context,
                    ).copyWith(color: AppColors.error),
                  ),
                ],
              ]),
              _section('面试设置', [
                _choice(
                  '模式',
                  AppSegmented<String>(
                    variant: AppSegmentedVariant.pill,
                    value: _mode,
                    enabled: !_starting,
                    onChanged: (value) => setState(() => _mode = value),
                    options: const [
                      AppSegmentedOption('basic', '基础问答'),
                      AppSegmentedOption('deep', '深度面试'),
                      AppSegmentedOption('quick', '快速复习'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _choice(
                  '难度',
                  AppSegmented<String>(
                    variant: AppSegmentedVariant.pill,
                    value: _difficulty,
                    enabled: !_starting,
                    onChanged: (value) => setState(() => _difficulty = value),
                    options: const [
                      AppSegmentedOption('easy', '简单'),
                      AppSegmentedOption('medium', '中等'),
                      AppSegmentedOption('hard', '困难'),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _choice(
                  '题数',
                  AppSegmented<String>(
                    variant: AppSegmentedVariant.pill,
                    value: '$_count',
                    enabled: !_starting,
                    onChanged: (value) => setState(() => _count = int.parse(value)),
                    options: const [
                      AppSegmentedOption('3', '3 题'),
                      AppSegmentedOption('5', '5 题'),
                      AppSegmentedOption('10', '10 题'),
                    ],
                  ),
                ),
              ]),
              _section('语音设置', [
                _SwitchRow(
                  label: 'AI 面试官语音',
                  value: _voiceEnabled,
                  enabled: !_starting,
                  onChanged: (value) => setState(() => _voiceEnabled = value),
                ),
                _SwitchRow(
                  label: '自动播放问题',
                  value: _autoPlay,
                  enabled: _voiceEnabled && !_starting,
                  onChanged: (value) => setState(() => _autoPlay = value),
                ),
                _slider(
                  '音量',
                  _volume,
                  '${(_volume * 100).round()}%',
                  (value) => setState(() => _volume = value),
                ),
                _slider(
                  '语速',
                  (_rate - .25) / .5,
                  '${(_rate / .5).toStringAsFixed(1)}x',
                  (value) => setState(() => _rate = .25 + value * .5),
                ),
                const SizedBox(height: 4),
                InterviewMicrophoneCheck(
                  key: _microphoneKey,
                  enabled: !_starting,
                ),
              ]),
            ],
          );
        },
      ),
    ),
  );

  Widget _section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: PremiumSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h3(context)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );

  Widget _choice(String label, Widget control) => Row(
    children: [
      SizedBox(
        width: 40,
        child: Text(label, style: AppTextStyles.bodySmall(context)),
      ),
      Expanded(child: control),
    ],
  );

  Widget _slider(
    String title,
    double value,
    String label,
    ValueChanged<double> onChanged,
  ) => Row(
    children: [
      SizedBox(
        width: 44,
        child: Text(title, style: AppTextStyles.bodySmall(context)),
      ),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.clamp(0, 1),
            onChanged: _starting || !_voiceEnabled ? null : onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 44,
        child: Text(
          label,
          textAlign: TextAlign.end,
          style: AppTextStyles.bodySmall(context),
        ),
      ),
    ],
  );
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodySmall(context).copyWith(
              color: enabled ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
        Switch(value: value, onChanged: enabled ? onChanged : null),
      ],
    ),
  );
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label：$value',
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadii.input),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadii.input),
          border: Border.all(color: AppColors.border),
        ),
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(label, style: AppTextStyles.caption(context)),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textTertiary,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PickOption {
  const _PickOption({required this.value, required this.title, this.subtitle});
  final int value;
  final String title;
  final String? subtitle;
}
