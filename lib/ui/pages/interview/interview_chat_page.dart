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
import '../../../interview/interview_failure.dart';
import '../../../interview/speech/interview_speech.dart';
import '../../theme/app_theme.dart';
import '../../widgets/premium_app_chrome.dart';
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
    this.preparationRoute,
    super.key,
  });

  final int userId;
  final int sessionId;
  final InterviewController? controller;

  /// 可注入的语音实现；为空时才创建离线语音服务。
  final InterviewVoicePort? voice;
  final InterviewRepository? repository;
  final AppDatabase? database;
  final Route<dynamic>? preparationRoute;

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
  String? _downloadError;
  bool _newMessages = false;
  int _messageCount = 0;
  bool _reportOpened = false;
  bool _micBusy = false;
  bool _leaving = false;
  bool _allowPop = false;

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
      _controller?.removeListener(_onChanged);
      if (widget.controller == null) _controller?.dispose();
      _controller = controller..addListener(_onChanged);
      setState(() => _starting = false);
      await controller.resume();
      _scrollToBottom(force: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _starting = false;
          _loadError = interviewFailure(error, fallback: '读取失败，请重试');
        });
      }
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    final controller = _controller;
    if (controller != null) {
      if (controller.isFinished && !_reportOpened) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openReport();
        });
      }
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
    setState(() {
      _downloadProgress = 0;
      _downloadError = null;
    });
    try {
      await controller.voice.ensureOfflineModel(
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (mounted) _toast(controller.voice.modelReady ? '离线识别模型已就绪' : '模型尚未就绪');
    } catch (error) {
      if (mounted) {
        if (error is VoiceCancelled) {
          _toast(interviewModelDownloadFailure(error));
        } else {
          setState(() => _downloadError = interviewModelDownloadFailure(error));
        }
      }
    } finally {
      if (mounted) setState(() => _downloadProgress = null);
    }
  }

  /// 语音服务不可用时降级为纯文字面试，而不是让整场面试无法开始。
  Future<InterviewVoicePort> _createVoice(InterviewSession session) async {
    try {
      // 平台目录查询在异常环境下可能不返回，超时后按无麦克风降级。
      final creating = createOfflineInterviewVoiceService(
        settings: VoiceSettings(
          volume: session.voiceVolume,
          rate: session.voiceRate,
        ),
      );
      try {
        return await creating.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        unawaited(
          creating.then((voice) => voice.dispose(), onError: (Object _) {}),
        );
        rethrow;
      }
    } catch (error) {
      if (mounted) _toast('语音暂不可用，可用文字回答');
      return NoopInterviewVoice();
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );

  Future<void> _micPressed() async {
    if (_micBusy) return;
    _micBusy = true;
    try {
      await _handleMic();
    } finally {
      _micBusy = false;
    }
  }

  Future<void> _handleMic() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.voice is NoopInterviewVoice) {
      _toast('语音暂不可用，请用文字回答');
      if (!_showTextInput) await _toggleText();
      return;
    }
    if (controller.phase == InterviewPhase.speaking) {
      await controller.interruptSpeech();
      if (!mounted) return;
    }
    if (controller.phase == InterviewPhase.recording) {
      await controller.stopRecording();
    } else if (controller.canRecord) {
      if (!controller.voiceAvailable) {
        if (!mounted) return;
        final download = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('准备语音识别'),
            content: const Text('首次使用需下载约 24 MB，之后可离线识别。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('下载'),
              ),
            ],
          ),
        );
        if (download != true || !mounted) return;
        await _checkModel();
        if (!mounted || !controller.voiceAvailable || !controller.canRecord) {
          return;
        }
      }
      await controller.beginRecording();
    }
  }

  Future<void> _submit() async {
    final controller = _controller;
    if (controller == null) return;
    FocusScope.of(context).unfocus();
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
    if (confirmed == true && mounted) {
      await controller.endEarly();
      if (mounted) await _openReport();
    }
  }

  Future<void> _openReport() async {
    final controller = _controller;
    if (controller == null) return;
    if (!controller.isFinished || _reportOpened || _leaving) return;
    _reportOpened = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => InterviewResultPage(
          userId: widget.userId,
          sessionId: widget.sessionId,
          repository: widget.repository,
          database: widget.database,
          preparationRoute: widget.preparationRoute,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final recording =
        controller?.phase == InterviewPhase.recording ||
        controller?.phase == InterviewPhase.transcribing;
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _leaving) return;
        _leaving = true;
        if (recording) {
          final leave = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('保存回答并退出？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('继续面试'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('保存并退出'),
                ),
              ],
            ),
          );
          if (leave != true || !mounted) {
            _leaving = false;
            return;
          }
        }
        await controller?.pause();
        await controller?.savePendingAnswer();
        if (!mounted) return;
        if (controller?.draftSaveFailed ?? false) {
          _leaving = false;
          _toast('回答未保存，请重试后退出');
          return;
        }
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI 语音面试'),
          actions: [
            PopupMenuButton<String>(
              tooltip: '面试操作',
              enabled:
                  controller != null &&
                  !controller.isFinished &&
                  controller.phase != InterviewPhase.evaluating &&
                  controller.phase != InterviewPhase.transcribing &&
                  controller.phase != InterviewPhase.generatingQuestions &&
                  controller.phase != InterviewPhase.preparing,
              onSelected: (value) async {
                if (value == 'end') {
                  await _endInterview();
                } else if (controller?.phase == InterviewPhase.paused) {
                  await controller?.resumeFromPause();
                } else {
                  await controller?.pause();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'pause',
                  child: Text(
                    controller?.phase == InterviewPhase.paused
                        ? '继续面试'
                        : '暂停面试',
                  ),
                ),
                const PopupMenuItem(value: 'end', child: Text('结束面试')),
              ],
            ),
          ],
        ),
        body: PremiumPageBackground(child: SafeArea(child: _body(controller))),
      ),
    );
  }

  Widget _body(InterviewController? controller) {
    if (_starting || controller == null || _loadError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loadError == null) const CircularProgressIndicator(),
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
        _SourceBar(session: controller.session),
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
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () => _scrollToBottom(force: true),
                    child: const Text('查看新消息'),
                  ),
                ),
            ],
          ),
        ),
        if (controller.error != null) _ErrorBanner(message: controller.error!),
        if (_downloadError != null) ...[
          _ErrorBanner(message: _downloadError!),
          TextButton(onPressed: _checkModel, child: const Text('重新下载语音模型')),
        ],
        if (_downloadProgress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(value: _downloadProgress),
                ),
                const SizedBox(width: 8),
                Text('${(_downloadProgress! * 100).floor()}%'),
                TextButton(
                  onPressed: () async {
                    try {
                      await controller.voice.cancel();
                    } catch (error) {
                      if (mounted) _toast('取消失败，请重试');
                    }
                  },
                  child: const Text('取消下载'),
                ),
              ],
            ),
          ),
        _BottomControls(
          controller: controller,
          showTextInput: _showTextInput,
          textController: _textAnswer,
          onMic: _downloadProgress == null ? _micPressed : null,
          onSubmit: _submit,
          onToggleText: _toggleText,
          onDiscard: () async {
            await controller.cancelRecording();
            if (mounted) setState(() => _showTextInput = false);
            _textAnswer.clear();
          },
          onReport: _openReport,
        ),
      ],
    );
  }
}

class _SourceBar extends StatelessWidget {
  const _SourceBar({required this.session});
  final InterviewSession session;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
    child: Row(
      children: [
        const Icon(
          Icons.menu_book_outlined,
          size: 18,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            session.scopeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall(context),
          ),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF2F8FF), Colors.white],
        ),
        borderRadius: BorderRadius.circular(AppRadii.cardSmall),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          InterviewAvatar(
            mood: _mood,
            mouthActivity: controller.voice.mouthActivity,
            size: 96,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI 面试官',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _status,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
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
            message.text.isEmpty ? (live ? '等待回答…' : '') : message.text,
            style: AppTextStyles.body(context).copyWith(fontSize: 15),
          ),
          if (live)
            Text(
              controller.phase == InterviewPhase.recording
                  ? '正在录音…'
                  : controller.phase == InterviewPhase.transcribing
                  ? '正在转写…'
                  : '待提交',
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
    return Column(
      children: [
        Row(
          children: [
            const Text(
              '面试进度',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              '第 $current / $target 题',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: const Color(0xFFE3ECF7),
            color: AppColors.primary,
          ),
        ),
      ],
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
    required this.onReport,
    required this.onDiscard,
  });
  final InterviewController controller;
  final bool showTextInput;
  final TextEditingController textController;
  final VoidCallback? onMic;
  final VoidCallback onSubmit, onToggleText, onReport, onDiscard;

  String get _micLabel => switch (controller.phase) {
    InterviewPhase.speaking => '打断并作答',
    InterviewPhase.recording => '结束回答',
    InterviewPhase.transcribing => '正在转写…',
    InterviewPhase.evaluating => '正在评分…',
    InterviewPhase.generatingQuestions || InterviewPhase.preparing => '正在出题…',
    _ => '点击作答',
  };

  @override
  Widget build(BuildContext context) {
    final recording = controller.phase == InterviewPhase.recording;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canMic =
        controller.canRecord ||
        (recording && !controller.recordingStarting) ||
        controller.phase == InterviewPhase.speaking;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.sheet),
        ),
        boxShadow: AppShadows.navList,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!controller.isFinished) ...[
            _ProgressBar(controller: controller),
            const SizedBox(height: 12),
          ],
          if (showTextInput && controller.hasPendingAnswer) ...[
            TextField(
              controller: textController,
              minLines: 1,
              maxLines: 2,
              onChanged: controller.editPendingAnswer,
              decoration: const InputDecoration(hintText: '输入或修改回答'),
            ),
            const SizedBox(height: 8),
          ],
          if (controller.isFinished)
            FilledButton(onPressed: onReport, child: const Text('查看结果'))
          else if (controller.phase == InterviewPhase.failed)
            FilledButton(onPressed: controller.retry, child: const Text('重试'))
          else if (controller.phase == InterviewPhase.paused)
            FilledButton(
              onPressed: controller.pausing ? null : controller.resumeFromPause,
              child: Text(controller.pausing ? '正在暂停…' : '继续面试'),
            )
          else if (controller.hasPendingAnswer)
            Row(
              children: [
                IconButton(
                  onPressed: onDiscard,
                  tooltip: '重新作答',
                  icon: const Icon(Icons.refresh_rounded),
                ),
                TextButton(onPressed: onToggleText, child: const Text('文字回答')),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: controller.canSubmit ? onSubmit : null,
                    child: const Text('提交回答'),
                  ),
                ),
              ],
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SideAction(
                  icon: Icons.keyboard_alt_outlined,
                  label: '文字回答',
                  onTap: controller.canRecord ? onToggleText : null,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!keyboard)
                      Semantics(
                        button: true,
                        enabled: canMic,
                        label: _micLabel,
                        child: SizedBox.square(
                          dimension: 64,
                          child: FilledButton(
                            key: const ValueKey('interview-mic'),
                            onPressed: canMic ? onMic : null,
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: EdgeInsets.zero,
                              backgroundColor: recording
                                  ? AppColors.error
                                  : AppColors.primary,
                            ),
                            child: Icon(
                              recording
                                  ? Icons.stop_rounded
                                  : Icons.mic_rounded,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(_micLabel, style: AppTextStyles.caption(context)),
                  ],
                ),
                _SideAction(
                  icon: Icons.volume_up_outlined,
                  label: '重听问题',
                  onTap: controller.canRecord && controller.session.voiceEnabled
                      ? controller.replayQuestion
                      : null,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 72,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onTap,
          tooltip: label,
          icon: Icon(icon, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surfaceAlt,
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textTertiary,
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption(context),
        ),
      ],
    ),
  );
}
