import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'voice_backends.dart';

/// Native handles live only in the worker and are freed before normal shutdown.
class SherpaStreamingAsr implements VoiceAsrEngine {
  SherpaStreamingAsr({
    this.libraryDirectory,
    this.requestTimeout = const Duration(seconds: 20),
    this.shutdownTimeout = const Duration(seconds: 20),
  });
  final String? libraryDirectory;
  final Duration requestTimeout;
  final Duration shutdownTimeout;
  Isolate? _isolate;
  ReceivePort? _receive;
  SendPort? _send;
  Completer<SendPort>? _handshake;
  Completer<void>? _exited;
  Future<void>? _cancelling;
  String? _modelDirectory;
  int _generation = 0;
  bool _disposed = false;
  final _pending = <int, Completer<String>>{};
  int _requestId = 0;

  @override
  Future<void> start(String modelDirectory) async {
    if (_disposed) throw StateError('离线识别器已释放');
    await _cancelling;
    if (_disposed) throw StateError('离线识别器已释放');
    if (_send != null && _modelDirectory != modelDirectory) await cancel();
    final generation = _generation;
    if (_send == null) {
      final receive = _receive = ReceivePort();
      final handshake = _handshake = Completer<SendPort>();
      final exited = _exited = Completer<void>();
      unawaited(
        handshake.future.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
      receive.listen((message) {
        if (message is SendPort) {
          if (!handshake.isCompleted) handshake.complete(message);
        } else if (message is List && message.length == 3) {
          final request = _pending.remove(message[0]);
          if (request == null) return;
          if (message[1] == 'ok') {
            request.complete(message[2] as String);
          } else {
            request.completeError(StateError(message[2] as String));
          }
        } else if (message == null) {
          if (!exited.isCompleted) exited.complete();
          if (_receive == receive) {
            unawaited(cancel().catchError((Object _) {}));
          }
        } else if (message is List && _receive == receive) {
          if (!handshake.isCompleted) {
            handshake.completeError(StateError('离线识别工作线程失败：$message'));
          }
          unawaited(cancel().catchError((Object _) {}));
        }
      });
      final Isolate isolate;
      try {
        isolate = await Isolate.spawn(
          _asrWorker,
          [receive.sendPort, modelDirectory, libraryDirectory],
          onExit: receive.sendPort,
          onError: receive.sendPort,
          errorsAreFatal: true,
        );
      } catch (_) {
        await cancel();
        rethrow;
      }
      if (_receive != receive || generation != _generation || _disposed) {
        isolate.kill(priority: Isolate.immediate);
        throw const VoiceCancelled();
      }
      _isolate = isolate;
      try {
        _send = await handshake.future.timeout(requestTimeout);
      } catch (_) {
        await cancel();
        rethrow;
      }
      if (generation != _generation || _disposed) throw const VoiceCancelled();
      _modelDirectory = modelDirectory;
    }
    try {
      await _request('start', null);
    } catch (_) {
      await cancel();
      rethrow;
    }
  }

  Future<String> _request(String command, Object? payload) {
    if (_send == null) return Future.error(const VoiceCancelled());
    final id = ++_requestId;
    final result = Completer<String>();
    _pending[id] = result;
    _send!.send([id, command, payload]);
    return result.future.timeout(
      requestTimeout,
      onTimeout: () {
        unawaited(cancel().catchError((Object _) {}));
        throw TimeoutException('离线语音推理超时');
      },
    );
  }

  @override
  Future<String> accept(Float32List samples) => _request('audio', samples);
  @override
  Future<String> finish() => _request('finish', null);

  @override
  Future<void> cancel() {
    if (_cancelling != null) return _cancelling!;
    final result = _cancel();
    _cancelling = result;
    void clear() {
      if (identical(_cancelling, result)) _cancelling = null;
    }

    unawaited(result.then((_) => clear(), onError: (Object _) => clear()));
    return result;
  }

  Future<void> _cancel() async {
    ++_generation;
    final isolate = _isolate;
    final receive = _receive;
    final send = _send;
    final exited = _exited;
    _isolate = null;
    _send = null;
    _receive = null;
    _modelDirectory = null;
    if (!(_handshake?.isCompleted ?? true)) {
      _handshake!.completeError(const VoiceCancelled());
    }
    for (final request in _pending.values) {
      if (!request.isCompleted) request.completeError(const VoiceCancelled());
    }
    _pending.clear();
    try {
      if (isolate != null && send != null) {
        // Killing an isolate alone does not run recognizer.free(). Let the
        // worker drain its current native call and explicitly free both handles.
        send.send([0, 'dispose', null]);
        await exited!.future.timeout(shutdownTimeout);
      } else {
        isolate?.kill(priority: Isolate.immediate);
      }
    } on TimeoutException {
      // A native call that never returns has no safe in-process destructor.
      isolate?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      receive?.close();
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await cancel();
  }
}

void _asrWorker(List<Object?> args) {
  final parent = args[0] as SendPort;
  final directory = args[1] as String;
  final libraryDirectory = args[2] as String?;
  final receive = ReceivePort();
  parent.send(receive.sendPort);
  sherpa.OnlineRecognizer? recognizer;
  sherpa.OnlineStream? stream;
  var completed = '';
  void decode() {
    while (recognizer!.isReady(stream!)) {
      recognizer!.decode(stream!);
    }
  }

  receive.listen((message) {
    final request = message as List;
    final id = request[0];
    try {
      var text = '';
      switch (request[1]) {
        case 'start':
          if (recognizer == null) {
            if (Platform.isWindows) {
              // Windows searches System32 before PATH for dependent DLLs. Load
              // the bundled runtime explicitly instead of Windows' older ORT.
              final nativeDirectory =
                  libraryDirectory ??
                  File(Platform.resolvedExecutable).parent.path;
              DynamicLibrary.open(p.join(nativeDirectory, 'onnxruntime.dll'));
            }
            sherpa.initBindings(libraryDirectory);
            recognizer = sherpa.OnlineRecognizer(
              sherpa.OnlineRecognizerConfig(
                model: sherpa.OnlineModelConfig(
                  transducer: sherpa.OnlineTransducerModelConfig(
                    encoder: p.join(
                      directory,
                      'encoder-epoch-99-avg-1.int8.onnx',
                    ),
                    decoder: p.join(
                      directory,
                      'decoder-epoch-99-avg-1.int8.onnx',
                    ),
                    joiner: p.join(
                      directory,
                      'joiner-epoch-99-avg-1.int8.onnx',
                    ),
                  ),
                  tokens: p.join(directory, 'tokens.txt'),
                  modelType: 'zipformer',
                  provider: 'cpu',
                  numThreads: 1,
                  debug: false,
                ),
              ),
            );
          }
          stream?.free();
          stream = recognizer!.createStream();
          completed = '';
        case 'audio':
          stream!.acceptWaveform(
            samples: request[2] as Float32List,
            sampleRate: 16000,
          );
          decode();
          final current = recognizer!.getResult(stream!).text;
          text = '$completed$current'.trim();
          if (recognizer!.isEndpoint(stream!)) {
            completed = text;
            recognizer!.reset(stream!);
          }
        case 'finish':
          // Tail context is inference-only; it is not added to the saved WAV.
          stream!.acceptWaveform(samples: Float32List(8000), sampleRate: 16000);
          stream!.inputFinished();
          decode();
          text = '$completed${recognizer!.getResult(stream!).text}'.trim();
          stream!.free();
          stream = null;
        case 'dispose':
          stream?.free();
          stream = null;
          recognizer?.free();
          recognizer = null;
          receive.close();
      }
      parent.send([id, 'ok', text]);
    } catch (error) {
      parent.send([id, 'error', error.toString()]);
    }
  });
}
