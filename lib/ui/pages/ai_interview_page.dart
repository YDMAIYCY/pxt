import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../database/ai_generation_repository.dart';
import '../../database/auth_repository.dart';
import '../../database/llm_config_repository.dart';
import '../../database/models/ai_result_records.dart';
import '../../database/models/llm_provider_config.dart';
import '../../generator/ai_interview_service.dart';
import '../../generator/cloud_speech_transcription_service.dart';
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
    this.cloudSpeechService,
    this.libraryId,
    this.libraryName,
    super.key,
  });

  final AuthRepository? authRepository;
  final AiGenerationRepository? aiGenerationRepository;
  final LlmConfigRepository? llmConfigRepository;
  final AiInterviewService? interviewService;
  final VideoInterviewCaptureService? videoCaptureService;
  final CloudSpeechTranscriptionService? cloudSpeechService;
  final int? libraryId;
  final String? libraryName;

  @override
  State<AiInterviewPage> createState() => _AiInterviewPageState();
}

class _AiInterviewPageState extends State<AiInterviewPage> {
  late final AuthRepository _authRepository;
  late final AiGenerationRepository _aiGenerationRepository;
  late final LlmConfigRepository _llmConfigRepository;
  late final AiInterviewService _interviewService;
  late final VideoInterviewCaptureService _videoCaptureService;
  late final CloudSpeechTranscriptionService _cloudSpeechService;
  late final AudioRecorder _cloudAudioRecorder;
  late final SpeechToText _speechToText;
  late Future<_InterviewSessionData> _future;
  final TextEditingController _answerController = TextEditingController();
  Future<void> _cloudTranscriptionQueue = Future.value();
  Timer? _cloudSegmentTimer;
  bool _isSubmitting = false;
  bool _isPreparingCamera = false;
  bool _isPreparingSpeech = false;
  bool _isListening = false;
  bool _isCloudRecording = false;
  bool _isCloudTranscribing = false;
  bool _isRotatingCloudSegment = false;
  bool _interviewStarted = false;
  bool _isAnswering = false;
  CapturedVideoAnswer? _capturedVideo;
  VideoInterviewCameraSession? _cameraSession;
  AiInterviewFeedback? _feedback;
  PracticeQuestionWithDocument? _followUpQuestion;
  LlmProviderConfig? _cloudTranscriptionConfig;
  String _speechBaseText = '';
  String _speechStatusText = '等待回答';
  final List<String> _cloudTranscriptSegments = <String>[];
  int _followUpRound = 0;

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
    _cloudSpeechService =
        widget.cloudSpeechService ?? CloudSpeechTranscriptionService();
    _cloudAudioRecorder = AudioRecorder();
    _speechToText = SpeechToText();
    _future = _loadSession();
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _cloudSegmentTimer?.cancel();
    _cloudAudioRecorder.dispose();
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
        .fetchPracticeQuestionsByUser(
          userId: user.id,
          libraryId: widget.libraryId,
          limit: 100,
        );
    if (questions.isEmpty) {
      return _InterviewSessionData.notReady(
        widget.libraryName == null
            ? '请先生成练习题，再回来进行 AI 面试练习'
            : '这个知识库还没有可用于面试的练习题',
      );
    }

    return _InterviewSessionData.ready(
      config: config,
      question: _pickInterviewQuestion(questions),
    );
  }

  PracticeQuestionWithDocument _pickInterviewQuestion(
    List<PracticeQuestionWithDocument> questions,
  ) {
    final preferred = questions
        .where(
          (item) =>
              item.question.questionKind == PracticeQuestionKind.oral ||
              item.question.questionKind == PracticeQuestionKind.shortAnswer ||
              item.question.questionKind == PracticeQuestionKind.errorAnalysis,
        )
        .toList(growable: false);
    final pool = preferred.isEmpty ? questions : preferred;
    return pool[Random().nextInt(pool.length)];
  }

  Future<void> _submit(_InterviewSessionData data) async {
    if (_isAnswering || _isListening) {
      await _finishAnswering();
    }
    if (_isCloudTranscribing) {
      await _cloudTranscriptionQueue;
    }
    final answer = _answerController.text.trim();
    if (answer.isEmpty || data.question == null || data.config == null) {
      return;
    }
    final activeQuestion = _currentQuestion(data);

    setState(() {
      _isSubmitting = true;
      _feedback = null;
    });

    try {
      final feedback = await _interviewService.evaluateAnswer(
        question: activeQuestion,
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
      final session = await _videoCaptureService.createSession(
        enableAudio: false,
      );
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

  Future<void> _beginInterview() async {
    setState(() {
      _interviewStarted = true;
      _feedback = null;
      _followUpQuestion = null;
      _followUpRound = 0;
    });
    await _ensureCameraSession();
  }

  Future<void> _startAnswering(_InterviewSessionData data) async {
    setState(() {
      _isAnswering = true;
      _feedback = null;
      _capturedVideo = null;
    });
    await _ensureCameraSession();
    final speechStarted = await _startSpeechTranscription();
    final config = data.config;
    if (!speechStarted && config != null) {
      final cloudStarted = await _startCloudTranscription(config);
      if (!cloudStarted && mounted) {
        setState(() => _isAnswering = false);
      }
    } else if (!speechStarted && mounted) {
      setState(() => _isAnswering = false);
    }
    if (mounted) setState(() {});
  }

  Future<void> _finishAnswering() async {
    await _stopSpeechTranscription();
    await _stopCloudTranscription();
    final session = _cameraSession;
    CapturedVideoAnswer? captured;
    if (session != null && session.isRecording) {
      try {
        captured = await session.stopRecording();
      } catch (_) {
        captured = null;
      }
    }
    if (!mounted) return;
    setState(() {
      _isAnswering = false;
      _capturedVideo = captured ?? _capturedVideo;
    });
  }

  Future<bool> _startSpeechTranscription() async {
    if (_isListening || _isPreparingSpeech) return true;
    setState(() => _isPreparingSpeech = true);
    try {
      final available = await _speechToText.initialize(
        options: [
          SpeechToText.androidNoBluetooth,
          SpeechToText.androidIntentLookup,
        ],
        debugLogging: true,
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _speechStatusText = _speechStatusLabel(status);
          });
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _isListening = false;
            _speechStatusText = _speechErrorMessage(error.errorMsg);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_speechErrorMessage(error.errorMsg))),
          );
        },
      );
      if (!available) {
        if (mounted) {
          setState(() {
            _speechStatusText = '当前设备没有可用的系统语音识别服务';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('当前设备没有可用的系统语音识别服务，请检查语音服务和麦克风权限')),
          );
        }
        return false;
      }

      final localeId = await _preferredSpeechLocale();
      _speechBaseText = _answerController.text.trim();
      await _speechToText.listen(
        onResult: _handleSpeechResult,
        onSoundLevelChange: (level) {
          if (!mounted) return;
          if (level > 0 && _speechStatusText != '检测到声音，正在转写') {
            setState(() => _speechStatusText = '检测到声音，正在转写');
          }
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          autoPunctuation: true,
          listenFor: const Duration(seconds: 90),
          pauseFor: const Duration(seconds: 8),
          localeId: localeId,
        ),
      );
      if (mounted) {
        setState(() {
          _isListening = true;
          _speechStatusText = '正在实时转写到回答框';
        });
      }
      return true;
    } catch (error) {
      final message = _speechExceptionMessage(error);
      if (mounted) {
        setState(() => _speechStatusText = message);
        if (!_isRecognizerUnavailable(error)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
      return false;
    } finally {
      if (mounted) setState(() => _isPreparingSpeech = false);
    }
  }

  Future<void> _stopSpeechTranscription() async {
    if (!_isListening && !_speechToText.isListening) return;
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListening = false;
        _speechStatusText = '已结束回答';
      });
    }
  }

  Future<bool> _startCloudTranscription(LlmProviderConfig config) async {
    if (_isCloudRecording) return true;
    try {
      final hasPermission = await _cloudAudioRecorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          setState(() => _speechStatusText = '请允许麦克风权限后再开始语音回答');
        }
        return false;
      }

      _speechBaseText = _answerController.text.trim();
      _cloudTranscriptionConfig = config;
      _cloudTranscriptSegments.clear();
      await _startCloudAudioSegment();
      _cloudSegmentTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _rotateCloudAudioSegment(config),
      );
      if (mounted) {
        setState(() {
          _isCloudRecording = true;
          _speechStatusText = '系统语音不可用，已切换为云端实时转写';
        });
      }
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _speechStatusText = '云端语音转写启动失败：$error');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('云端语音转写启动失败：$error')));
      }
      return false;
    }
  }

  Future<void> _startCloudAudioSegment() async {
    final tempDir = await getTemporaryDirectory();
    final path =
        '${tempDir.path}${Platform.pathSeparator}'
        'ai_interview_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _cloudAudioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 16000,
        bitRate: 64000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  Future<void> _rotateCloudAudioSegment(LlmProviderConfig config) async {
    if (!_isCloudRecording || _isRotatingCloudSegment) return;
    _isRotatingCloudSegment = true;
    try {
      final path = await _cloudAudioRecorder.stop();
      await _startCloudAudioSegment();
      if (path != null && path.isNotEmpty) {
        _enqueueCloudTranscription(path: path, config: config);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _speechStatusText = '云端语音分片失败：$error');
      }
    } finally {
      _isRotatingCloudSegment = false;
    }
  }

  Future<void> _stopCloudTranscription() async {
    _cloudSegmentTimer?.cancel();
    _cloudSegmentTimer = null;
    if (!_isCloudRecording) return;

    String? path;
    try {
      path = await _cloudAudioRecorder.stop();
    } catch (_) {
      path = null;
    }
    if (mounted) {
      setState(() {
        _isCloudRecording = false;
        _speechStatusText = '正在整理最后一段语音';
      });
    }
    if (path != null && path.isNotEmpty) {
      final config = _cloudTranscriptionConfig;
      if (config != null) {
        _enqueueCloudTranscription(path: path, config: config);
      }
    }
    await _cloudTranscriptionQueue;
    if (mounted) {
      setState(() {
        _isCloudTranscribing = false;
        _speechStatusText = '已结束回答';
      });
    }
  }

  void _enqueueCloudTranscription({
    required String path,
    required LlmProviderConfig config,
  }) {
    _cloudTranscriptionQueue = _cloudTranscriptionQueue.then((_) async {
      if (mounted) {
        setState(() {
          _isCloudTranscribing = true;
          _speechStatusText = '正在云端转写语音';
        });
      }
      try {
        final text = await _cloudSpeechService.transcribeAudioFile(
          audioPath: path,
          config: config,
        );
        if (text.trim().isNotEmpty) {
          _cloudTranscriptSegments.add(text.trim());
          _syncCloudTranscriptToAnswer();
        }
      } catch (error) {
        if (mounted) {
          setState(() => _speechStatusText = error.toString());
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      } finally {
        unawaited(_deleteTempAudio(path));
        if (mounted) {
          setState(() => _isCloudTranscribing = false);
        }
      }
    });
  }

  void _syncCloudTranscriptToAnswer() {
    final text = _cloudTranscriptSegments.join('\n').trim();
    if (text.isEmpty) return;
    final merged = _speechBaseText.isEmpty ? text : '$_speechBaseText\n$text';
    _answerController.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(offset: merged.length),
    );
    if (mounted) {
      setState(() => _speechStatusText = '云端已转写 ${text.runes.length} 个字');
    }
  }

  Future<void> _deleteTempAudio(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Temporary audio cleanup is best-effort.
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    final words = result.recognizedWords.trim();
    if (words.isEmpty) return;
    final merged = _speechBaseText.isEmpty ? words : '$_speechBaseText\n$words';
    _answerController.value = TextEditingValue(
      text: merged,
      selection: TextSelection.collapsed(offset: merged.length),
    );
    if (mounted) {
      setState(() => _speechStatusText = '已转写 ${words.runes.length} 个字');
    }
  }

  Future<String> _preferredSpeechLocale() async {
    final systemLocale = await _speechToText.systemLocale();
    final localeId = systemLocale?.localeId;
    if (localeId == null || localeId.isEmpty) {
      return 'zh-CN';
    }
    return localeId.replaceAll('_', '-');
  }

  String _speechStatusLabel(String status) {
    return switch (status) {
      'listening' => '正在听你回答',
      'notListening' => '语音识别已暂停',
      'done' => '语音识别已结束',
      _ => '语音状态：$status',
    };
  }

  String _speechErrorMessage(String code) {
    return switch (code) {
      'error_permission' => '语音转写失败：请在系统设置里允许拍学通使用麦克风',
      'error_network' || 'error_network_timeout' => '语音转写失败：请检查网络或系统语音识别服务',
      'error_no_match' || 'error_speech_timeout' => '没有识别到清晰语音，请靠近麦克风后重试',
      'error_busy' => '麦克风暂时被占用，请退出其他录音或通话应用后重试',
      _ => '语音转写失败：$code',
    };
  }

  String _speechExceptionMessage(Object error) {
    if (_isRecognizerUnavailable(error)) {
      return '系统语音识别不可用，正在切换云端转写';
    }
    return '语音转写启动失败：$error';
  }

  bool _isRecognizerUnavailable(Object error) {
    return error is PlatformException && error.code == 'recognizerNotAvailable';
  }

  PracticeQuestionWithDocument _currentQuestion(_InterviewSessionData data) {
    return _followUpQuestion ?? data.question!;
  }

  void _nextQuestion(_InterviewSessionData data) {
    final followUp = _feedback?.nextFollowUp.trim() ?? '';
    if (followUp.isNotEmpty && data.question != null) {
      final base = _currentQuestion(data);
      setState(() {
        _answerController.clear();
        _feedback = null;
        _capturedVideo = null;
        _isAnswering = false;
        _interviewStarted = true;
        _followUpRound++;
        _followUpQuestion = _buildFollowUpQuestion(base, followUp);
      });
      return;
    }

    setState(() {
      _answerController.clear();
      _feedback = null;
      _capturedVideo = null;
      _isAnswering = false;
      _interviewStarted = false;
      _followUpQuestion = null;
      _followUpRound = 0;
      _future = _loadSession();
    });
  }

  PracticeQuestionWithDocument _buildFollowUpQuestion(
    PracticeQuestionWithDocument base,
    String followUp,
  ) {
    final question = base.question;
    return PracticeQuestionWithDocument(
      documentTitle: '${base.documentTitle} · 追问 $_followUpRound',
      question: PracticeQuestionRecord(
        id: -DateTime.now().microsecondsSinceEpoch,
        documentId: question.documentId,
        questionText: followUp,
        answerText: question.answerText,
        analysisText: question.analysisText,
        difficulty: question.difficulty,
        reviewStatus: question.reviewStatus,
        wrongCount: question.wrongCount,
        createdAt: DateTime.now(),
        parentQuestionId: question.id,
        questionKind: PracticeQuestionKind.oral,
        optionsJson: question.optionsJson,
        rubricJson: question.rubricJson,
        expectedKeywordsJson: question.expectedKeywordsJson,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryName = widget.libraryName ?? '当前知识库';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text('$libraryName 面试')),
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
          final activeQuestion = _currentQuestion(data);
          final hasFollowUp = _feedback?.nextFollowUp.trim().isNotEmpty == true;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _InterviewRoomPanel(
                libraryName: libraryName,
                question: activeQuestion,
                cameraSession: _cameraSession,
                capturedVideo: _capturedVideo,
                isPreparingCamera: _isPreparingCamera,
                isPreparingSpeech: _isPreparingSpeech,
                isListening: _isListening,
                speechStatusText: _speechStatusText,
                interviewStarted: _interviewStarted,
                isAnswering: _isAnswering,
                onPrepare: _beginInterview,
                onStartAnswer: () => _startAnswering(data),
                onFinishAnswer: _finishAnswering,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _answerController,
                minLines: 5,
                maxLines: 8,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: '回答转写',
                  hintText: '点击“开始回答”后，你说的话会实时出现在这里',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    !_interviewStarted || _isSubmitting || _isCloudTranscribing
                    ? null
                    : () => _submit(data),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic_rounded),
                label: Text(_isSubmitting ? '正在评价' : '提交回答'),
              ),
              if (_feedback != null) ...[
                const SizedBox(height: 14),
                _FeedbackCard(
                  feedback: _feedback!,
                  capturedVideo: _capturedVideo,
                  answerText: _answerController.text,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _nextQuestion(data),
                  icon: const Icon(Icons.skip_next_rounded),
                  label: Text(hasFollowUp ? '进入追问' : '下一题'),
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

class _InterviewRoomPanel extends StatelessWidget {
  const _InterviewRoomPanel({
    required this.libraryName,
    required this.question,
    required this.cameraSession,
    required this.capturedVideo,
    required this.isPreparingCamera,
    required this.isPreparingSpeech,
    required this.isListening,
    required this.speechStatusText,
    required this.interviewStarted,
    required this.isAnswering,
    required this.onPrepare,
    required this.onStartAnswer,
    required this.onFinishAnswer,
  });

  final String libraryName;
  final PracticeQuestionWithDocument question;
  final VideoInterviewCameraSession? cameraSession;
  final CapturedVideoAnswer? capturedVideo;
  final bool isPreparingCamera;
  final bool isPreparingSpeech;
  final bool isListening;
  final String speechStatusText;
  final bool interviewStarted;
  final bool isAnswering;
  final VoidCallback onPrepare;
  final VoidCallback onStartAnswer;
  final VoidCallback onFinishAnswer;

  @override
  Widget build(BuildContext context) {
    final isRecording = cameraSession?.isRecording ?? false;
    final isReady = cameraSession?.isInitialized ?? false;
    final aiLine = interviewStarted
        ? '我们即将开始 $libraryName 的问答。请听题：${question.question.questionText}'
        : '你好，我是你的 AI 面试官。准备好后请说“准备好了”，然后点击下方按钮开始。';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppShadows.cardSoftList,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FacePreview(
                isReady: isReady,
                isPreparingCamera: isPreparingCamera,
                cameraSession: cameraSession,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FCFB),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.volume_up_rounded,
                            color: AppColors.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'AI 面试官',
                            style: AppTextStyles.caption(context).copyWith(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        aiLine,
                        style: AppTextStyles.body(
                          context,
                        ).copyWith(height: 1.45, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _QuestionCard(question: question),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                _RecordingPill(isRecording: isRecording || isAnswering),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    speechStatusText.isEmpty ? _statusText : speechStatusText,
                    maxLines: 3,
                    softWrap: true,
                    style: AppTextStyles.caption(context).copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (!interviewStarted)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isPreparingCamera ? null : onPrepare,
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(isPreparingCamera ? '正在打开摄像头' : '我准备好了'),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isAnswering || isPreparingSpeech
                        ? null
                        : onStartAnswer,
                    icon: const Icon(Icons.mic_rounded),
                    label: Text(isPreparingSpeech ? '启动转写中' : '开始回答'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isAnswering ? onFinishAnswer : null,
                    icon: const Icon(Icons.stop_circle_rounded),
                    label: const Text('结束回答'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String get _statusText {
    if (isPreparingSpeech) return '正在启动语音转写';
    if (isListening) return '正在实时转写到回答框';
    if (isAnswering) return '正在回答';
    if (capturedVideo != null) return '已保存视频片段';
    return '等待回答';
  }
}

class _FacePreview extends StatelessWidget {
  const _FacePreview({
    required this.isReady,
    required this.isPreparingCamera,
    required this.cameraSession,
  });

  final bool isReady;
  final bool isPreparingCamera;
  final VideoInterviewCameraSession? cameraSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 118,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: isReady && cameraSession != null
          ? FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: 118,
                height: 118,
                child: cameraSession!.buildPreview(),
              ),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isPreparingCamera
                      ? Icons.hourglass_top_rounded
                      : Icons.person_rounded,
                  color: Colors.white70,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  isPreparingCamera ? '打开中' : '人脸预览',
                  style: AppTextStyles.caption(
                    context,
                  ).copyWith(color: Colors.white70),
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
  const _FeedbackCard({
    required this.feedback,
    required this.capturedVideo,
    required this.answerText,
  });

  final AiInterviewFeedback feedback;
  final CapturedVideoAnswer? capturedVideo;
  final String answerText;

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
          const SizedBox(height: 6),
          Text(
            '评级：${_scoreLevel(feedback.score)}',
            style: AppTextStyles.bodySmall(context).copyWith(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          _FeedbackSection(title: '已答对要点', items: feedback.hitPoints),
          _FeedbackSection(title: '缺漏要点', items: feedback.missingPoints),
          _FeedbackSection(title: '可能误区', items: feedback.misconceptions),
          _TextBlock(title: '综合表现', text: _presenceFeedback),
          _TextBlock(title: '纠正建议', text: feedback.correction),
          _TextBlock(title: '标准答案', text: feedback.standardAnswer),
          _TextBlock(title: '追问', text: feedback.nextFollowUp),
        ],
      ),
    );
  }

  String _scoreLevel(int score) {
    if (score < 60) return '差';
    if (score < 85) return '良好';
    return '优秀';
  }

  String get _presenceFeedback {
    final answerLength = answerText.trim().runes.length;
    final clarity = answerLength >= 80
        ? '表达较完整，有展开论证。'
        : answerLength >= 30
        ? '表达基本完整，但可以补充推导过程和关键词。'
        : '回答偏短，建议先给结论，再补充依据。';
    final camera = capturedVideo == null
        ? '本次未保存视频片段，神态和动作只能给出准备建议。'
        : '已保存本题视频片段，建议回看眼神稳定性、语速和停顿。';
    return '$clarity $camera 面试时尽量看向镜头，回答前停顿半秒，手部动作保持自然。';
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
