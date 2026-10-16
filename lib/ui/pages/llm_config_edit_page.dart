import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../database/llm_config_repository.dart';
import '../../database/models/llm_provider_config.dart';
import '../../llm/llm_model_catalog.dart';
import '../../llm/llm_request_support.dart';
import '../../llm/minimax_client.dart';

const _blue = Color(0xFF3068E9);
const _background = Color(0xFFF7F9FC);
const _muted = Color(0xFF73819B);

class LlmConfigEditPage extends StatefulWidget {
  const LlmConfigEditPage({
    super.key,
    required this.config,
    this.repository,
    this.httpClient,
  });
  final LlmProviderConfig config;
  final LlmConfigRepository? repository;
  final http.Client? httpClient;
  @override
  State<LlmConfigEditPage> createState() => _LlmConfigEditPageState();
}

class _LlmConfigEditPageState extends State<LlmConfigEditPage> {
  late final _repository = widget.repository ?? LlmConfigRepository();
  final _name = TextEditingController();
  final _key = TextEditingController();
  final _base = TextEditingController();
  final _model = TextEditingController();
  final _tokens = TextEditingController();
  final _drafts = <String, LlmProviderConfig>{};
  late LlmProviderConfig _config;
  List<LlmModelOption> _models = [];
  bool _loading = true, _saving = false, _refreshing = false;
  bool _testing = false, _visible = false;
  String? _modelMessage, _testMessage, _loadError;
  bool _testSucceeded = false;
  http.Client? _testClient;

  List<LlmProviderPreset> get _presets {
    const order = [
      'openai',
      'deepseek',
      'kimi',
      'minimax',
      'zhipu',
      'opencode_go',
      'claude',
      'gemini',
      'siliconflow',
      'custom',
    ];
    return order
        .map(
          (id) => LlmModelCatalog.providerPresets.firstWhere(
            (p) => p.provider == id,
          ),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final known = _presets.any((p) => p.provider == widget.config.provider);
    _config = known
        ? widget.config
        : widget.config.copyWith(provider: LlmProvider.custom);
    _loadFields(_config);
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    try {
      for (final preset in _presets) {
        final saved = await _repository.getForProvider(
          widget.config.userId,
          preset.provider,
        );
        if (saved != null) _drafts[preset.provider] = saved;
      }
      _drafts.putIfAbsent(_config.provider, () => _config);
    } catch (_) {
      _loadError = '无法读取安全存储，请重新进入页面后重试。';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _loadFields(LlmProviderConfig config) {
    _config = config;
    _name.text = config.displayName.isEmpty
        ? _presets.firstWhere((p) => p.provider == config.provider).label
        : config.displayName;
    _key.text = config.apiKey;
    _base.text = config.effectiveBaseUrl;
    _model.text = config.effectiveModel;
    _tokens.text = config.effectiveMaxTokens.toString();
    _models = LlmModelCatalog.modelsFor(
      provider: config.provider,
      baseUrl: config.baseUrl,
      currentModel: config.effectiveModel,
    );
    _visible = false;
    _modelMessage = null;
    _testMessage = null;
  }

  LlmProviderConfig _readFields() => _config.copyWith(
    apiMode:
        _config.isMiniMax &&
            _config.apiMode == LlmApiMode.openAiCompatible &&
            _key.text.trim().startsWith('sk-cp-')
        ? LlmApiMode.tokenPlan
        : _config.apiMode,
    displayName: _name.text.trim(),
    apiKey: _key.text.trim(),
    baseUrl: _base.text.trim(),
    model: _model.text.trim(),
    maxTokens: int.tryParse(_tokens.text),
    updatedAt: DateTime.now(),
  );

  void _selectProvider(LlmProviderPreset preset) {
    if (_config.provider == preset.provider) return;
    _drafts[_config.provider] = _readFields();
    final mode = switch (preset.provider) {
      LlmProvider.opencodeGo => LlmApiMode.auto,
      LlmProvider.claude => LlmApiMode.anthropic,
      LlmProvider.gemini => LlmApiMode.gemini,
      LlmProvider.openai => LlmApiMode.responses,
      _ => LlmApiMode.openAiCompatible,
    };
    final config =
        _drafts[preset.provider] ??
        LlmProviderConfig.emptyForUser(widget.config.userId).copyWith(
          provider: preset.provider,
          apiMode: mode,
          baseUrl: preset.baseUrl,
          model: preset.models.isEmpty ? '' : preset.models.first.id,
        );
    setState(() => _loadFields(config));
  }

  bool _validate() {
    String? message;
    final uri = Uri.tryParse(_base.text.trim());
    final tokens = int.tryParse(_tokens.text);
    if (_key.text.trim().isEmpty) {
      message = '请填写 API Key';
    } else if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      message = '请填写有效的 Base URL，不要包含密钥、查询参数或片段';
    } else if (_model.text.trim().isEmpty) {
      message = '请选择或填写模型 ID';
    } else if (tokens == null || tokens < 512 || tokens > 32768) {
      message = '最大 Tokens 请输入 512～32768 之间的整数';
    }
    if (message != null) _message(message);
    return message == null;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      final current = _readFields();
      _drafts[current.provider] = current;
      for (final draft in _drafts.values) {
        if (draft.provider != current.provider) {
          await _repository.saveProvider(draft);
        }
      }
      final saved = await _repository.save(current);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) _message('保存失败，请检查安全存储后重试。当前输入已保留。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _modelMessage = null;
    });
    try {
      final models = await LlmModelCatalog.fetchModels(
        provider: _config.provider,
        baseUrl: _base.text,
        apiKey: _key.text,
        httpClient: widget.httpClient,
      );
      if (!mounted) return;
      setState(() {
        _models = models;
        _modelMessage = '已从接口读取 ${models.length} 个模型，实际访问权限以连接测试为准。';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _modelMessage =
              '${LlmRequestSupport.redact(error.toString(), _key.text)}\n可继续手动填写模型 ID。',
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    final config = _readFields();
    final transport = widget.httpClient ?? http.Client();
    if (widget.httpClient == null) _testClient = transport;
    final watch = Stopwatch()..start();
    try {
      final reply =
          await MiniMaxClient.fromConfig(
            config,
            httpClient: transport,
          ).generateChatReply(
            systemPrompt: '这是连接测试。请简短回复。',
            messages: [
              {
                'role': 'user',
                'content': config.responseFormat == 'json'
                    ? '只返回 JSON 对象 {"ok":true}'
                    : '请只回复：连接成功',
              },
            ],
          );
      if (reply.trim().isEmpty) throw const MiniMaxException('接口返回空内容');
      if (mounted) {
        setState(() {
          _testSucceeded = true;
          _testMessage = '连接成功 · ${watch.elapsedMilliseconds} 毫秒\n模型已返回有效内容。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _testSucceeded = false;
          _testMessage =
              '连接失败：${LlmRequestSupport.redact(error.toString(), config.apiKey)}';
        });
      }
    } finally {
      if (widget.httpClient == null) transport.close();
      _testClient = null;
      if (mounted) setState(() => _testing = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  Future<void> _chooseModel() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (_) => _ModelPicker(models: _models, selected: _model.text),
    );
    if (result != null && mounted) {
      setState(() {
        _model.text = result;
        _testMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _testClient?.close();
    for (final controller in [_name, _key, _base, _model, _tokens]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _refreshing || _testing || _loading;
    final selected = _models.where((m) => m.id == _model.text).firstOrNull;
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: _blue, primary: _blue),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9FE),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE1E8F5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE1E8F5)),
          ),
        ),
      ),
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: const Color(0xFF111D34),
          centerTitle: true,
          title: const Text(
            'AI 模型配置',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton(
              onPressed: busy || _loadError != null ? null : _save,
              child: Text(
                _saving ? '保存中' : '保存',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: AbsorbPointer(
            absorbing: busy,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    '连接你的模型服务，用于知识生成、问答与 EClaw 助手。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                ),
                if (_loading) const LinearProgressIndicator(),
                if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _loadError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                _section(
                  icon: Icons.view_in_ar_outlined,
                  title: '服务商选择',
                  subtitle: '选择你要使用的模型服务商',
                  child: _providerGrid(),
                ),
                _section(
                  icon: Icons.description_outlined,
                  title: '服务配置',
                  child: Column(
                    children: [
                      _field('服务商名称', _name, hint: '服务商名称'),
                      _field(
                        'API Key',
                        _key,
                        secret: true,
                        hint: '粘贴你的 API Key',
                      ),
                      _field('Base URL', _base, hint: '输入服务接口地址'),
                    ],
                  ),
                ),
                _section(
                  icon: Icons.layers_outlined,
                  title: '模型选择',
                  subtitle: '选择合适的模型，获取更好的效果',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: _refresh,
                          icon: _refreshing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh, size: 18),
                          label: const Text('刷新模型'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F6FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFBDD8FF)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              backgroundColor: _blue,
                              child: Icon(
                                Icons.auto_awesome_outlined,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selected?.label ??
                                        (_model.text.isEmpty
                                            ? '请选择模型'
                                            : _model.text),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _model.text.isEmpty
                                        ? '支持从列表选择或手动填写'
                                        : _model.text,
                                    style: const TextStyle(
                                      color: _blue,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    selected?.description ??
                                        '手动配置的模型，使用前请测试连接。',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_model.text.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.check_circle,
                                  color: _blue,
                                  size: 22,
                                ),
                              ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _chooseModel,
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('搜索和切换模型'),
                      ),
                      _field('模型 ID', _model, hint: '也可以手动填写模型 ID'),
                      Text(
                        _modelMessage ?? '预设仅供选择；刷新后显示接口返回的模型。',
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                _section(
                  icon: Icons.tune,
                  title: '高级设置',
                  subtitle: '按需调整模型参数',
                  child: ExpansionTile(
                    key: ValueKey('advanced_${_config.provider}'),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    shape: const Border(),
                    title: const Text(
                      '温度、最大 Tokens、连接测试与响应格式',
                      style: TextStyle(fontSize: 13, color: _muted),
                    ),
                    children: [_advanced()],
                  ),
                ),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 17, color: _muted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '支持通过 OpenAI-compatible 接口接入更多模型服务。',
                        style: TextStyle(fontSize: 12, color: _muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _providerGrid() => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 330 ? 3 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
      // Index-aligned with the provider order in _presets.
      const colors = [
        Color(0xFF22B8D6),
        _blue,
        Color(0xFF9255EB),
        Color(0xFFEA73A5),
        Color(0xFFD9A521),
        Color(0xFF24BF94),
        Color(0xFFF48454),
        Color(0xFF7955EF),
        Color(0xFF5876CB),
        _muted,
      ];
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _presets.asMap().entries.map((entry) {
          final preset = entry.value;
          final selected = _config.provider == preset.provider;
          return SizedBox(
            width: width,
            child: Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                key: ValueKey('provider_${preset.provider}'),
                onTap: () => _selectProvider(preset),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 68),
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFEEF4FF)
                        : const Color(0xFFFAFBFE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? _blue : const Color(0xFFE4EAF5),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: colors[entry.key % colors.length],
                              child: preset.provider == 'custom'
                                  ? const Icon(
                                      Icons.settings_outlined,
                                      size: 17,
                                      color: Colors.white,
                                    )
                                  : Text(
                                      preset.label.substring(0, 1),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                preset.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected
                                      ? _blue
                                      : const Color(0xFF17223A),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        const Positioned(
                          top: 0,
                          right: 0,
                          child: Icon(
                            Icons.check_circle,
                            color: _blue,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      );
    },
  );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool secret = false,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final title = Text(
          label,
          style: const TextStyle(color: _muted, fontSize: 13),
        );
        final input = TextField(
          key: ValueKey('field_$label'),
          controller: controller,
          obscureText: secret && !_visible,
          autocorrect: false,
          enableSuggestions: !secret,
          keyboardType: numeric ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 14),
          onChanged: (_) => setState(() => _testMessage = null),
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: secret
                ? IconButton(
                    tooltip: _visible ? '隐藏密钥' : '显示密钥',
                    onPressed: () => setState(() => _visible = !_visible),
                    icon: Icon(
                      _visible
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _muted,
                      size: 21,
                    ),
                  )
                : null,
          ),
        );
        if (constraints.maxWidth >= 300 &&
            MediaQuery.textScalerOf(context).scale(1) <= 1.2) {
          return Row(
            children: [
              SizedBox(width: 88, child: title),
              Expanded(child: input),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const SizedBox(height: 7), input],
        );
      },
    ),
  );

  Widget _advanced() {
    final current = _readFields();
    final temperature = _config.temperature ?? (_config.isKimi ? 1.0 : 0.2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_config.provider == LlmProvider.opencodeGo ||
            _config.isMiniMax ||
            _config.provider == LlmProvider.openai)
          DropdownButtonFormField<String>(
            key: ValueKey('protocol_${_config.provider}'),
            initialValue: _config.apiMode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '接口协议'),
            items: [
              if (_config.provider == LlmProvider.opencodeGo)
                const DropdownMenuItem(
                  value: LlmApiMode.auto,
                  child: Text('按模型自动选择'),
                ),
              const DropdownMenuItem(
                value: LlmApiMode.openAiCompatible,
                child: Text('对话接口（Chat Completions）'),
              ),
              const DropdownMenuItem(
                value: LlmApiMode.responses,
                child: Text('Responses'),
              ),
              const DropdownMenuItem(
                value: LlmApiMode.anthropic,
                child: Text('Anthropic Messages'),
              ),
              const DropdownMenuItem(
                value: LlmApiMode.gemini,
                child: Text('Gemini 原生接口'),
              ),
              if (_config.isMiniMax) ...[
                const DropdownMenuItem(
                  value: LlmApiMode.tokenPlan,
                  child: Text('MiniMax Token Plan'),
                ),
                const DropdownMenuItem(
                  value: LlmApiMode.openPlatform,
                  child: Text('MiniMax 开放平台（旧版）'),
                ),
              ],
            ],
            onChanged: (mode) => setState(() {
              _config = _config.copyWith(apiMode: mode);
              _testMessage = null;
            }),
          ),
        const SizedBox(height: 12),
        Text(
          '温度  ${temperature.toStringAsFixed(1)}',
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        Slider(
          value: temperature.clamp(0, 2),
          min: 0,
          max: 2,
          divisions: 20,
          onChanged:
              _config.isKimi || current.effectiveApiMode == LlmApiMode.responses
              ? null
              : (value) => setState(() {
                  _config = _config.copyWith(temperature: value);
                  _testMessage = null;
                }),
        ),
        if (_config.isKimi || current.effectiveApiMode == LlmApiMode.responses)
          const Text(
            '该模型的温度由服务商协议控制。',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        _field('最大 Tokens', _tokens, numeric: true, hint: '4096'),
        DropdownButtonFormField<String>(
          key: ValueKey('format_${_config.provider}'),
          isExpanded: true,
          initialValue: _config.responseFormat,
          decoration: const InputDecoration(labelText: '响应格式'),
          items: const [
            DropdownMenuItem(value: 'auto', child: Text('自动（跟随业务需求）')),
            DropdownMenuItem(value: 'text', child: Text('文本')),
            DropdownMenuItem(value: 'json', child: Text('JSON')),
          ],
          onChanged: (value) => setState(() {
            _config = _config.copyWith(responseFormat: value);
            _testMessage = null;
          }),
        ),
        const SizedBox(height: 8),
        const Text(
          '知识生成、面试评分等结构化任务始终使用 JSON；部分模型通过提示词约束。',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _test,
          icon: const Icon(Icons.link),
          label: Text(_testing ? '正在测试连接…' : '测试连接'),
        ),
        if (_testMessage != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _testMessage!,
              style: TextStyle(
                fontSize: 13,
                color: _testSucceeded
                    ? const Color(0xFF159977)
                    : Colors.red.shade700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _section({
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: _blue.withValues(alpha: 0.035),
          blurRadius: 20,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFFEDF5FF),
              child: Icon(icon, color: _blue, size: 23),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111D34),
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.selected});
  final List<LlmModelOption> models;
  final String selected;
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final models = widget.models
        .where(
          (m) => '${m.label} ${m.id}'.toLowerCase().contains(
            _search.toLowerCase(),
          ),
        )
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            0.65,
        child: Column(
          children: [
            const Text(
              '选择模型',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '搜索模型名称或 ID',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: models.isEmpty
                  ? const Center(child: Text('未找到模型，可返回手动填写模型 ID。'))
                  : ListView.builder(
                      itemCount: models.length,
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(model.label),
                          subtitle: Text('${model.id}\n${model.description}'),
                          trailing: model.id == widget.selected
                              ? const Icon(Icons.check_circle, color: _blue)
                              : null,
                          onTap: () => Navigator.pop(context, model.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
