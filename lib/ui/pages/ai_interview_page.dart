import 'package:flutter/material.dart';

import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/llm_provider_config.dart';
import '../../generator/ai_interview_service.dart';
import '../../generator/video_interview_capture_service.dart';
import '../theme/app_theme.dart';

// ========== AI 面试官页面 ==========
// 基于已生成练习题，提供文字面试和视频面试两种练习方式。

class AiInterviewPage extends StatefulWidget {
  const AiInterviewPage({
    this.authRepository,
    this.aiGenerationRepository,
    this.llmConfigRepository,
    this.interviewService,
    this.videoCaptureService,
    super.key,
  });

  final AuthRepository? authRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiInterviewService? interviewService;
  final VideoInterviewCaptureService? videoCaptureService;

  @override
  State<AiInterviewPage> createState() => _AiInterviewPageState();
}

class _AiInterviewPageState extends State<AiInterviewPage> {
  late final AuthRepository _authRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiInterviewService _interviewService;
  late final VideoInterviewCaptureService _videoCaptureService;
  late Future<_InterviewSessionData> _future;
  final TextEditingController _answerController = TextEditingController();
  bool _isSubmitting = false;
  bool _isVideoMode = false;
  bool _isPreparingCamera = false;
  CapturedVideoAnswer? _capturedVideo;
  VideoInterviewCameraSession? _cameraSession;
  AiInterviewFeedback? _feedback;

  @override
  void initState() {
    super.initState();
    _authRepository = widget.authRepository ?? AuthRepository();
    _aiGenerationRepository =
        widget.aiGenerationRepository ?? AiGenerationRepository();
    _llmConfigRepository = widget.llmConfigRepository ?? LlmConfigRepository();
    _interviewService = widget.interviewService ?? AiInterviewService();
    _videoCaptureService =
        widget.videoCaptureService ?? VideoInterviewCaptureService();
    _future = _loadSession();
  }

  @override
  void dispose() {
    _cameraSession?.dispose();
    _answerController.dispose();
    super.dispose();
  }

  Future<_InterviewSessionData> _loadSession() async {
    final user = await _authRepository.getCurrentUserProfile();
    if (user == null) {
      return const _InterviewSessionData.notReady('请先登录后再开始面试练习');
    }

    final config = await _llmConfigRepository.getByUserId(user.id);
    if (config == null || !config.isConfigured) {
      return const _InterviewSessionData.notReady('请先在“我的”页面配置 AI 模型，再开始面试练习');
    }

    final questions = await _aiGenerationRepository
        .fetchPracticeQuestionsByUser(userId: user.id, limit: 100);
    if (questions.isEmpty) {
      return const _InterviewSessionData.notReady('请先生成练习题，再回来进行 AI 面试练习');
    }

    return _InterviewSessionData.ready(
      config: config,
      question: _pickInterviewQuestion(questions),
    );
  }

  PracticeQuestionWithDocument _pickInterviewQuestion(
    List<PracticeQuestionWithDocument> questions,
  ) {
    for (final item in questions) {
      if (item.question.questionKind == PracticeQuestionKind.oral ||
          item.question.questionKind == PracticeQuestionKind.shortAnswer ||
          item.question.questionKind == PracticeQuestionKind.errorAnalysis) {
        return item;
      }
    }
    return questions.first;
  }

  Future<void> _submit(_InterviewSessionData data) async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || data.question == null || data.config == null) {
      return;
    }

    setState(() {
      _isSubmitting = true;
      _feedback = null;
    });

    try {
      final feedback = await _interviewService.evaluateAnswer(
        question: data.question!,
        userAnswer: answer,
        config: data.config!,
      );
      if (!mounted) return;
      setState(() => _feedback = feedback);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('面试评分失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _ensureCameraSession() async {
    if (_cameraSession != null || _isPreparingCamera) {
      return;
    }
    setState(() => _isPreparingCamera = true);
    try {
      final session = await _videoCaptureService.createSession();
      await session.initialize();
      if (!mounted) {
        await session.dispose();
        return;
      }
      setState(() => _cameraSession = session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('摄像头初始化失败：$error')));
    } finally {
      if (mounted) {
        setState(() => _isPreparingCamera = false);
      }
    }
  }

  Future<void> _toggleVideoRecording() async {
    await _ensureCameraSession();
    final session = _cameraSession;
    if (session == null) {
      return;
    }

    try {
      if (session.isRecording) {
        final captured = await session.stopRecording();
        if (!mounted) return;
        setState(() => _capturedVideo = captured);
      } else {
        await session.startRecording();
        if (!mounted) return;
        setState(() => _capturedVideo = null);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('视频录制失败：$error')));
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _nextQuestion() {
    setState(() {
      _answerController.clear();
      _feedback = null;
      _capturedVideo = null;
      _future = _loadSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 面试官')),
      body: FutureBuilder<_InterviewSessionData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          final data =
              snapshot.data ??
              _InterviewSessionData.notReady(
                snapshot.error?.toString() ?? '面试暂时不可用',
              );
          if (!data.isReady) {
            return _EmptyState(message: data.message);
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _InterviewModeSelector(
                isVideoMode: _isVideoMode,
                onChanged: (value) {
                  setState(() {
                    _isVideoMode = value;
                    _feedback = null;
                  });
                  if (value) {
                    _ensureCameraSession();
                  }
                },
              ),
              const SizedBox(height: 14),
              if (_isVideoMode) ...[
                _VideoInterviewPanel(
                  cameraSession: _cameraSession,
                  capturedVideo: _capturedVideo,
                  isPreparingCamera: _isPreparingCamera,
                  onToggleRecording: _toggleVideoRecording,
                ),
                const SizedBox(height: 14),
              ],
              _QuestionCard(question: data.question!),
              const SizedBox(height: 14),
              TextField(
                controller: _answerController,
                minLines: 5,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: _isVideoMode ? '口述答案转写' : '你的答案',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : () => _submit(data),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic_rounded),
                label: Text(
                  _isSubmitting
                      ? '正在评分'
                      : _isVideoMode
                      ? '提交视频答案'
                      : '提交答案',
                ),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 14),
                _FeedbackCard(feedback: _feedback!),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _nextQuestion,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('下一题'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ========== Session Data ==========

class _InterviewSessionData {
  const _InterviewSessionData._({
    required this.isReady,
    required this.message,
    this.config,
    this.question,
  });

  const _InterviewSessionData.ready({
    required LlmProviderConfig config,
    required PracticeQuestionWithDocument question,
  }) : this._(isReady: true, message: '', config: config, question: question);

  const _InterviewSessionData.notReady(String message)
    : this._(isReady: false, message: message);

  final bool isReady;
  final String message;
  final LlmProviderConfig? config;
  final PracticeQuestionWithDocument? question;
}

// ========== Presentation Widgets ==========

class _InterviewModeSelector extends StatelessWidget {
  const _InterviewModeSelector({
    required this.isVideoMode,
    required this.onChanged,
  });

  final bool isVideoMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          icon: Icon(Icons.edit_note_rounded),
          label: Text('文字面试'),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(Icons.videocam_rounded),
          label: Text('视频面试'),
        ),
      ],
      selected: {isVideoMode},
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

class _VideoInterviewPanel extends StatelessWidget {
  const _VideoInterviewPanel({
    required this.cameraSession,
    required this.capturedVideo,
    required this.isPreparingCamera,
    required this.onToggleRecording,
  });

  final VideoInterviewCameraSession? cameraSession;
  final CapturedVideoAnswer? capturedVideo;
  final bool isPreparingCamera;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final isRecording = cameraSession?.isRecording ?? false;
    final isReady = cameraSession?.isInitialized ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.smart_toy_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 视频面试官',
                      style: AppTextStyles.body(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '看着镜头回答问题，结束后提交口述转写，AI 会按知识点评分并纠正。',
                      style: AppTextStyles.caption(
                        context,
                      ).copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white24),
              ),
              child: Center(
                child: isReady
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: 360,
                              height: 220,
                              child: cameraSession!.buildPreview(),
                            ),
                          ),
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPreparingCamera
                                ? Icons.hourglass_top_rounded
                                : Icons.videocam_off_rounded,
                            color: Colors.white70,
                            size: 36,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPreparingCamera ? '正在打开摄像头' : '摄像头预览等待启动',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall(
                              context,
                            ).copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _RecordingPill(isRecording: isRecording),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  capturedVideo == null
                      ? '尚未保存本题视频答案'
                      : '已保存：${capturedVideo!.name}',
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isPreparingCamera ? null : onToggleRecording,
              icon: isPreparingCamera
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isRecording
                          ? Icons.stop_circle_rounded
                          : Icons.fiber_manual_record_rounded,
                    ),
              label: Text(
                isPreparingCamera
                    ? '正在打开摄像头'
                    : isRecording
                    ? '结束作答'
                    : '开始作答',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordingPill extends StatelessWidget {
  const _RecordingPill({required this.isRecording});

  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isRecording ? const Color(0xFFDC2626) : Colors.white12,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRecording
                  ? Icons.fiber_manual_record_rounded
                  : Icons.pause_circle_outline_rounded,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              isRecording ? '录制中' : '待作答',
              style: AppTextStyles.caption(
                context,
              ).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.question});

  final PracticeQuestionWithDocument question;

  @override
  Widget build(BuildContext context) {
    final record = question.question;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.documentTitle,
            style: AppTextStyles.caption(context).copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(record.questionText, style: AppTextStyles.h2(context)),
          if (record.options.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final option in record.options)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(option, style: AppTextStyles.body(context)),
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: record.questionKind),
              if ((record.difficulty ?? '').isNotEmpty)
                _MetaChip(label: record.difficulty!),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});

  final AiInterviewFeedback feedback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.primarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('得分 ${feedback.score}/100', style: AppTextStyles.h2(context)),
          const SizedBox(height: 12),
          _FeedbackSection(title: '已答对要点', items: feedback.hitPoints),
          _FeedbackSection(title: '缺漏要点', items: feedback.missingPoints),
          _FeedbackSection(title: '可能误区', items: feedback.misconceptions),
          _TextBlock(title: '纠正建议', text: feedback.correction),
          _TextBlock(title: '标准答案', text: feedback.standardAnswer),
          _TextBlock(title: '追问', text: feedback.nextFollowUp),
        ],
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.caption(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Text('- $item', style: AppTextStyles.bodySmall(context)),
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.caption(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(text, style: AppTextStyles.bodySmall(context)),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: AppTextStyles.caption(
            context,
          ).copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTextStyles.body(context).copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
