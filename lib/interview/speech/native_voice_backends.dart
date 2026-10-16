import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';

import 'voice_backends.dart';

class RecordVoiceRecorder implements VoiceRecorder {
  final _recorder = AudioRecorder();
  int _epoch = 0;

  @override
  Future<Stream<Uint8List>> start() async {
    final epoch = ++_epoch;
    if (!await _recorder.hasPermission()) throw StateError('请允许麦克风权限');
    if (epoch != _epoch) throw const VoiceCancelled();
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw StateError('当前设备不支持 PCM16 麦克风流');
    }
    if (epoch != _epoch) throw const VoiceCancelled();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );
    if (epoch != _epoch) {
      await _recorder.cancel();
      throw const VoiceCancelled();
    }
    return stream;
  }

  @override
  Future<void> stop() async {
    ++_epoch;
    // PCM is persisted by our WAV writer. There is no native file to finalize.
    await _recorder.cancel();
  }

  @override
  Future<void> dispose() async {
    ++_epoch;
    await _recorder.dispose();
  }
}

class LocalChineseVoiceSpeaker implements VoiceSpeaker {
  LocalChineseVoiceSpeaker() {
    _tts.setStartHandler(() => _activity?.call(0.5));
    _tts.setProgressHandler((_, _, _, _) => _activity?.call(0.7));
    _tts.setCompletionHandler(_complete);
    _tts.setCancelHandler(_complete);
    _tts.setErrorHandler((message) {
      final done = _done;
      if (done != null && !done.isCompleted) {
        done.completeError(StateError(message));
      }
      _activity?.call(0);
    });
  }

  final _tts = FlutterTts();
  Completer<void>? _done;
  void Function(double)? _activity;
  int _epoch = 0;
  void _complete() {
    if (!(_done?.isCompleted ?? true)) _done!.complete();
    _activity?.call(0);
  }

  @override
  Future<void> speak(
    String text, {
    required double volume,
    required double rate,
    required void Function(double) onActivity,
  }) async {
    final epoch = ++_epoch;
    void check() {
      if (epoch != _epoch) throw const VoiceCancelled();
    }

    final voices = await _tts.getVoices as List<dynamic>;
    check();
    final available = voices.whereType<Map>().where((voice) {
      final locale = voice['locale']
          .toString()
          .replaceAll('_', '-')
          .toLowerCase();
      final network = voice['network_required'];
      final local =
          network == false ||
          network == 'false' ||
          network == 0 ||
          network == '0';
      final installed = !voice['features'].toString().contains('notInstalled');
      return (locale == 'zh-cn' || locale == 'zh-hans-cn') &&
          installed &&
          (Platform.isAndroid ? local : network != true && network != 'true');
    });
    if (available.isEmpty) {
      throw StateError('未找到可用的中文离线语音，请在系统设置的“文字转语音输出”中选择中文引擎');
    }
    final voice = available.first;
    await _tts.setVoice({
      'name': voice['name'].toString(),
      'locale': voice['locale'].toString(),
    });
    check();
    await _tts.setVolume(volume);
    check();
    await _tts.setSpeechRate(rate);
    check();
    await _tts.awaitSpeakCompletion(false);
    check();
    final done = _done = Completer<void>();
    _activity = onActivity;
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      final accepted = await _tts.speak(text, focus: Platform.isAndroid);
      check();
      if (accepted != 1) throw StateError('系统 TTS 拒绝播报');
      await done.future;
    } finally {
      if (identical(_done, done)) {
        _activity?.call(0);
        _activity = null;
        _done = null;
      }
    }
  }

  @override
  Future<void> stop() async {
    ++_epoch;
    try {
      await _tts.stop();
    } finally {
      _complete();
      _activity = null;
    }
  }

  @override
  Future<void> dispose() => stop();
}

class SavedRecordingPlayback implements VoicePlayback {
  final _player = AudioPlayer();
  Completer<void>? _done;
  int _epoch = 0;

  @override
  Future<void> play(String path) async {
    final epoch = ++_epoch;
    final done = _done = Completer<void>();
    final completeSubscription = _player.onPlayerComplete.listen((_) {
      if (epoch == _epoch && !done.isCompleted) done.complete();
    });
    final errorSubscription = _player.onLog.listen(
      (_) {},
      onError: (Object error) {
        if (!done.isCompleted) done.completeError(error);
      },
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    try {
      await _player.play(DeviceFileSource(path));
      if (epoch != _epoch) {
        await _player.stop();
        throw const VoiceCancelled();
      }
      await done.future;
    } finally {
      await completeSubscription.cancel();
      await errorSubscription.cancel();
      if (identical(_done, done)) _done = null;
    }
  }

  @override
  Future<void> stop() async {
    ++_epoch;
    final done = _done;
    try {
      await _player.stop();
    } finally {
      if (!(done?.isCompleted ?? true)) done!.complete();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
