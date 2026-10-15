import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

class InterviewMicrophoneCheck extends StatefulWidget {
  const InterviewMicrophoneCheck({
    this.enabled = true,
    this.recorderFactory,
    super.key,
  });
  final bool enabled;
  final AudioRecorder Function()? recorderFactory;

  @override
  State<InterviewMicrophoneCheck> createState() =>
      InterviewMicrophoneCheckState();
}

class InterviewMicrophoneCheckState extends State<InterviewMicrophoneCheck>
    with WidgetsBindingObserver {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  Future<Stream<Uint8List>?>? _opening;
  Future<void>? _cleanup;
  Timer? _timer;
  int _generation = 0;
  int _bytes = 0;
  double _level = 0;
  double _peak = 0;
  bool _testing = false;
  bool _requestingPermission = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(InterviewMicrophoneCheck oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) unawaited(_stopQuietly());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // System permission UI may report both inactive and paused on Android.
    if (state != AppLifecycleState.resumed && !_requestingPermission) {
      unawaited(_stopQuietly(message: '测试已暂停'));
    }
  }

  Future<Stream<Uint8List>?> _open(
    AudioRecorder recorder,
    int generation,
  ) async {
    _requestingPermission = true;
    bool permitted;
    try {
      permitted = await recorder.hasPermission().timeout(
        const Duration(seconds: 30),
      );
    } finally {
      _requestingPermission = false;
    }
    if (!mounted || generation != _generation) return null;
    if (!permitted) throw StateError('permission');
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return null;
    }
    if (!await recorder
        .isEncoderSupported(AudioEncoder.pcm16bits)
        .timeout(const Duration(seconds: 10))) {
      throw StateError('encoder');
    }
    if (!mounted || generation != _generation) return null;
    return recorder
        .startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: 16000,
            numChannels: 1,
          ),
        )
        .timeout(const Duration(seconds: 10));
  }

  Future<void> _start() async {
    if (_testing || !widget.enabled) return;
    // Set the guard before the first await, including cleanup and permission.
    setState(() {
      _testing = true;
      _message = '正在检测…';
    });
    try {
      await _cleanup;
    } catch (_) {}
    if (!mounted || !widget.enabled) {
      if (mounted) setState(() => _testing = false);
      return;
    }
    final generation = ++_generation;
    final recorder = _recorder =
        widget.recorderFactory?.call() ?? AudioRecorder();
    _bytes = 0;
    _peak = 0;
    _level = 0;
    final opening = _opening = _open(recorder, generation);
    try {
      final stream = await opening;
      if (!mounted || generation != _generation) return;
      if (stream == null) {
        await _stopQuietly(message: '测试已暂停');
        return;
      }
      setState(() => _message = '请说一句话');
      _subscription = stream.listen(
        (bytes) {
          if (!mounted || generation != _generation) return;
          final data = ByteData.sublistView(bytes);
          var energy = 0.0;
          final samples = bytes.length ~/ 2;
          for (var i = 0; i < samples; i++) {
            final value = data.getInt16(i * 2, Endian.little) / 32768.0;
            energy += value * value;
          }
          final level = samples == 0 ? 0.0 : math.sqrt(energy / samples);
          setState(() {
            _bytes += bytes.length;
            _level = (level * 5).clamp(0, 1);
            _peak = math.max(_peak, level);
          });
        },
        onError: (Object _) => unawaited(_stopQuietly(message: '检测失败，请重试')),
        onDone: () {
          if (generation == _generation) unawaited(_stopQuietly());
        },
      );
      _timer = Timer(
        const Duration(seconds: 5),
        () => unawaited(_stopQuietly()),
      );
    } catch (error) {
      if (generation == _generation) {
        await _stopQuietly(
          message: error is StateError && error.message == 'permission'
              ? '请允许麦克风权限'
              : '检测失败，请重试',
        );
      }
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  Future<void> stop({String? message}) {
    if (_recorder == null) return _cleanup ?? Future.value();
    ++_generation;
    _timer?.cancel();
    _timer = null;
    final recorder = _recorder!;
    final opening = _opening;
    final subscription = _subscription;
    _recorder = null;
    _subscription = null;
    final result =
        message ??
        (_bytes == 0
            ? '未收到声音，请重试'
            : _peak < .005
            ? '声音较轻，请靠近麦克风'
            : '麦克风正常');
    return _cleanup = _release(recorder, subscription, opening)
        .then(
          (_) {
            if (mounted) {
              setState(() {
                _testing = false;
                _level = 0;
                _message = result;
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _testing = false;
                _level = 0;
                _message = '麦克风未能停止，请重启应用';
              });
            }
            throw error;
          },
        )
        .whenComplete(() => _cleanup = null);
  }

  Future<void> _release(
    AudioRecorder recorder,
    StreamSubscription<Uint8List>? subscription,
    Future<Stream<Uint8List>?>? opening,
  ) async {
    // Finish the permission/start command before releasing its native owner.
    try {
      await opening;
    } catch (_) {}
    try {
      // The probe never saves audio. cancel avoids Android's file-stop callback.
      await recorder.cancel().timeout(const Duration(seconds: 10));
    } finally {
      await subscription?.cancel();
      await recorder.dispose().timeout(const Duration(seconds: 10));
    }
  }

  Future<void> _stopQuietly({String? message}) async {
    try {
      await stop(message: message);
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopQuietly());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: widget.enabled
            ? () async {
                if (_testing) {
                  await _stopQuietly();
                } else {
                  await _start();
                }
              }
            : null,
        icon: Icon(
          _testing ? Icons.stop_rounded : Icons.mic_none_rounded,
          size: 18,
        ),
        label: Text(_testing ? '停止检测' : '检测麦克风'),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _testing
            ? LinearProgressIndicator(value: _level, semanticsLabel: '麦克风音量')
            : Text(
                _message ?? '',
                style: Theme.of(context).textTheme.bodySmall,
              ),
      ),
    ],
  );
}
