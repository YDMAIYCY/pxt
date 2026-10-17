import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
  bool _voiceSelected = false;
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

    if (!_voiceSelected) await _selectChineseVoice(check);
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
      final accepted = await _tts.speak(
        text,
        focus: defaultTargetPlatform == TargetPlatform.android,
      );
      check();
      if (accepted != 1) throw StateError('系统 TTS 拒绝播报');
      await done.future;
    } catch (_) {
      // Re-discover after an engine failure or a system voice-data change.
      _voiceSelected = false;
      rethrow;
    } finally {
      if (identical(_done, done)) {
        _activity?.call(0);
        _activity = null;
        _done = null;
      }
    }
  }

  Future<void> _selectChineseVoice(void Function() check) async {
    if (await _selectFromCurrentEngine(check)) {
      _voiceSelected = true;
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final engines = await _tts.getEngines;
      check();
      for (final engine
          in (engines is List ? engines : const [])
              .whereType<String>()
              .toSet()) {
        try {
          await _tts.setEngine(engine);
          check();
          if (await _selectFromCurrentEngine(check)) {
            _voiceSelected = true;
            return;
          }
        } on VoiceCancelled {
          rethrow;
        } catch (_) {
          check();
          // One unavailable engine must not hide other installed engines.
        }
      }
    }
    throw StateError('未找到可用的中文语音，请在系统“文字转语音输出”中安装中文语音数据');
  }

  Future<bool> _selectFromCurrentEngine(void Function() check) async {
    try {
      final result = await _tts.getVoices;
      check();
      final voices = (result is List ? result : const [])
          .whereType<Map>()
          .where((voice) {
            final locale = voice['locale']
                .toString()
                .replaceAll('_', '-')
                .toLowerCase();
            return const [
                  'zh',
                  'zh-cn',
                  'zh-hans',
                  'zh-hans-cn',
                  'cmn',
                  'cmn-cn',
                ].contains(locale) &&
                voice['name'] != null &&
                !voice['features'].toString().toLowerCase().contains(
                  'notinstalled',
                );
          })
          .toList();
      bool network(Map voice) => const [
        'true',
        '1',
      ].contains(voice['network_required'].toString().toLowerCase());
      // Prefer local voices; some vendor engines only expose a network voice.
      voices.sort((a, b) => (network(a) ? 1 : 0).compareTo(network(b) ? 1 : 0));
      for (final voice in voices) {
        final selected = await _tts.setVoice({
          'name': voice['name'].toString(),
          'locale': voice['locale'].toString(),
        });
        check();
        if (selected == 1) return true;
      }
    } on VoiceCancelled {
      rethrow;
    } catch (_) {
      check();
    }
    // Vendor engines can support Mandarin without implementing getVoices.
    for (final locale in const ['zh-CN', 'zh-Hans', 'zh']) {
      try {
        final available = await _tts.isLanguageAvailable(locale);
        check();
        if (available != true && available != 1) continue;
        final selected = await _tts.setLanguage(locale);
        check();
        if (selected == 1) return true;
      } on VoiceCancelled {
        rethrow;
      } catch (_) {
        check();
      }
    }
    return false;
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
