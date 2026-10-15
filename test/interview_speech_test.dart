import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import 'package:pxt1/interview/interview_voice_port.dart';
import 'package:pxt1/interview/speech/offline_interview_voice_service.dart';
import 'package:pxt1/interview/speech/offline_model_manager.dart';
import 'package:pxt1/interview/speech/pcm_wav.dart';
import 'package:pxt1/interview/speech/sherpa_streaming_asr.dart';
import 'package:pxt1/interview/speech/voice_backends.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'PCM views and odd chunk boundaries preserve signed little-endian samples',
    () {
      final decoder = Pcm16Decoder();
      final backing = Uint8List.fromList([99, 0, 128, 255, 127, 88]);
      final first = decoder.decode(Uint8List.sublistView(backing, 1, 4));
      expect(first.samples, [-1.0]);
      expect(decoder.hasTail, isTrue);
      final second = decoder.decode(Uint8List.fromList([127]));
      expect(second.samples.single, closeTo(32767 / 32768, 0.00001));
      expect(decoder.hasTail, isFalse);
      expect([...first.bytes, ...second.bytes], [0, 128, 255, 127]);
    },
  );

  group('verified model installation', () {
    late Directory temp;
    late List<OfflineModelFile> specs;
    late OfflineModelManager models;
    final payload = [1, 2, 3, 4];
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('interview_model_test_');
      specs = [
        OfflineModelFile(
          'model.onnx',
          payload.length,
          sha256.convert(payload).toString(),
          'https://publisher.test/model',
        ),
      ];
    });
    tearDown(() async {
      await models.dispose();
      await temp.delete(recursive: true);
    });

    test(
      'progress reaches 1 only after hash validation and atomic install',
      () async {
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes(payload, 200)),
        );
        final progress = <double>[];
        await models.ensure(
          onProgress: (value) {
            progress.add(value);
            if (value == 1) expect(models.directory.existsSync(), isTrue);
          },
        );
        expect(models.ready, isTrue);
        expect(progress.first, 0);
        expect(progress.last, 1);
        expect(await models.directory.list().length, 1);
        expect(await models.inspect(), isTrue);
      },
    );

    test(
      'corrupt digest is rejected and no ready/partial files remain',
      () async {
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          clientFactory: () =>
              MockClient((_) async => http.Response.bytes([4, 3, 2, 1], 200)),
        );
        await expectLater(models.ensure(), throwsStateError);
        expect(models.ready, isFalse);
        expect(models.progress.value, lessThan(1));
        expect(await models.root.list().length, 0);
      },
    );

    test(
      'wrong length and HTTP failures do not install and can retry',
      () async {
        var attempt = 0;
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          clientFactory: () => MockClient((_) async {
            attempt++;
            if (attempt == 1) return http.Response.bytes([1, 2], 200);
            if (attempt == 2) return http.Response('unavailable', 503);
            return http.Response.bytes(payload, 200);
          }),
        );
        await expectLater(models.ensure(), throwsStateError);
        await expectLater(models.ensure(), throwsA(isA<HttpException>()));
        await models.ensure();
        expect(models.ready, isTrue);
        expect(attempt, 3);
      },
    );

    test(
      'cancel pending HTTP never produces ready or fake completion',
      () async {
        final response = Completer<http.Response>();
        final started = Completer<void>();
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          clientFactory: () => MockClient((_) {
            started.complete();
            return response.future;
          }),
        );
        final download = models.ensure();
        final expectation = expectLater(
          download,
          throwsA(isA<VoiceCancelled>()),
        );
        await started.future;
        await models.cancel();
        await expectation;
        response.complete(http.Response.bytes(payload, 200));
        expect(models.ready, isFalse);
        expect(models.downloading.value, isFalse);
        expect(models.progress.value, lessThan(1));
        expect(await models.root.list().length, 0);
      },
    );

    test('existing verified installation is reused without HTTP', () async {
      var requests = 0;
      models = OfflineModelManager(
        documentsDirectory: temp,
        files: specs,
        clientFactory: () => MockClient((_) async {
          requests++;
          return http.Response.bytes(payload, 200);
        }),
      );
      await models.ensure();
      await models.ensure();
      expect(requests, 1);
      expect(models.ready, isTrue);
    });

    test(
      'client initialization failure cleans stage and download state',
      () async {
        var fail = true;
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          clientFactory: () {
            if (fail) throw StateError('client initialization failed');
            return MockClient((_) async => http.Response.bytes(payload, 200));
          },
        );
        await expectLater(models.ensure(), throwsStateError);
        expect(models.downloading.value, isFalse);
        expect(await models.root.list().length, 0);
        fail = false;
        await models.ensure();
        expect(models.ready, isTrue);
      },
    );

    test(
      'stalled HTTP times out, closes client and remains retryable',
      () async {
        final client = _StalledClient();
        models = OfflineModelManager(
          documentsDirectory: temp,
          files: specs,
          timeout: const Duration(milliseconds: 30),
          clientFactory: () => client,
        );
        await expectLater(models.ensure(), throwsA(isA<TimeoutException>()));
        expect(client.closed, isTrue);
        expect(models.downloading.value, isFalse);
        expect(models.ready, isFalse);
        expect(await models.root.list().length, 0);
      },
    );

    test('cancel during body streaming removes staged files', () async {
      final body = StreamController<List<int>>();
      final requested = Completer<void>();
      models = OfflineModelManager(
        documentsDirectory: temp,
        files: specs,
        clientFactory: () => MockClient.streaming((_, _) async {
          requested.complete();
          return http.StreamedResponse(body.stream, 200);
        }),
      );
      final download = models.ensure();
      final failed = expectLater(download, throwsA(isA<VoiceCancelled>()));
      await requested.future;
      body.add([1, 2]);
      await Future<void>.delayed(Duration.zero);
      await models.cancel();
      await failed;
      expect(models.ready, isFalse);
      expect(models.downloading.value, isFalse);
      expect(await models.root.list().length, 0);
      await body.close();
    });
  });

  group('alternating voice turns', () {
    late Directory temp;
    late OfflineModelManager models;
    late _Recorder recorder;
    late _Asr asr;
    late _Speaker speaker;
    late _Playback playback;
    late OfflineInterviewVoiceService voice;
    setUp(() async {
      temp = await Directory.systemTemp.createTemp('interview_voice_test_');
      models = OfflineModelManager(
        documentsDirectory: temp,
        files: [
          OfflineModelFile(
            'model.onnx',
            1,
            sha256.convert([1]).toString(),
            'https://publisher.test/model',
          ),
        ],
        clientFactory: () =>
            MockClient((_) async => http.Response.bytes([1], 200)),
      );
      await models.ensure();
      recorder = _Recorder();
      asr = _Asr();
      speaker = _Speaker();
      playback = _Playback();
      voice = OfflineInterviewVoiceService(
        modelManager: models,
        recorder: recorder,
        asr: asr,
        speaker: speaker,
        playback: playback,
        operationTimeout: const Duration(milliseconds: 150),
      );
    });
    tearDown(() async {
      await voice.dispose();
      await temp.delete(recursive: true);
    });

    test(
      'implements shared port and returns a real complete WAV once',
      () async {
        expect(voice, isA<InterviewVoicePort>());
        final partials = <VoiceTranscript>[];
        final subscription = voice.transcripts.listen(partials.add);
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([0, 128, 255]));
        recorder.tail = Uint8List.fromList([127, 0, 0]);
        final result = await voice.stopRecording();
        await Future<void>.delayed(Duration.zero);
        expect(result.text, '中文回答');
        expect(result.isFinal, isTrue);
        expect(partials, isNotEmpty);
        expect(partials.every((t) => !t.isFinal), isTrue);
        final wav = await File(result.audioPath!).readAsBytes();
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
        expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 16000);
        expect(ByteData.sublistView(wav).getUint32(40, Endian.little), 6);
        expect(wav.sublist(44), [0, 128, 255, 127, 0, 0]);
        expect(asr.received.length, 3);
        expect(asr.finishes, 1);
        expect((await voice.stopRecording()).audioPath, result.audioPath);
        expect(asr.finishes, 1);
        await subscription.cancel();
      },
    );

    test(
      'WAV duration reflects real captured samples, without inference padding',
      () async {
        await voice.startRecording();
        recorder.data.add(Uint8List(32000));
        final result = await voice.stopRecording();
        expect(result.durationMs, 1000);
        expect(await File(result.audioPath!).length(), 32044);
      },
    );

    test(
      'recording stops TTS, ignores late lips, and never overlaps output',
      () async {
        final spoken = voice.speak('请介绍自己');
        final cancelled = expectLater(spoken, throwsA(isA<VoiceCancelled>()));
        await speaker.started.future;
        expect(voice.phase.value, VoicePhase.speaking);
        expect(voice.mouthActivity.value, greaterThan(0));
        await voice.startRecording();
        await cancelled;
        expect(speaker.active, isFalse);
        expect(playback.active, isFalse);
        speaker.activity?.call(1);
        expect(voice.mouthActivity.value, 0);
        expect(voice.phase.value, VoicePhase.recording);
        await expectLater(voice.speak('下一题'), throwsStateError);
        expect(recorder.active, isTrue);
      },
    );

    test(
      'cancel removes partial WAV and ignores delayed transcription',
      () async {
        await voice.startRecording();
        final partials = <VoiceTranscript>[];
        final subscription = voice.transcripts.listen(partials.add);
        asr.block = Completer<String>();
        recorder.data.add(Uint8List.fromList([1, 0]));
        await asr.accepted.future;
        await voice.cancel();
        expect(voice.phase.value, VoicePhase.idle);
        expect(voice.mouthActivity.value, 0);
        expect(recorder.active, isFalse);
        expect(partials, isEmpty);
        final recordings = Directory(p.join(models.root.path, 'recordings'));
        expect(await recordings.list().length, 0);
        await subscription.cancel();
      },
    );

    test(
      'device stream closure delivers a final transcript without a stop tap',
      () async {
        final finalResult = voice.transcripts.firstWhere((t) => t.isFinal);
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([0, 0, 1, 0]));
        await recorder.data.close();
        final result = await finalResult.timeout(const Duration(seconds: 2));
        expect(result.text, '中文回答');
        expect(result.audioPath, isNotNull);
        expect(voice.phase.value, VoicePhase.idle);
        expect(recorder.active, isFalse);
        expect((await voice.stopRecording()).audioPath, result.audioPath);
      },
    );

    test('native failure preserves error and emits no final', () async {
      await voice.startRecording();
      asr.failure = StateError('native decoder failed');
      recorder.data.add(Uint8List.fromList([1, 0]));
      await expectLater(voice.stopRecording(), throwsStateError);
      expect(voice.phase.value, VoicePhase.error);
      expect(voice.lastError, contains('native decoder failed'));
      expect(recorder.active, isFalse);
    });

    test(
      'missing stream close times out and cleans recording resources',
      () async {
        await voice.startRecording();
        recorder.closeOnStop = false;
        await expectLater(
          voice.stopRecording(),
          throwsA(isA<TimeoutException>()),
        );
        expect(voice.phase.value, VoicePhase.error);
        expect(voice.lastError, contains('TimeoutException'));
        expect(recorder.active, isFalse);
      },
    );

    test(
      'odd trailing PCM byte fails explicitly instead of silently truncating',
      () async {
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([1]));
        await expectLater(voice.stopRecording(), throwsStateError);
        expect(voice.lastError, contains('PCM16'));
      },
    );

    test(
      'saved recording playback waits completion and is cancelled before mic',
      () async {
        final file = File(p.join(temp.path, 'saved.wav'));
        await file.writeAsBytes([1]);
        final playing = voice.playRecording(file.path);
        final cancelled = expectLater(playing, throwsA(isA<VoiceCancelled>()));
        await playback.started.future;
        expect(voice.phase.value, VoicePhase.speaking);
        await voice.startRecording();
        await cancelled;
        expect(playback.active, isFalse);
        expect(voice.mouthActivity.value, 0);
      },
    );

    test(
      'settings roundtrip is controller owned and applied to speaking',
      () async {
        voice.settings = VoiceSettings.fromJson({'volume': 0.3, 'rate': 0.4});
        final speaking = voice.speakWithSettings('设置测试');
        await speaker.started.future;
        expect(speaker.volume, 0.3);
        expect(speaker.rate, 0.4);
        speaker.complete();
        await speaking;
        expect(voice.settings.toJson(), {'volume': 0.3, 'rate': 0.4});
        expect(voice.phase.value, VoicePhase.idle);
        expect(voice.mouthActivity.value, 0);
      },
    );

    test(
      'speech completion timeout stops backend and closes the mouth',
      () async {
        await voice.dispose();
        models = OfflineModelManager(documentsDirectory: temp);
        recorder = _Recorder();
        asr = _Asr();
        speaker = _Speaker();
        playback = _Playback();
        voice = OfflineInterviewVoiceService(
          modelManager: models,
          recorder: recorder,
          asr: asr,
          speaker: speaker,
          playback: playback,
          recordingLimit: const Duration(milliseconds: 30),
          operationTimeout: const Duration(milliseconds: 150),
        );
        await expectLater(
          voice.speak('不会发来结束事件'),
          throwsA(isA<TimeoutException>()),
        );
        expect(speaker.active, isFalse);
        expect(voice.mouthActivity.value, 0);
        expect(voice.phase.value, VoicePhase.error);
        speaker.activity?.call(1);
        expect(voice.mouthActivity.value, 0);
      },
    );

    test('dispose is idempotent, stops audio and prevents reuse', () async {
      await voice.startRecording();
      await voice.dispose();
      await voice.dispose();
      expect(recorder.disposed, isTrue);
      expect(asr.disposed, isTrue);
      expect(speaker.disposed, isTrue);
      expect(playback.disposed, isTrue);
      expect(() => voice.startRecording(), throwsStateError);
    });

    test(
      'background stops recording and rejects restart until resumed',
      () async {
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([1, 0]));
        voice.didChangeAppLifecycleState(AppLifecycleState.paused);
        await voice.cancel();
        expect(recorder.active, isFalse);
        expect(voice.mouthActivity.value, 0);
        await expectLater(
          voice.startRecording(),
          throwsA(isA<VoiceCancelled>()),
        );
        voice.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await voice.startRecording();
        expect(recorder.active, isTrue);
      },
    );

    test(
      'cancel racing with stop does not leave a stale stopping future',
      () async {
        await voice.startRecording();
        final stopped = voice.stopRecording();
        final rejected = expectLater(stopped, throwsA(isA<VoiceCancelled>()));
        await voice.cancel();
        await rejected;
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([1, 0]));
        expect((await voice.stopRecording()).isFinal, isTrue);
      },
    );

    test(
      'inference timeout skips backlog, cleans WAV and allows retry',
      () async {
        await voice.startRecording();
        asr.block = Completer<String>();
        recorder.data.add(Uint8List.fromList([1, 0]));
        await asr.accepted.future;
        for (var i = 0; i < 12; i++) {
          recorder.data.add(Uint8List.fromList([1, 0]));
        }
        await expectLater(
          voice.stopRecording(),
          throwsA(isA<TimeoutException>()),
        );
        expect(recorder.active, isFalse);
        expect(asr.received.length, 1);
        expect(
          await Directory(p.join(models.root.path, 'recordings')).list().length,
          0,
        );
        asr.block = null;
        await voice.startRecording();
        recorder.data.add(Uint8List.fromList([1, 0]));
        expect((await voice.stopRecording()).text, '中文回答');
      },
    );

    test(
      'background interrupts speech and late activity remains silent',
      () async {
        final spoken = voice.speak('正在播报');
        final rejected = expectLater(spoken, throwsA(isA<VoiceCancelled>()));
        await speaker.started.future;
        voice.didChangeAppLifecycleState(AppLifecycleState.hidden);
        await voice.cancel();
        await rejected;
        speaker.activity?.call(1);
        expect(speaker.active, isFalse);
        expect(voice.mouthActivity.value, 0);
      },
    );
  });

  // Opt-in actual model/native smoke. Never downloads during normal tests.
  final modelPath = Platform.environment['INTERVIEW_ASR_SMOKE'];
  test(
    'actual 14M native model loads and recognizes Chinese sample',
    () async {
      final asr = SherpaStreamingAsr(
        libraryDirectory: Platform.environment['INTERVIEW_ASR_LIBRARY'],
      );
      try {
        await asr.start(modelPath!);
        final file = File(Platform.environment['INTERVIEW_ASR_WAV']!);
        final wav = await file.readAsBytes();
        // Publisher samples include metadata chunks; PCM does not start at 44.
        final header = ByteData.sublistView(wav);
        int? offset;
        var length = 0;
        for (var i = 12; i + 8 <= wav.length;) {
          final size = header.getUint32(i + 4, Endian.little);
          final tag = String.fromCharCodes(wav.sublist(i, i + 4));
          if (tag == 'fmt ') {
            expect(header.getUint16(i + 8, Endian.little), 1);
            expect(header.getUint16(i + 10, Endian.little), 1);
            expect(header.getUint32(i + 12, Endian.little), 16000);
            expect(header.getUint16(i + 22, Endian.little), 16);
          }
          if (tag == 'data') {
            offset = i + 8;
            length = size;
            break;
          }
          i += 8 + size + size % 2;
        }
        expect(offset, isNotNull);
        expect(offset! + length, lessThanOrEqualTo(wav.length));
        final pcm = Pcm16Decoder();
        for (var i = offset; i < offset + length; i += 3200) {
          final end = i + 3200 < offset + length ? i + 3200 : offset + length;
          await asr.accept(
            pcm.decode(Uint8List.sublistView(wav, i, end)).samples,
          );
        }
        final text = await asr.finish();
        // A non-empty string alone is insufficient evidence of correct decoding.
        expect(text, contains('研究'));
        expect(text.runes.any((c) => c >= 0x4e00 && c <= 0x9fff), isTrue);
      } finally {
        await asr.dispose();
      }
    },
    skip: modelPath == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _StalledClient extends http.BaseClient {
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
  @override
  void close() => closed = true;
}

class _Recorder implements VoiceRecorder {
  StreamController<Uint8List> data = StreamController();
  Uint8List? tail;
  bool active = false;
  bool disposed = false;
  bool closeOnStop = true;
  @override
  Future<Stream<Uint8List>> start() async {
    if (data.isClosed) data = StreamController();
    active = true;
    return data.stream;
  }

  @override
  Future<void> stop() async {
    if (!active) return;
    active = false;
    if (tail != null) data.add(tail!);
    if (closeOnStop && !data.isClosed) await data.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!data.isClosed) unawaited(data.close());
  }
}

class _Asr implements VoiceAsrEngine {
  final received = <double>[];
  final accepted = Completer<void>();
  Completer<String>? block;
  Object? failure;
  int finishes = 0;
  bool disposed = false;
  @override
  Future<void> start(String directory) async {}
  @override
  Future<String> accept(Float32List samples) async {
    received.addAll(samples);
    if (!accepted.isCompleted) accepted.complete();
    if (failure != null) throw failure!;
    return block == null ? '中文' : await block!.future;
  }

  @override
  Future<String> finish() async {
    finishes++;
    return '中文回答';
  }

  @override
  Future<void> cancel() async {
    if (block != null && !block!.isCompleted) {
      block!.completeError(const VoiceCancelled());
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await cancel();
  }
}

class _Speaker implements VoiceSpeaker {
  final started = Completer<void>();
  Completer<void>? done;
  void Function(double)? activity;
  bool active = false;
  bool disposed = false;
  double? volume;
  double? rate;
  @override
  Future<void> speak(
    String text, {
    required double volume,
    required double rate,
    required void Function(double) onActivity,
  }) {
    this.volume = volume;
    this.rate = rate;
    active = true;
    activity = onActivity;
    onActivity(0.5);
    done = Completer<void>();
    if (!started.isCompleted) started.complete();
    return done!.future;
  }

  void complete() {
    active = false;
    if (!(done?.isCompleted ?? true)) done!.complete();
  }

  @override
  Future<void> stop() async {
    complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    complete();
  }
}

class _Playback implements VoicePlayback {
  final started = Completer<void>();
  Completer<void>? done;
  bool active = false;
  bool disposed = false;
  @override
  Future<void> play(String path) {
    active = true;
    done = Completer<void>();
    if (!started.isCompleted) started.complete();
    return done!.future;
  }

  @override
  Future<void> stop() async {
    active = false;
    if (!(done?.isCompleted ?? true)) done!.complete();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await stop();
  }
}
