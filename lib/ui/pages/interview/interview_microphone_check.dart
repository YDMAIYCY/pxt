import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// A five-second local PCM check. Audio is discarded, never saved or uploaded.
class InterviewMicrophoneCheck extends StatefulWidget {
  const InterviewMicrophoneCheck({this.enabled = true, super.key});

  final bool enabled;

  @override
  State<InterviewMicrophoneCheck> createState() =>
      InterviewMicrophoneCheckState();
}

class InterviewMicrophoneCheckState extends State<InterviewMicrophoneCheck>
    with WidgetsBindingObserver {
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timer;
  Future<void>? _cleanup;
  int _generation = 0;
  int _bytes = 0;
  double _level = 0;
  double _peak = 0;
  bool _testing = false;
  bool _requestingPermission = false;
  String _message = '点击测试后，请说一句话。测试音频只在本机检测，不保存、不上传。';

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
    // A permission dialog may briefly make the foreground app inactive.
    if (state != AppLifecycleState.resumed &&
        !(state == AppLifecycleState.inactive && _requestingPermission)) {
      unawaited(_stopQuietly(message: '已停止麦克风测试，返回后可重新测试。'));
    }
  }

  Future<void> _start() async {
    if (_testing || !widget.enabled) return;
    try {
      await _cleanup;
    } catch (_) {
      // The failed release is already visible. Do not open another mic owner.
      return;
    }
    if (!mounted || !widget.enabled) return;
    final generation = ++_generation;
    final recorder = _recorder = AudioRecorder();
    setState(() {
      _testing = true;
      _bytes = 0;
      _level = 0;
      _peak = 0;
      _message = '正在检查麦克风权限…';
    });
    try {
      _requestingPermission = true;
      final permitted = await recorder.hasPermission().timeout(
        const Duration(seconds: 30),
      );
      _requestingPermission = false;
      if (!mounted || generation != _generation) return;
      if (!permitted) {
        await stop(message: '麦克风权限未开启，请在系统设置中允许后重试。');
        return;
      }
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await stop(message: '应用已离开前台，麦克风测试已停止。');
        return;
      }
      if (!await recorder
          .isEncoderSupported(AudioEncoder.pcm16bits)
          .timeout(const Duration(seconds: 10))) {
        await stop(message: '当前设备不支持麦克风 PCM 录音，仍可使用文字回答。');
        return;
      }
      if (!mounted || generation != _generation) return;
      final stream = await recorder
          .startStream(
            const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
              streamBufferSize: 3200,
            ),
          )
          .timeout(const Duration(seconds: 10));
      if (!mounted || generation != _generation) {
        await recorder.stop();
        return;
      }
      setState(() => _message = '正在录音测试（最多 5 秒），请对着麦克风说话…');
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
            _level = (level * 5).clamp(0.0, 1.0);
            _peak = math.max(_peak, level);
          });
        },
        onError: (Object error) =>
            unawaited(_stopQuietly(message: '麦克风测试失败：$error')),
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
        await _stopQuietly(message: '麦克风测试失败：$error');
      }
    } finally {
      _requestingPermission = false;
    }
  }

  /// Preparation must await this before opening a page that owns the mic.
  Future<void> stop({String? message}) {
    if (_recorder == null) return _cleanup ?? Future.value();
    ++_generation;
    _timer?.cancel();
    _timer = null;
    final recorder = _recorder!;
    final subscription = _subscription;
    _recorder = null;
    _subscription = null;
    final result =
        message ??
        (_bytes == 0
            ? '未收到录音数据，请检查麦克风后重试。'
            : _peak < 0.005
            ? '录音通道可用，但声音较弱或尚未说话，请靠近麦克风重试。'
            : '麦克风可用，已收到 ${(_bytes / 32000).toStringAsFixed(1)} 秒录音并检测到声音。');
    final cleanup = _release(recorder, subscription);
    _cleanup = cleanup;
    return cleanup.then(
      (_) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _level = 0;
          _message = result;
        });
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _testing = false;
          _level = 0;
          _message = '麦克风释放失败，请退出本页后重试：$error';
        });
        throw error;
      },
    );
  }

  Future<void> _release(
    AudioRecorder recorder,
    StreamSubscription<Uint8List>? subscription,
  ) async {
    try {
      await subscription?.cancel();
      await recorder.stop().timeout(const Duration(seconds: 10));
    } finally {
      await recorder.dispose().timeout(const Duration(seconds: 10));
    }
  }

  Future<void> _stopQuietly({String? message}) async {
    try {
      await stop(message: message);
    } catch (_) {
      // stop reports errors; timers and lifecycle callbacks must consume them.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stopQuietly());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      OutlinedButton.icon(
        onPressed: widget.enabled
            ? () async {
                if (_testing) {
                  await _stopQuietly();
                } else {
                  await _start();
                }
              }
            : null,
        icon: Icon(_testing ? Icons.stop_rounded : Icons.mic_none_rounded),
        label: Text(_testing ? '停止麦克风测试' : '测试麦克风'),
      ),
      if (_testing) ...[
        const SizedBox(height: 6),
        LinearProgressIndicator(value: _level, semanticsLabel: '麦克风音量'),
      ],
      const SizedBox(height: 6),
      Text(_message, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
