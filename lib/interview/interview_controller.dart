import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../database/interview_repository.dart';
import '../database/models/llm_provider_config.dart';
import 'interview_ai_service.dart';
import 'interview_evidence_service.dart';
import 'interview_models.dart';
import 'interview_voice_port.dart';
import 'interview_failure.dart';

// ========== 面试状态机 ==========
// 负责一次面试从出题、播报、录音、转写、评分到追问或收尾的全部状态推进。
// 页面只读取这里的阶段与消息，不直接调用模型或数据库。

enum InterviewPhase {
  preparing,
  generatingQuestions,
  askingQuestion,
  speaking,
  awaitingAnswer,
  recording,
  transcribing,
  awaitingConfirmation,
  evaluating,
  finished,
  paused,
  failed,
}

/// 一道题的作答轮数上限：1 轮主答 + 最多 2 轮追问。
const int interviewMaxFollowUps = 2;

class InterviewMessage {
  const InterviewMessage({
    required this.id,
    required this.speaker,
    required this.text,
    required this.round,
    required this.isFollowUp,
    this.rawText,
    this.audioPath,
    this.durationMs,
    this.questionId,
    this.pending = false,
  });

  final String id;
  final String speaker; // assistant / user
  final String text;
  final int round;
  final bool isFollowUp;
  final String? rawText;
  final String? audioPath;
  final int? durationMs;
  final int? questionId;
  final bool pending;

  bool get isUser => speaker == 'user';

  InterviewMessage copyWith({
    String? text,
    bool? pending,
    String? rawText,
    String? audioPath,
    int? durationMs,
  }) => InterviewMessage(
    id: id,
    speaker: speaker,
    text: text ?? this.text,
    round: round,
    isFollowUp: isFollowUp,
    rawText: rawText ?? this.rawText,
    audioPath: audioPath ?? this.audioPath,
    durationMs: durationMs ?? this.durationMs,
    questionId: questionId,
    pending: pending ?? this.pending,
  );
}

class InterviewController extends ChangeNotifier {
  InterviewController({
    required this.userId,
    required InterviewSession session,
    required InterviewRepository repository,
    InterviewAiService? aiService,
    InterviewEvidenceService? evidenceService,
    InterviewVoicePort? voice,
    LlmProviderConfig? llmConfig,
  }) : _session = session,
       _repository = repository,
       _aiService = aiService ?? InterviewAiService(),
       _evidenceService = evidenceService,
       _voice = voice ?? NoopInterviewVoice(),
       _llmConfig = llmConfig,
       _evidence = const [] {
    _voice.phase.addListener(_onVoicePhase);
  }

  final int userId;
  final InterviewRepository _repository;
  final InterviewAiService _aiService;
  final InterviewEvidenceService? _evidenceService;
  final InterviewVoicePort _voice;
  LlmProviderConfig? _llmConfig;
  List<InterviewEvidence> _evidence;

  InterviewSession _session;
  final List<InterviewQuestion> _questions = [];
  final List<InterviewMessage> _messages = [];
  final Map<int, InterviewEvaluation> _evaluationsByQuestion = {};
  InterviewPhase _phase = InterviewPhase.preparing;
  InterviewMessage? _liveMessage;
  int _currentIndex = 0;
  int _currentRound = 0;
  String? _error;
  String? _reportJson;
  StreamSubscription<VoiceTranscript>? _transcriptSub;
  bool _disposed = false;
  int _operation = 0;
  InterviewPhase? _pausedPhase;
  Timer? _draftTimer;
  Future<void> _draftWrites = Future.value();
  bool _recordingStarting = false;
  bool _pauseRequested = false;
  bool _pausing = false;
  bool _draftSaveFailed = false;

  bool _active(int operation) => !_disposed && operation == _operation;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  InterviewSession get session => _session;
  List<InterviewQuestion> get questions => List.unmodifiable(_questions);
  List<InterviewMessage> get messages => List.unmodifiable(_messages);
  InterviewPhase get phase => _phase;
  String? get error => _error;
  String? get reportJson => _reportJson;
  InterviewVoicePort get voice => _voice;
  bool get voiceAvailable => _voice.modelReady;
  InterviewMessage? get liveMessage => _liveMessage;
  int get completedCount => _session.completedQuestionCount;
  int get targetCount => _session.targetQuestionCount;
  int get currentQuestionNumber => math.min(_currentIndex + 1, targetCount);
  InterviewQuestion? get currentQuestion =>
      _currentIndex >= 0 && _currentIndex < _questions.length
      ? _questions[_currentIndex]
      : null;
  InterviewEvaluation? get currentEvaluation => currentQuestion == null
      ? null
      : _evaluationsByQuestion[currentQuestion!.id];
  bool get canRecord => _phase == InterviewPhase.awaitingAnswer;
  bool get recordingStarting => _recordingStarting;
  bool get pausing => _pausing;
  bool get draftSaveFailed => _draftSaveFailed;
  bool get canSubmit =>
      _phase == InterviewPhase.awaitingConfirmation &&
      (_liveMessage?.text.trim().isNotEmpty ?? false);
  bool get isFinished => _phase == InterviewPhase.finished;
  bool get hasPendingAnswer => _phase == InterviewPhase.awaitingConfirmation;

  void updateLlmConfig(LlmProviderConfig config) => _llmConfig = config;

  @visibleForTesting
  void debugSetPhase(InterviewPhase phase) {
    _phase = phase;
    notifyListeners();
  }

  /// 用于测试注入素材，正式流程由 [start] 从数据库读取。
  @visibleForTesting
  set debugEvidence(List<InterviewEvidence> evidence) => _evidence = evidence;

  Future<void> start() async {
    if (_disposed) return;
    final operation = ++_operation;
    _phase = InterviewPhase.preparing;
    _error = null;
    notifyListeners();
    try {
      if (_llmConfig?.isConfigured != true) {
        throw StateError('请先在“我的”页配置大模型服务，再开始 AI 面试');
      }
      if (_questions.isEmpty) {
        _phase = InterviewPhase.generatingQuestions;
        notifyListeners();
        final evidence = _evidence.isNotEmpty
            ? _evidence
            : await (_evidenceService ?? InterviewEvidenceService()).load(
                userId: userId,
                libraryId: _session.libraryId,
                recordId: _session.recordId,
                mode: _session.mode,
              );
        if (evidence.isEmpty) throw StateError('所选范围没有可靠的出题资料，请先完成 OCR 校对');
        _evidence = evidence;
        final drafts = await _aiService.generateQuestions(
          evidence: evidence,
          mode: _session.mode,
          difficulty: _session.difficulty,
          count: _session.targetQuestionCount,
          config: _llmConfig!,
        );
        if (!_active(operation)) return;
        _questions
          ..clear()
          ..addAll(
            await _repository.saveQuestions(userId, _session.id, drafts),
          );
      }
      if (!_active(operation)) return;
      await _loadHistory();
      if (!_active(operation)) return;
      await _restoreProgress();
    } catch (error) {
      if (_active(operation)) {
        _fail(interviewFailure(error, fallback: '出题失败，请重试'));
      }
    }
  }

  /// 恢复未完成会话：读取历史问题与消息，停在当前题目。
  Future<void> resume() async {
    if (_disposed) return;
    _pauseRequested = false;
    final operation = ++_operation;
    _phase = InterviewPhase.preparing;
    _error = null;
    notifyListeners();
    try {
      if (_llmConfig?.isConfigured != true) {
        throw StateError('请先配置大模型服务，再继续面试');
      }
      _questions
        ..clear()
        ..addAll(await _repository.questions(userId, _session.id));
      if (_questions.isEmpty) {
        await start();
        return;
      }
      await _loadHistory();
      if (!_active(operation)) return;
      await _restoreProgress();
    } catch (error) {
      if (_active(operation)) {
        _fail(interviewFailure(error, fallback: '读取面试失败，请重试'));
      }
    }
  }

  Future<void> _loadHistory() async {
    final turns = await _repository.turns(userId, _session.id);
    final evals = await _repository.evaluations(userId, _session.id);
    _evaluationsByQuestion
      ..clear()
      ..addEntries(evals.map((e) => MapEntry(e.questionId, e)));
    _messages
      ..clear()
      ..addAll(
        turns.map(
          (t) => InterviewMessage(
            id: 'turn:${t.id}',
            speaker: t.speaker,
            text: t.text,
            round: t.round,
            isFollowUp: t.isFollowUp,
            rawText: t.rawText,
            audioPath: t.audioPath,
            durationMs: t.durationMs,
            questionId: t.questionId,
          ),
        ),
      );
  }

  Future<void> _restoreProgress() async {
    _session = (await _repository.getSession(userId, _session.id))!;
    _liveMessage = null;
    if (_session.status == 'completed' || _session.status == 'cancelled') {
      _reportJson = _session.reportJson;
      _phase = InterviewPhase.finished;
      notifyListeners();
      return;
    }
    final stored = await _repository.questions(userId, _session.id);
    _questions
      ..clear()
      ..addAll(stored);
    _currentIndex = _questions.indexWhere((q) => q.status != 'completed');
    if (_currentIndex < 0) {
      await _finish(cancelled: false);
      return;
    }
    final question = currentQuestion!;
    final draft = await _repository.answerDraft(userId, _session.id);
    if (_disposed) return;
    final turns = _messages.where((m) => m.questionId == question.id).toList();
    if (draft != null &&
        draft['question_id'] == question.id &&
        (turns.isEmpty || !turns.last.isUser)) {
      _currentRound = draft['round'] as int;
      _liveMessage = InterviewMessage(
        id: 'draft:${_session.id}',
        speaker: 'user',
        text: draft['text'] as String,
        rawText: draft['raw_text'] as String?,
        audioPath: draft['audio_path'] as String?,
        durationMs: draft['duration_ms'] as int?,
        round: _currentRound,
        isFollowUp: _currentRound > 0,
        questionId: question.id,
      );
      _phase = InterviewPhase.awaitingConfirmation;
      notifyListeners();
      return;
    }
    if (turns.isEmpty) {
      await _askCurrentQuestion();
      return;
    }
    final last = turns.last;
    _currentRound = last.round;
    if (last.isUser) {
      final evaluation = _evaluationsByQuestion[question.id];
      if (evaluation == null || last.id != 'turn:${evaluation.turnId}') {
        _messages.removeWhere((m) => m.id == last.id);
        _liveMessage = last.copyWith(pending: false);
        _phase = InterviewPhase.awaitingConfirmation;
      } else {
        await _continueEvaluation(question, evaluation);
        return;
      }
    } else {
      _phase = InterviewPhase.awaitingAnswer;
    }
    notifyListeners();
  }

  Future<void> _askCurrentQuestion() async {
    final operation = _operation;
    final question = currentQuestion;
    if (question == null) {
      await _finish(cancelled: _session.completedQuestionCount == 0);
      return;
    }
    _currentRound = 0;
    final turn = await _repository.upsertTurn(
      userId: userId,
      sessionId: _session.id,
      questionId: question.id,
      speaker: 'assistant',
      text: question.questionText,
      round: 0,
      isFollowUp: false,
      requestKey: 'q${question.id}:ask',
    );
    if (!_active(operation)) return;
    _messages.add(
      InterviewMessage(
        id: 'turn:${turn.id}',
        speaker: 'assistant',
        text: turn.text,
        round: 0,
        isFollowUp: false,
        questionId: question.id,
      ),
    );
    await _repository.setSessionState(
      userId,
      _session.id,
      status: 'in_progress',
      currentOrder: _currentIndex + 1,
      currentRound: 0,
    );
    _session = (await _repository.getSession(userId, _session.id))!;
    if (!_active(operation)) return;
    _phase = InterviewPhase.askingQuestion;
    notifyListeners();
    if (_session.voiceEnabled && _session.autoPlay) {
      await _speakCurrentQuestion(question.questionText);
    } else {
      _phase = _pauseRequested
          ? InterviewPhase.paused
          : InterviewPhase.awaitingAnswer;
      notifyListeners();
    }
  }

  Future<void> _speakCurrentQuestion(String text) async {
    if (_pauseRequested) {
      _phase = InterviewPhase.paused;
      _pausedPhase = InterviewPhase.awaitingAnswer;
      notifyListeners();
      return;
    }
    final operation = _operation;
    _error = null;
    _phase = InterviewPhase.speaking;
    notifyListeners();
    try {
      await _voice.speak(
        text,
        volume: _session.voiceVolume,
        rate: _session.voiceRate,
      );
    } catch (error) {
      if (!_active(operation)) return;
      _error = interviewFailure(error, fallback: '播报失败，请阅读题目作答');
    }
    if (!_active(operation) || _phase != InterviewPhase.speaking) return;
    _phase = InterviewPhase.awaitingAnswer;
    notifyListeners();
  }

  Future<void> replayQuestion() async {
    final question = currentQuestion;
    if (question == null || _phase != InterviewPhase.awaitingAnswer) return;
    final lastFollowUp = _messages.lastWhere(
      (m) => !m.isUser && m.questionId == question.id,
      orElse: () => InterviewMessage(
        id: 'q${question.id}',
        speaker: 'assistant',
        text: question.questionText,
        round: 0,
        isFollowUp: false,
      ),
    );
    if (_session.voiceEnabled) await _speakCurrentQuestion(lastFollowUp.text);
  }

  Future<void> replayMessage(InterviewMessage message) async {
    if (!message.isUser &&
        _session.voiceEnabled &&
        _phase == InterviewPhase.awaitingAnswer) {
      await _speakCurrentQuestion(message.text);
    }
  }

  Future<void> interruptSpeech() async {
    if (_phase != InterviewPhase.speaking) return;
    ++_operation;
    try {
      await _voice.stopSpeaking();
    } catch (error) {
      _error = interviewFailure(error, fallback: '语音停止失败，请重试');
    }
    _phase = InterviewPhase.awaitingAnswer;
    notifyListeners();
  }

  Future<void> beginRecording() async {
    if (!canRecord) return;
    final operation = _operation;
    _error = null;
    _recordingStarting = true;
    _phase = InterviewPhase.recording;
    _liveMessage = InterviewMessage(
      id: 'live:${DateTime.now().microsecondsSinceEpoch}',
      speaker: 'user',
      text: '',
      round: _currentRound,
      isFollowUp: _currentRound > 0,
      questionId: currentQuestion?.id,
      pending: true,
    );
    notifyListeners();
    try {
      await _voice.stopSpeaking();
      if (!_active(operation)) return;
      _transcriptSub ??= _voice.transcripts.listen(
        _onTranscript,
        onError: (Object error) {
          if (_disposed ||
              (_phase != InterviewPhase.recording &&
                  _phase != InterviewPhase.transcribing)) {
            return;
          }
          _error = interviewFailure(error, fallback: '录音失败，请重试');
          _liveMessage = _liveMessage?.copyWith(pending: false);
          _phase = InterviewPhase.awaitingConfirmation;
          unawaited(savePendingAnswer());
          notifyListeners();
        },
      );
      await _voice.startRecording();
      if (!_active(operation)) {
        await _voice.cancel();
        return;
      }
    } catch (error) {
      if (!_active(operation)) return;
      _error = interviewFailure(error, fallback: '录音未开始，请重试');
      _phase = InterviewPhase.awaitingAnswer;
      _liveMessage = null;
      notifyListeners();
    } finally {
      _recordingStarting = false;
      notifyListeners();
    }
  }

  void _onVoicePhase() {
    if (_phase == InterviewPhase.recording &&
        _voice.phase.value == VoicePhase.transcribing) {
      _phase = InterviewPhase.transcribing;
      notifyListeners();
    } else if (_phase == InterviewPhase.recording &&
        _voice.phase.value == VoicePhase.recording) {
      notifyListeners();
    }
  }

  void _onTranscript(VoiceTranscript transcript) {
    if (_phase != InterviewPhase.recording &&
        _phase != InterviewPhase.transcribing) {
      return;
    }
    if (transcript.isFinal) {
      _liveMessage = _liveMessage?.copyWith(
        text: transcript.text,
        rawText: transcript.text,
        pending: false,
        audioPath: transcript.audioPath,
        durationMs: transcript.durationMs,
      );
      _phase = InterviewPhase.awaitingConfirmation;
      if (transcript.text.trim().isEmpty) {
        _error = '没有识别到文字，请重试或改用文字回答';
      }
      unawaited(savePendingAnswer());
      notifyListeners();
      return;
    }
    final live = _liveMessage;
    if (live == null || transcript.text.trim().isEmpty) return;
    // 增量转写只更新当前这一条气泡，绝不追加新消息。
    _liveMessage = live.copyWith(text: transcript.text);
    _scheduleDraft();
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (_phase != InterviewPhase.recording || _recordingStarting) return;
    final operation = _operation;
    _phase = InterviewPhase.transcribing;
    notifyListeners();
    try {
      final result = await _voice.stopRecording();
      if (!_active(operation)) return;
      final text = result.text.trim();
      _liveMessage =
          (_liveMessage ??
                  InterviewMessage(
                    id: 'live:${DateTime.now().microsecondsSinceEpoch}',
                    speaker: 'user',
                    text: '',
                    round: _currentRound,
                    isFollowUp: _currentRound > 0,
                    questionId: currentQuestion?.id,
                    pending: true,
                  ))
              .copyWith(
                text: text,
                rawText: text,
                pending: false,
                audioPath: result.audioPath,
                durationMs: result.durationMs,
              );
      _phase = InterviewPhase.awaitingConfirmation;
      if (text.isEmpty) _error = '没有识别到文字，请重试或改用文字回答';
    } catch (error) {
      if (!_active(operation)) return;
      _error = interviewFailure(error, fallback: '转写失败，可修改文字后提交');
      _liveMessage = _liveMessage?.copyWith(pending: false);
      _phase = InterviewPhase.awaitingConfirmation;
    }
    await savePendingAnswer();
    notifyListeners();
  }

  /// 用户可修正识别文本，修正只影响这一条待确认消息。
  void editPendingAnswer(String text) {
    if (_phase != InterviewPhase.awaitingConfirmation) return;
    final live = _liveMessage;
    if (live == null) return;
    _liveMessage = live.copyWith(text: text);
    _scheduleDraft();
    notifyListeners();
  }

  /// 无麦克风或识别失败时的文字回答降级入口。
  Future<void> startTextAnswer({String initial = ''}) async {
    if (_phase != InterviewPhase.awaitingAnswer &&
        _phase != InterviewPhase.awaitingConfirmation) {
      return;
    }
    _error = null;
    _liveMessage = InterviewMessage(
      id: 'live:${DateTime.now().microsecondsSinceEpoch}',
      speaker: 'user',
      text: initial,
      round: _currentRound,
      isFollowUp: _currentRound > 0,
      questionId: currentQuestion?.id,
      pending: false,
    );
    _phase = InterviewPhase.awaitingConfirmation;
    await savePendingAnswer();
    notifyListeners();
  }

  void _scheduleDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(savePendingAnswer()),
    );
  }

  Future<void> savePendingAnswer() {
    _draftTimer?.cancel();
    final live = _liveMessage;
    if (live == null ||
        live.questionId == null ||
        _phase == InterviewPhase.finished) {
      return _draftWrites;
    }
    final values = <String, Object?>{
      'question_id': live.questionId,
      'text': live.text,
      'raw_text': live.rawText,
      'audio_path': live.audioPath,
      'duration_ms': live.durationMs,
      'round': live.round,
    };
    return _draftWrites = _draftWrites
        .then((_) async {
          await _repository.saveAnswerDraft(userId, _session.id, values);
          _draftSaveFailed = false;
        })
        .catchError((Object _) {
          _draftSaveFailed = true;
          if (!_disposed) {
            _error = '回答保存失败，请保持页面并重试';
            notifyListeners();
          }
        });
  }

  Future<void> cancelRecording() async {
    if (_phase != InterviewPhase.recording &&
        _phase != InterviewPhase.awaitingConfirmation) {
      return;
    }
    try {
      await _voice.cancel();
    } catch (_) {}
    _draftTimer?.cancel();
    await _draftWrites;
    await _repository.clearAnswerDraft(userId, _session.id);
    await _discardPendingAudio();
    _liveMessage = null;
    _phase = InterviewPhase.awaitingAnswer;
    notifyListeners();
  }

  Future<void> submitAnswer() async {
    final question = currentQuestion;
    final live = _liveMessage;
    if (question == null || live == null) return;
    final answer = live.text.trim();
    if (answer.isEmpty) {
      _error = '回答内容不能为空';
      notifyListeners();
      return;
    }
    if (!canSubmit) return;
    final operation = _operation;
    _phase = InterviewPhase.evaluating;
    _error = null;
    notifyListeners();
    try {
      await savePendingAnswer();
      final turn = await _repository.upsertTurn(
        userId: userId,
        sessionId: _session.id,
        questionId: question.id,
        speaker: 'user',
        text: answer,
        rawText: live.rawText ?? answer,
        audioPath: live.audioPath,
        durationMs: live.durationMs,
        round: _currentRound,
        isFollowUp: _currentRound > 0,
        requestKey: 'q${question.id}:user:r$_currentRound',
      );
      if (!_active(operation)) return;
      await _repository.clearAnswerDraft(userId, _session.id);
      _messages.removeWhere(
        (m) => m.id == live.id || m.id == 'turn:${turn.id}',
      );
      _messages.add(
        InterviewMessage(
          id: 'turn:${turn.id}',
          speaker: 'user',
          text: turn.text,
          round: turn.round,
          isFollowUp: turn.isFollowUp,
          audioPath: turn.audioPath,
          durationMs: turn.durationMs,
          questionId: question.id,
        ),
      );
      _liveMessage = null;
      final result = await _aiService.evaluateAnswer(
        question: question,
        userAnswer: answer,
        config: _llmConfig!,
        dialogue: _messages
            .where((m) => m.questionId == question.id)
            .map((m) => '${m.isUser ? '考生' : '面试官'}：${m.text}')
            .toList(),
        followUpReferencePoints: _currentRound > 0
            ? (_evaluationsByQuestion[question.id]?.followUpReferencePoints ??
                  const [])
            : const [],
      );
      if (!_active(operation)) return;
      final evaluation = await _repository.saveEvaluation(
        userId,
        InterviewEvaluation(
          id: 0,
          sessionId: _session.id,
          questionId: question.id,
          turnId: turn.id,
          accuracyScore: result.accuracyScore,
          completenessScore: result.completenessScore,
          logicScore: result.logicScore,
          expressionScore: result.expressionScore,
          totalScore: result.totalScore,
          strengths: result.strengths,
          weaknesses: result.weaknesses,
          suggestions: result.suggestions,
          evidenceRefs: result.evidenceRefs,
          followUpText: result.followUpText,
          followUpReferencePoints: result.followUpReferencePoints,
        ),
      );
      _evaluationsByQuestion[question.id] = evaluation;
      if (!_active(operation)) return;
      await _continueEvaluation(question, evaluation);
    } catch (error) {
      if (_active(operation)) {
        _fail(interviewFailure(error, fallback: '评分失败，请重试'));
      }
    }
  }

  Future<void> _continueEvaluation(
    InterviewQuestion question,
    InterviewEvaluation evaluation,
  ) async {
    final followUp = evaluation.followUpText;
    if (_session.mode == 'deep' &&
        followUp != null &&
        followUp.trim().isNotEmpty &&
        evaluation.followUpReferencePoints.isNotEmpty &&
        !_messages.any((m) => !m.isUser && m.text.trim() == followUp.trim()) &&
        _currentRound < interviewMaxFollowUps) {
      await _askFollowUp(
        question,
        followUp,
        evaluation.followUpReferencePoints,
      );
    } else {
      await _advance();
    }
  }

  Future<void> _askFollowUp(
    InterviewQuestion question,
    String followUp,
    List<String> points,
  ) async {
    final operation = _operation;
    _currentRound += 1;
    final turn = await _repository.upsertTurn(
      userId: userId,
      sessionId: _session.id,
      questionId: question.id,
      speaker: 'assistant',
      text: followUp,
      round: _currentRound,
      isFollowUp: true,
      requestKey: 'q${question.id}:followup:r$_currentRound',
    );
    if (!_active(operation)) return;
    _messages.add(
      InterviewMessage(
        id: 'turn:${turn.id}',
        speaker: 'assistant',
        text: turn.text,
        round: _currentRound,
        isFollowUp: true,
        questionId: question.id,
      ),
    );
    await _repository.setSessionState(
      userId,
      _session.id,
      status: 'in_progress',
      currentOrder: _currentIndex + 1,
      currentRound: _currentRound,
    );
    _session = (await _repository.getSession(userId, _session.id))!;
    if (!_active(operation)) return;
    _phase = InterviewPhase.askingQuestion;
    notifyListeners();
    if (_session.voiceEnabled && _session.autoPlay) {
      await _speakCurrentQuestion(followUp);
    } else {
      _phase = _pauseRequested
          ? InterviewPhase.paused
          : InterviewPhase.awaitingAnswer;
      notifyListeners();
    }
  }

  Future<void> _advance() async {
    final operation = _operation;
    final question = currentQuestion;
    if (question != null) {
      await _repository.completeQuestion(userId, _session.id, question.id);
      if (!_active(operation)) return;
      _session = (await _repository.getSession(userId, _session.id))!;
      if (!_active(operation)) return;
    }
    _currentIndex += 1;
    _liveMessage = null;
    if (_currentIndex >= _questions.length) {
      await _finish(cancelled: false);
      return;
    }
    notifyListeners();
    await _askCurrentQuestion();
  }

  /// 用户主动提前结束：已完成题目照常评分，缺失题目标记为未完成。
  Future<void> endEarly() async => _finish(cancelled: true);

  Future<void> _finish({required bool cancelled}) async {
    if (_phase == InterviewPhase.finished) return;
    ++_operation;
    _aiService.cancel();
    _phase = InterviewPhase.evaluating;
    notifyListeners();
    try {
      await _voice.cancel();
      _draftTimer?.cancel();
      await _draftWrites;
      await _repository.clearAnswerDraft(userId, _session.id);
      await _discardPendingAudio();
      _questions
        ..clear()
        ..addAll(await _repository.questions(userId, _session.id));
      final report = _buildReport(cancelled: cancelled);
      await _repository.finishSession(
        userId,
        _session.id,
        report: report,
        cancelled: cancelled,
      );
      _session = (await _repository.getSession(userId, _session.id))!;
      _reportJson = jsonEncode(report);
      _phase = InterviewPhase.finished;
    } catch (error) {
      _fail(interviewFailure(error, fallback: '报告保存失败，请重试'));
      return;
    }
    notifyListeners();
  }

  Map<String, Object?> _buildReport({required bool cancelled}) {
    final completedIds = _questions
        .where((q) => q.status == 'completed')
        .map((q) => q.id)
        .toSet();
    final evals = _evaluationsByQuestion.values
        .where((e) => completedIds.contains(e.questionId))
        .toList(growable: false);
    final completed = _session.completedQuestionCount;
    final knowledge = evals.isEmpty
        ? null
        : (evals
                      .map((e) => e.accuracyScore + e.completenessScore)
                      .reduce((a, b) => a + b) *
                  100) ~/
              (evals.length * 70);
    final expression = evals.isEmpty
        ? null
        : (evals
                      .map((e) => e.expressionScore + e.logicScore)
                      .reduce((a, b) => a + b) *
                  100) ~/
              (evals.length * 30);
    final overall = evals.isEmpty
        ? null
        : evals.map((e) => e.totalScore).reduce((a, b) => a + b) ~/
              evals.length;
    final strengths = <String>{};
    final weaknesses = <String>{};
    final suggestions = <String>{};
    final weakPoints = <String>{};
    for (final eval in evals) {
      strengths.addAll(eval.strengths);
      weaknesses.addAll(eval.weaknesses);
      suggestions.addAll(eval.suggestions);
      if (eval.totalScore < 70) {
        final question = _questions
            .where((q) => q.id == eval.questionId)
            .firstOrNull;
        if (question != null) {
          weakPoints.add(
            question.knowledgePoint.isEmpty
                ? question.questionText
                : question.knowledgePoint,
          );
        }
      }
    }
    return {
      'overall_score': overall,
      'score_scale': 100,
      'knowledge_score': knowledge,
      'expression_score': expression,
      'completed_count': completed,
      'target_count': _session.targetQuestionCount,
      'cancelled': cancelled,
      'strengths': strengths.take(6).toList(),
      'weaknesses': weaknesses.take(6).toList(),
      'suggestions': suggestions.take(6).toList(),
      'weak_points': weakPoints.toList(),
    };
  }

  Future<void> pause() async {
    _pauseRequested = true;
    if (_phase == InterviewPhase.paused ||
        _phase == InterviewPhase.finished ||
        _phase == InterviewPhase.evaluating ||
        _phase == InterviewPhase.generatingQuestions ||
        _phase == InterviewPhase.preparing) {
      return;
    }
    final previous = _phase;
    final operation = ++_operation;
    _pausing = true;
    _phase = InterviewPhase.paused;
    notifyListeners();
    try {
      if (previous == InterviewPhase.recording ||
          previous == InterviewPhase.transcribing) {
        if (!_recordingStarting) {
          final result = await _voice.stopRecording();
          if (!_active(operation)) return;
          _liveMessage = _liveMessage?.copyWith(
            text: result.text,
            rawText: result.text,
            pending: false,
            audioPath: result.audioPath,
            durationMs: result.durationMs,
          );
        } else {
          await _voice.cancel();
        }
      }
      await _voice.stopSpeaking();
    } catch (error) {
      _liveMessage = _liveMessage?.copyWith(pending: false);
      _error = interviewFailure(error, fallback: '录音已中断，可校对文字后继续');
    } finally {
      _pausing = false;
    }
    if (!_active(operation)) return;
    _pausedPhase = _liveMessage == null
        ? InterviewPhase.awaitingAnswer
        : InterviewPhase.awaitingConfirmation;
    _phase = InterviewPhase.paused;
    await savePendingAnswer();
    notifyListeners();
  }

  Future<void> resumeFromPause() async {
    if (_phase != InterviewPhase.paused || _pausing) return;
    _pauseRequested = false;
    _phase = _pausedPhase == InterviewPhase.awaitingConfirmation
        ? InterviewPhase.awaitingConfirmation
        : InterviewPhase.awaitingAnswer;
    notifyListeners();
  }

  /// 恢复持久化的游标与待评价回答，重试同一轮不会重复插入消息。
  Future<void> retry() async {
    if (_phase != InterviewPhase.failed) return;
    await resume();
    if (_phase == InterviewPhase.awaitingConfirmation && canSubmit) {
      await submitAnswer();
    }
  }

  void _fail(String message) {
    _error = message;
    _phase = InterviewPhase.failed;
    if (!_disposed) notifyListeners();
  }

  Future<void> _discardPendingAudio() async {
    final path = _liveMessage?.audioPath;
    if (path == null) return;
    try {
      await _repository.discardUnsubmittedAudio(userId, _session.id, path);
    } catch (_) {
      // Stored turns remain authoritative; cleanup must never erase their audio.
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(savePendingAnswer());
    ++_operation;
    _disposed = true;
    _aiService.cancel();
    _draftTimer?.cancel();
    _transcriptSub?.cancel();
    _transcriptSub = null;
    _voice.phase.removeListener(_onVoicePhase);
    unawaited(_voice.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
