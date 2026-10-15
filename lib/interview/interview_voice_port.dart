import 'package:flutter/foundation.dart';

// ========== 面试语音端口 ==========
// 页面与状态机只依赖这组接口，便于替换离线/云端语音实现与测试注入。

enum VoicePhase { idle, speaking, recording, transcribing, paused, error }

class VoiceTranscript {
  const VoiceTranscript({
    required this.text,
    required this.isFinal,
    this.audioPath,
    this.durationMs,
  });

  final String text;
  final bool isFinal;
  final String? audioPath;
  final int? durationMs;
}

abstract class InterviewVoicePort {
  ValueListenable<VoicePhase> get phase;

  /// 归一化 0..1 的嘴部开合驱动；无播放时必须为 0。
  ValueListenable<double> get mouthActivity;

  /// 录音期间输出临时结果。主动结束返回最终结果；自动结束通过流通知。
  Stream<VoiceTranscript> get transcripts;
  bool get modelReady;
  String? get lastError;
  Future<void> ensureOfflineModel({void Function(double progress)? onProgress});
  Future<void> speak(String text, {double volume = 1, double rate = 0.5});
  Future<void> stopSpeaking();
  Future<void> startRecording();
  Future<VoiceTranscript> stopRecording();
  Future<void> playRecording(String path);
  Future<void> cancel();
  Future<void> dispose();
}

/// 测试与降级场景使用的最小空实现，不做任何音频操作。
class NoopInterviewVoice implements InterviewVoicePort {
  final _phase = ValueNotifier<VoicePhase>(VoicePhase.idle);
  final _mouth = ValueNotifier<double>(0);
  @override
  ValueListenable<VoicePhase> get phase => _phase;
  @override
  ValueListenable<double> get mouthActivity => _mouth;
  @override
  Stream<VoiceTranscript> get transcripts => const Stream.empty();
  @override
  bool get modelReady => false;
  @override
  String? get lastError => '当前未接入语音服务，可先用文字回答。';
  @override
  Future<void> ensureOfflineModel({
    void Function(double progress)? onProgress,
  }) async {
    throw StateError(lastError!);
  }

  @override
  Future<void> speak(
    String text, {
    double volume = 1,
    double rate = 0.5,
  }) async {
    throw StateError(lastError!);
  }

  @override
  Future<void> stopSpeaking() async {}
  @override
  Future<void> startRecording() async {
    throw StateError(lastError!);
  }

  @override
  Future<VoiceTranscript> stopRecording() async =>
      const VoiceTranscript(text: '', isFinal: true);
  @override
  Future<void> playRecording(String path) async {}
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {
    _phase.dispose();
    _mouth.dispose();
  }
}
