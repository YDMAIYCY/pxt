import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../interview_voice_port.dart';
import 'offline_model_manager.dart';
import 'pcm_wav.dart';
import 'voice_backends.dart';

/// One microphone owner, one output owner, explicit recording-end submission.
/// Construct with backends for tests, or use createOfflineInterviewVoiceService.
class OfflineInterviewVoiceService
    with WidgetsBindingObserver
    implements InterviewVoicePort {
  OfflineInterviewVoiceService({
    required this.modelManager,
    required VoiceRecorder recorder,
    required VoiceAsrEngine asr,
    required VoiceSpeaker speaker,
    required VoicePlayback playback,
    Directory? recordingsDirectory,
    this.settings = const VoiceSettings(),
    this.operationTimeout = const Duration(seconds: 20),
    this.recordingLimit = const Duration(minutes: 2),
  }) : _recorder = recorder,
       _asr = asr,
       _speaker = speaker,
       _playback = playback,
       _recordingsDirectory =
           recordingsDirectory ??
           Directory(p.join(modelManager.root.path, 'recordings')) {
    WidgetsBinding.instance.addObserver(this);
  }

  final OfflineModelManager modelManager;
  final VoiceRecorder _recorder;
  final VoiceAsrEngine _asr;
  final VoiceSpeaker _speaker;
  final VoicePlayback _playback;
  final Directory _recordingsDirectory;
  final Duration operationTimeout;
  final Duration recordingLimit;

  /// The main controller loads/saves these settings; this service owns no DB.
  VoiceSettings settings;

  @override
  final ValueNotifier<VoicePhase> phase = ValueNotifier<VoicePhase>(
    VoicePhase.idle,
  );
  @override
  final ValueNotifier<double> mouthActivity = ValueNotifier<double>(0);
  ValueListenable<double> get modelProgress => modelManager.progress;
  ValueListenable<bool> get modelDownloading => modelManager.downloading;
  final _transcripts = StreamController<VoiceTranscript>.broadcast();
  @override
  Stream<VoiceTranscript> get transcripts => _transcripts.stream;
  @override
  bool get modelReady => modelManager.ready;
  @override
  String? get lastError => _lastError;
  String? _lastError;
  Future<void> _commands = Future.value();
  Future<void> _audioQueue = Future.value();
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _streamDone;
  Completer<void>? _outputCancelled;
  PcmWavWriter? _wav;
  Pcm16Decoder? _decoder;
  Timer? _recordingTimer;
  Object? _recordError;
  Future<VoiceTranscript>? _stopping;
  VoiceTranscript? _lastFinal;
  int _pendingChunks = 0;
  int _epoch = 0;
  int _recordingEpoch = 0;
  bool _recording = false;
  bool _disposed = false;
  bool _background = false;
  Future<void>? _disposing;

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _commands.then((_) => action());
    _commands = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _check(int epoch) {
    if (_disposed || _background || _disposing != null || epoch != _epoch) {
      throw const VoiceCancelled();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;
    if (_background && !_disposed && _disposing == null) {
      unawaited(cancel().catchError((Object error) => _error(error)));
    }
  }

  void _error(Object error) {
    if (_disposed) return;
    _lastError = error.toString();
    mouthActivity.value = 0;
    phase.value = VoicePhase.error;
  }

  @override
  Future<void> ensureOfflineModel({void Function(double)? onProgress}) async {
    if (_disposed || _disposing != null) throw StateError('语音服务已释放');
    try {
      await modelManager.ensure(onProgress: onProgress);
    } on VoiceCancelled {
      rethrow;
    } catch (error) {
      _error(error);
      rethrow;
    }
  }

  Future<void> _stopOutput() async {
    if (!(_outputCancelled?.isCompleted ?? true)) _outputCancelled!.complete();
    mouthActivity.value = 0;
    await Future.wait([
      _speaker.stop(),
      _playback.stop(),
    ]).timeout(operationTimeout);
  }

  Future<void> _output(Future<void> Function(int epoch) start) async {
    if (_disposed || _disposing != null) throw StateError('语音服务已释放');
    if (_recording || _stopping != null) throw StateError('请先结束回答录音');
    final epoch = ++_epoch;
    Future<void>? completion;
    try {
      await _serial(() async {
        _check(epoch);
        await _stopOutput();
        _check(epoch);
        _lastError = null;
        phase.value = VoicePhase.speaking;
        final cancelled = _outputCancelled = Completer<void>();
        completion = Future.any([
          Future<void>.sync(() => start(epoch)),
          cancelled.future.then<void>((_) => throw const VoiceCancelled()),
        ]);
        // Attach immediately, including when the backend fails synchronously.
        unawaited(
          completion!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      });
      await completion!.timeout(recordingLimit);
    } on VoiceCancelled {
      rethrow;
    } catch (error) {
      if (epoch == _epoch) {
        await _serial(() async {
          try {
            await _stopOutput();
          } finally {
            _error(error);
          }
        });
      }
      rethrow;
    } finally {
      if (!_disposed && epoch == _epoch && phase.value != VoicePhase.error) {
        mouthActivity.value = 0;
        phase.value = VoicePhase.idle;
      }
    }
  }

  @override
  Future<void> speak(String text, {double volume = 1, double rate = 0.5}) {
    if (text.trim().isEmpty) return Future.value();
    return _output(
      (epoch) => _speaker.speak(
        text,
        volume: volume.clamp(0.0, 1.0),
        rate: rate.clamp(0.0, 1.0),
        onActivity: (value) {
          if (!_disposed &&
              epoch == _epoch &&
              phase.value == VoicePhase.speaking) {
            mouthActivity.value = value.clamp(0.0, 1.0);
          }
        },
      ),
    );
  }

  /// Uses the settings last loaded/persisted by the main controller.
  Future<void> speakWithSettings(String text) =>
      speak(text, volume: settings.volume, rate: settings.rate);

  @override
  Future<void> playRecording(String path) => _output((epoch) async {
    if (!await File(path).exists()) throw StateError('录音文件不存在');
    _check(epoch);
    // System playback has no PCM/viseme stream. This is an activity hint.
    mouthActivity.value = 0.4;
    await _playback.play(path);
  });

  @override
  Future<void> stopSpeaking() {
    if (_disposed) return Future.value();
    if (_recording) return Future.value();
    ++_epoch;
    return _serial(() async {
      try {
        await _stopOutput();
        if (!_disposed) phase.value = VoicePhase.idle;
      } catch (error) {
        _error(error);
        rethrow;
      }
    });
  }

  @override
  Future<void> startRecording() {
    if (_disposed || _disposing != null) throw StateError('语音服务已释放');
    if (_recording || _stopping != null) throw StateError('录音正在进行或结束中');
    final epoch = ++_epoch;
    return _serial(() async {
      _check(epoch);
      try {
        await _stopOutput();
        _check(epoch);
        if (!modelReady) throw StateError('请先显式下载并验证离线中文模型');
        await _asr.start(modelManager.directory.path).timeout(operationTimeout);
        _check(epoch);
        _wav = await PcmWavWriter.create(
          p.join(
            _recordingsDirectory.path,
            'answer_${DateTime.now().microsecondsSinceEpoch}.wav',
          ),
        );
        _check(epoch);
        final stream = await _recorder.start().timeout(operationTimeout);
        _check(epoch);
        _decoder = Pcm16Decoder();
        _audioQueue = Future.value();
        _streamDone = Completer<void>();
        _pendingChunks = 0;
        _recordError = null;
        _lastFinal = null;
        _recordingEpoch = epoch;
        _recording = true;
        _lastError = null;
        phase.value = VoicePhase.recording;
        mouthActivity.value = 0;
        _audioSubscription = stream.listen(
          (chunk) => _acceptAudio(chunk, epoch),
          onError: (Object error) => _failRecording(error, epoch),
          onDone: () {
            if (!(_streamDone?.isCompleted ?? true)) _streamDone!.complete();
            if (_recording && _stopping == null && epoch == _epoch) {
              unawaited(
                stopRecording().then<void>(
                  (_) {},
                  onError: (Object _, StackTrace _) {},
                ),
              );
            }
          },
        );
        _recordingTimer = Timer(recordingLimit, () {
          if (_recording && epoch == _epoch) {
            unawaited(
              stopRecording().then<void>(
                (_) {},
                onError: (Object _, StackTrace _) {},
              ),
            );
          }
        });
      } catch (error) {
        await _cleanupRecording();
        if (error is! VoiceCancelled && epoch == _epoch) _error(error);
        rethrow;
      }
    });
  }

  void _acceptAudio(Uint8List chunk, int epoch) {
    if (!_recording || epoch != _epoch || _recordError != null) return;
    // No silent dropping and no unbounded inference/disk backlog.
    if (++_pendingChunks > 64) {
      _pendingChunks--;
      _failRecording(StateError('语音处理速度不足，录音队列已满'), epoch);
      return;
    }
    final frame = _decoder!.decode(chunk);
    _audioQueue = _audioQueue.then((_) async {
      try {
        _check(epoch);
        if (_recordError != null || frame.bytes.isEmpty) return;
        await _wav!.append(frame.bytes);
        final text = await _asr.accept(frame.samples).timeout(operationTimeout);
        _check(epoch);
        if (text.isNotEmpty) {
          _transcripts.add(VoiceTranscript(text: text, isFinal: false));
        }
      } catch (error) {
        if (error is! VoiceCancelled) _failRecording(error, epoch);
      } finally {
        _pendingChunks--;
      }
    });
  }

  void _failRecording(Object error, int epoch) {
    if (_recordError != null || epoch != _epoch || _disposed) return;
    _recordError = error;
    if (_stopping == null) {
      unawaited(
        stopRecording().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
  }

  @override
  Future<VoiceTranscript> stopRecording() {
    if (_stopping != null) return _stopping!;
    if (!_recording) {
      if (_lastFinal != null) return Future.value(_lastFinal);
      throw StateError('没有正在进行的录音');
    }
    final epoch = _recordingEpoch;
    final result = _serial(() async {
      _recordingTimer?.cancel();
      try {
        _check(epoch);
        phase.value = VoicePhase.transcribing;
        await _recorder.stop().timeout(operationTimeout);
        await _streamDone!.future.timeout(operationTimeout);
        await _audioQueue.timeout(operationTimeout);
        _check(epoch);
        _recording = false;
        if (_decoder!.hasTail) throw StateError('录音末尾含不完整的 PCM16 样本');
        if (_recordError != null) throw _recordError!;
        final text = await _asr.finish().timeout(operationTimeout);
        _check(epoch);
        final wav = _wav!;
        await wav.finish();
        _wav = null;
        final transcript = VoiceTranscript(
          text: text,
          isFinal: true,
          audioPath: wav.path,
          durationMs: wav.durationMs,
        );
        _lastFinal = transcript;
        // Port contract: stream is partial-only; final is returned once here.
        phase.value = VoicePhase.idle;
        return transcript;
      } catch (error) {
        _recordError ??= error;
        if (error is! VoiceCancelled && epoch == _epoch) _error(error);
        rethrow;
      } finally {
        try {
          await _cleanupRecording();
        } finally {
          _stopping = null;
        }
      }
    });
    _stopping = result;
    return result;
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    ++_epoch; // Ignore late native/text events before awaiting cleanup.
    _recordingTimer?.cancel();
    if (!(_outputCancelled?.isCompleted ?? true)) _outputCancelled!.complete();
    mouthActivity.value = 0;
    // Stop devices immediately, even if a download/start command is pending.
    final stopping = Future.wait([
      modelManager.cancel(),
      _asr.cancel(),
      _stopOutput(),
      _recorder.stop().timeout(operationTimeout),
    ]);
    unawaited(
      stopping.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    await _serial(() async {
      var failed = false;
      try {
        await stopping.timeout(operationTimeout);
      } catch (error) {
        failed = true;
        _error(error);
        rethrow;
      } finally {
        await _cleanupRecording();
        _lastFinal = null;
        _stopping = null;
        if (!_disposed && !failed) {
          phase.value = VoicePhase.idle;
        }
      }
    });
  }

  Future<void> _cleanupRecording() async {
    _recording = false;
    _recordingTimer?.cancel();
    _recordError ??= const VoiceCancelled();
    final subscription = _audioSubscription;
    _audioSubscription = null;
    // Every cleanup is attempted; a failed native stop cannot strand the WAV.
    for (final cleanup in <Future<void> Function()>[
      () => _recorder.stop(),
      () => _asr.cancel(),
      () async {
        await subscription?.cancel();
      },
      () => _audioQueue,
      () async {
        await _wav?.discard();
      },
    ]) {
      try {
        await cleanup().timeout(operationTimeout);
      } catch (error) {
        if (!_disposed && _lastError == null) _lastError = error.toString();
      }
    }
    _wav = null;
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    WidgetsBinding.instance.removeObserver(this);
    try {
      await cancel();
    } finally {
      _disposed = true;
      try {
        await Future.wait([
          _recorder.dispose(),
          _asr.dispose(),
          _speaker.dispose(),
          _playback.dispose(),
          modelManager.dispose(),
        ]).timeout(operationTimeout);
      } finally {
        await _transcripts.close();
        phase.dispose();
        mouthActivity.dispose();
      }
    }
  }
}
