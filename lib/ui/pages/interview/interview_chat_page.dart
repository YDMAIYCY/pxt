import 'dart:async';

import 'package:flutter/material.dart';

import '../../../database/app_database.dart';
import '../../../database/interview_repository.dart';
import '../../../database/llm_config_repository.dart';
import '../../../interview/avatar/interview_avatar.dart';
import '../../../interview/interview_controller.dart';
import '../../../interview/interview_models.dart';
import '../../../interview/interview_evidence_service.dart';
import '../../../interview/interview_voice_port.dart';
import '../../../interview/speech/interview_speech.dart';
import '../../theme/app_theme.dart';
import 'interview_result_page.dart';

// ========== AI 语音面试主页面 ==========
// 微信式左右消息布局：AI 面试官在左、用户回答在右，顶部是数字人卡片。

class InterviewChatPage extends StatefulWidget {
  const InterviewChatPage({
    required this.userId,
    required this.sessionId,
    this.controller,
    this.voice,
    this.repository,
    this.database,
    super.key,
  });

  final int userId;
  final int sessionId;
  final InterviewController? controller;

  /// 可注入的语音实现；为空时才创建离线语音服务。
  final InterviewVoicePort? voice;
  final InterviewRepository? repository;
  final AppDatabase? database;

  @override
  State<InterviewChatPage> createState() => _InterviewChatPageState();
}

class _InterviewChatPageState extends State<InterviewChatPage>
    with WidgetsBindingObserver {
  InterviewController? _controller;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _textAnswer = TextEditingController();
  bool _starting = true;
  String? _loadError;
  bool _showTextInput = false;
  double? _downloadProgress;
  bool _newMessages = false;
  int _messageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 首帧后再启动，避免在 build 阶段同步 setState/通知。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _boot();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onChanged);
    if (widget.controller == null) _controller?.dispose();
    _scroll.dispose();
    _textAnswer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        (state == AppLifecycleState.inactive &&
            (_controller?.voice.phase.value == VoicePhase.recording ||
                _controller?.voice.phase.value == VoicePhase.speaking))) {
      unawaited(_controller?.pause());
    }
  }

  Future<void> _toggleText() async {
    final controller = _controller;
    if (controller == null) return;
    if (!_showTextInput) {
      if (!controller.canRecord && !controller.hasPendingAnswer) return;
      final pending = controller.liveMessage?.text ?? '';
      if (!controller.hasPendingAnswer) await controller.startTextAnswer();
      _textAnswer.text = pending;
    }
    if (mounted) setState(() => _showTextInput = !_showTextInput);
  }

  Future<void> _boot() async {
    setState(() {
      _starting = true;
      _loadError = null;
    });
    try {
      final repo =
          widget.repository ?? InterviewRepository(database: widget.database);
      var controller = widget.controller;
      if (controller == null) {
        final session = await repo.getSession(widget.userId, widget.sessionId);
        if (session == null) throw StateError('面试会话不存在或已删除');
        final config = await LlmConfigRepository(
          database: widget.database,
        ).getByUserId(widget.userId);
        final voice = widget.voice ?? await _createVoice(session);
        controller = InterviewController(
          userId: widget.userId,
          session: session,
          repository: repo,
          voice: voice,
          evidenceService: InterviewEvidenceService(database: widget.database),
          llmConfig: config,
        );
      }
      if (!mounted) {
        controller.dispose();
        return;
      }
      _controller = controller..addListener(_onChanged);
      setState(() => _starting = false);
      await controller.resume();
      _scrollToBottom(force: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _loadError = '$error';
        });
      }
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final controller = _controller;
    if (controller != null) {
      final count =
          controller.messages.length + (controller.liveMessage == null ? 0 : 1);
      if (count != _messageCount &&
          _scroll.hasClients &&
          _scroll.position.maxScrollExtent - _scroll.position.pixels > 120) {
        _newMessages = true;
      }
      _messageCount = count;
      _scrollToBottom();
    }
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final atBottom = position.maxScrollExtent - position.pixels < 120;
      if (force || atBottom) {
        if (_newMessages) setState(() => _newMessages = false);
        _scroll.animateTo(
          position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _checkModel() async {
    final controller = _controller;
    if (controller == null) return;
    if (_downloadProgress != null) return;
    setState(() => _downloadProgress = 0);
    try {
      await controller.voice.ensureOfflineModel(
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (mounted) _toast(controller.voice.modelReady ? '离线识别模型已就绪' : '模型尚未就绪');
    } catch (error) {
      if (mounted) _toast('模型准备失败：$error');
    } finally {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  /// 语音服务不可用时降级为纯文字面试，而不是让整场面试无法开始。
  Future<InterviewVoicePort> _createVoice(InterviewSession session) async {
    try {
      // 平台目录查询在异常环境下可能不返回，超时后按无麦克风降级。
      return await createOfflineInterviewVoiceService(
        settings: VoiceSettings(
          volume: session.voiceVolume,
          rate: session.voiceRate,
        ),
      ).timeout(const Duration(seconds: 10));
    } catch (error) {
      if (mounted) _toast('语音服务不可用，可先用文字回答：$error');
      return NoopInterviewVoice();
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );

  Future<void> _micPressed() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.phase == InterviewPhase.speaking) {
      await controller.interruptSpeech();
    }
    if (controller.phase == InterviewPhase.recording) {
      await controller.stopRecording();
    } else if (controller.canRecord) {
      if (!controller.voiceAvailable) {
        _toast('离线识别模型尚未就绪，可点击“文字回答”作答');
        return;
      }
      await controller.beginRecording();
    }
  }

  Future<void> _submit() async {
    final controller = _controller;
    if (controller == null) return;
    _textAnswer.clear();
    setState(() => _showTextInput = false);
    if (controller.liveMessage != null) {
      await controller.submitAnswer();
    }
  }

  Future<void> _endInterview() async {
    final controller = _controller;
    if (controller == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次面试'),
        content: const Text('已完成的题目会保留评分并生成报告，未完成的题目将标记为未作答。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续面试'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束并生成报告'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.endEarly();
      if (mounted) await _openReport();
    }
  }

  Future<void> _openReport() async {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.isFinished) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InterviewResultPage(
          userId: widget.userId,
          sessionId: widget.sessionId,
          repository: widget.repository,
          database: widget.database,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final recording = controller?.phase == InterviewPhase.recording;
    return PopScope(
      canPop: !recording,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('正在录音'),
            content: const Text('离开会丢失当前这段录音，确定要退出吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续录音'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('退出'),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          await controller?.cancelRecording();
          if (mounted) navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F7FF),
        appBar: AppBar(
          title: const Text('AI 语音面试'),
          actions: [
            IconButton(
              tooltip: '结束面试',
              onPressed: controller == null || controller.isFinished
                  ? null
                  : _endInterview,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ),
        body: SafeArea(child: _body(controller)),
      ),
    );
  }

  void _showSources(InterviewController controller) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              controller.session.scopeName,
              style: AppTextStyles.h3(context),
            ),
            const Text('本次面试范围已固定，结束后可重新选择资料。'),
            for (final question in controller.questions)
              ListTile(
                title: Text(
                  '第 ${question.orderIndex + 1} 题 · ${question.knowledgePoint}',
                ),
                subtitle: Text(
                  '${question.sourceKind == 'ocr' ? '原始 OCR' : 'AI 派生内容'} · 来源页面 ${question.sourcePageId}\n${question.evidenceText}',
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(InterviewController? controller) {
    if (_starting || controller == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _loadError ?? '正在准备面试…',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall(context),
              ),
            ),
            if (_loadError != null)
              TextButton(onPressed: _boot, child: const Text('重试')),
          ],
        ),
      );
    }
    return Column(
      children: [
        _SourceBar(
          session: controller.session,
          onTap: () => _showSources(controller),
        ),
        if (MediaQuery.viewInsetsOf(context).bottom == 0)
          _AvatarCard(controller: controller),
        Expanded(
          child: Stack(
            children: [
              _ChatList(controller: controller, scroll: _scroll),
              if (_newMessages)
                Positioned(
                  right: 16,
                  bottom: 8,
                  child: FilledButton.tonal(
                    onPressed: () => _scrollToBottom(force: true),
                    child: const Text('查看新消息'),
                  ),
                ),
            ],
          ),
        ),
        if (controller.error != null) _ErrorBanner(message: controller.error!),
        if (_downloadProgress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: _downloadProgress),
                ),
                TextButton(
                  onPressed: () => controller.voice.cancel(),
                  child: const Text('取消下载'),
                ),
              ],
            ),
          ),
        _ProgressBar(controller: controller),
        _BottomControls(
          controller: controller,
          showTextInput: _showTextInput,
          textController: _textAnswer,
          onMic: _micPressed,
          onSubmit: _submit,
          onToggleText: _toggleText,
          onEnd: _endInterview,
          onReport: _openReport,
          onTestModel: _downloadProgress == null ? _checkModel : () {},
        ),
      ],
    );
  }
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({required this.session, required this.onTap});
  final VoidCallback onTap;
  final InterviewSession session;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.menu_book_rounded,
              color: AppColors.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                session.scopeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            const Text(
              '面试中不可切换',
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AvatarCard extends StatelessWidget {
  const _AvatarCard({required this.controller});
  final InterviewController controller;

  AvatarMood get _mood {
    switch (controller.phase) {
      case InterviewPhase.recording:
        return AvatarMood.listening;
      case InterviewPhase.transcribing:
      case InterviewPhase.evaluating:
      case InterviewPhase.generatingQuestions:
        return AvatarMood.thinking;
      case InterviewPhase.speaking:
      case InterviewPhase.askingQuestion:
        return AvatarMood.speaking;
      case InterviewPhase.finished:
        return AvatarMood.happy;
      case InterviewPhase.failed:
        return AvatarMood.error;
      default:
        return AvatarMood.idle;
    }
  }

  String get _status {
    switch (controller.phase) {
      case InterviewPhase.speaking:
      case InterviewPhase.askingQuestion:
        return 'AI 正在提问';
      case InterviewPhase.recording:
        return '正在聆听';
      case InterviewPhase.transcribing:
        return '正在转写';
      case InterviewPhase.evaluating:
        return 'AI 正在思考';
      case InterviewPhase.generatingQuestions:
        return '正在根据资料出题';
      case InterviewPhase.awaitingConfirmation:
        return '请确认你的回答';
      case InterviewPhase.finished:
        return '面试已完成';
      case InterviewPhase.failed:
        return '出现异常';
      case InterviewPhase.paused:
        return '已暂停';
      default:
        return '等待回答';
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Container(
      padding: const EdgeInsets.all(12),
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
            mood: _mood,
            mouthActivity: controller.voice.mouthActivity,
            size: 78,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 面试官',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.currentQuestion?.knowledgePoint ?? '基于所选知识库出题',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '重听问题',
            onPressed: controller.phase == InterviewPhase.recording
                ? null
                : controller.replayQuestion,
            icon: const Icon(Icons.volume_up_outlined),
          ),
        ],
      ),
    ),
  );
}

class _ChatList extends StatelessWidget {
  const _ChatList({required this.controller, required this.scroll});
  final InterviewController controller;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final items = [...controller.messages];
    final live = controller.liveMessage;
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      itemCount: items.length + (live == null ? 0 : 1),
      itemBuilder: (context, index) => index >= items.length
          ? _Bubble(message: live!, live: true, controller: controller)
          : _Bubble(message: items[index], live: false, controller: controller),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.live,
    required this.controller,
  });
  final InterviewController controller;
  final InterviewMessage message;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .68,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFFD6E6FF)
            : Colors.white.withValues(alpha: .96),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isUser ? 16 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 16),
        ),
        border: Border.all(
          color: isUser ? const Color(0xFFBBD5FF) : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isUser ? '我的回答' : (message.isFollowUp ? 'AI 追问' : 'AI 面试官'),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isUser ? AppColors.primaryDark : AppColors.primary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message.text.isEmpty ? (live ? '正在识别…' : '') : message.text,
            style: AppTextStyles.body(context).copyWith(fontSize: 15),
          ),
          if (!isUser && controller.session.voiceEnabled)
            TextButton.icon(
              onPressed: controller.canRecord
                  ? () => controller.replayMessage(message)
                  : null,
              icon: const Icon(Icons.volume_up_outlined, size: 16),
              label: const Text('重听'),
            ),
          if (isUser && message.audioPath != null)
            TextButton.icon(
              onPressed:
                  controller.phase == InterviewPhase.awaitingAnswer ||
                      controller.hasPendingAnswer
                  ? () async {
                      try {
                        await controller.voice.playRecording(
                          message.audioPath!,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('回放失败：$error')),
                          );
                        }
                      }
                    }
                  : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(
                '回放 ${((message.durationMs ?? 0) / 1000).toStringAsFixed(1)} 秒',
              ),
            ),
          if (live)
            Text(
              message.pending ? '临时转写' : '待确认',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
    final avatar = CircleAvatar(
      radius: 16,
      backgroundColor: isUser ? AppColors.primarySoft : const Color(0xFFE8F1FF),
      child: isUser
          ? const Icon(Icons.person, size: 18, color: AppColors.primary)
          : const InterviewAvatar(size: 32),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: isUser
            ? [bubble, const SizedBox(width: 8), avatar]
            : [avatar, const SizedBox(width: 8), bubble],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F3),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      message,
      style: const TextStyle(fontSize: 12, color: AppColors.error),
    ),
  );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.controller});
  final InterviewController controller;
  @override
  Widget build(BuildContext context) {
    final target = controller.targetCount;
    final done = controller.completedCount;
    final current = controller.currentQuestionNumber;
    final progress = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                '面试进度',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Text(
                '第 $current / $target 题 · 已完成 $done 题',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFFE3ECF7),
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({
    required this.controller,
    required this.showTextInput,
    required this.textController,
    required this.onMic,
    required this.onSubmit,
    required this.onToggleText,
    required this.onEnd,
    required this.onReport,
    required this.onTestModel,
  });
  final InterviewController controller;
  final bool showTextInput;
  final TextEditingController textController;
  final VoidCallback onMic;
  final VoidCallback onSubmit;
  final VoidCallback onToggleText;
  final VoidCallback onEnd;
  final VoidCallback onReport;
  final VoidCallback onTestModel;

  String get _micLabel {
    switch (controller.phase) {
      case InterviewPhase.speaking:
        return '打断并作答';
      case InterviewPhase.recording:
        return '完成回答';
      case InterviewPhase.transcribing:
        return '正在转写';
      case InterviewPhase.evaluating:
        return 'AI 正在思考';
      case InterviewPhase.awaitingConfirmation:
        return '请确认回答';
      case InterviewPhase.finished:
        return '面试已完成';
      case InterviewPhase.paused:
        return '已暂停';
      default:
        return '点击作答';
    }
  }

  @override
  Widget build(BuildContext context) {
    final finished = controller.isFinished;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final recording = controller.phase == InterviewPhase.recording;
    final busy =
        controller.phase == InterviewPhase.transcribing ||
        controller.phase == InterviewPhase.evaluating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showTextInput && !finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: textController,
                minLines: 2,
                maxLines: 3,
                onChanged: controller.editPendingAnswer,
                decoration: const InputDecoration(
                  hintText: '输入你的回答文字…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      (!controller.canRecord && !controller.hasPendingAnswer)
                      ? null
                      : onToggleText,
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                  label: const Text('文字回答'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: finished
                      ? onReport
                      : (recording || busy ? null : onEnd),
                  icon: Icon(
                    finished ? Icons.assessment_outlined : Icons.flag_outlined,
                    size: 18,
                  ),
                  label: Text(finished ? '查看报告' : '结束面试'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.hasPendingAnswer && !finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: controller.canSubmit ? onSubmit : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('确认提交回答'),
                ),
              ),
            ),
          if (!finished && !keyboard)
            Semantics(
              button: true,
              label: _micLabel,
              child: GestureDetector(
                key: const ValueKey('interview-mic'),
                onTap:
                    (controller.canRecord ||
                        recording ||
                        controller.phase == InterviewPhase.speaking)
                    ? onMic
                    : null,
                child: Container(
                  width: 84,
                  height: 84,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: recording
                          ? const [Color(0xFFF97316), Color(0xFFEA580C)]
                          : const [Color(0xFF60A5FA), Color(0xFF2563EB)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (recording ? Colors.orange : AppColors.primary)
                            .withValues(alpha: .35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    recording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (!keyboard)
            Text(
              _micLabel,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          if (controller.phase == InterviewPhase.failed)
            TextButton(onPressed: controller.retry, child: const Text('重试')),
          if (!finished && !busy && controller.phase != InterviewPhase.failed)
            TextButton(
              onPressed: controller.phase == InterviewPhase.paused
                  ? controller.resumeFromPause
                  : controller.pause,
              child: Text(
                controller.phase == InterviewPhase.paused ? '继续面试' : '暂停面试',
              ),
            ),
          if (!controller.voiceAvailable && !finished && !keyboard)
            TextButton.icon(
              onPressed: onTestModel,
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('准备离线识别模型', style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
