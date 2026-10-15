import 'dart:typed_data';

class VoiceSettings {
  const VoiceSettings({this.volume = 1, this.rate = 0.5});

  final double volume;
  final double rate;

  Map<String, Object> toJson() => {'volume': volume, 'rate': rate};

  factory VoiceSettings.fromJson(Map<String, dynamic> json) => VoiceSettings(
    volume: (json['volume'] as num?)?.toDouble() ?? 1,
    rate: (json['rate'] as num?)?.toDouble() ?? 0.5,
  );
}

class VoiceCancelled implements Exception {
  const VoiceCancelled();
  @override
  String toString() => '语音操作已取消';
}

abstract interface class VoiceRecorder {
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class VoiceAsrEngine {
  Future<void> start(String modelDirectory);
  Future<String> accept(Float32List samples);
  Future<String> finish();
  Future<void> cancel();
  Future<void> dispose();
}

abstract interface class VoiceSpeaker {
  /// Completes after playback ends, or after stop has stopped playback.
  Future<void> speak(
    String text, {
    required double volume,
    required double rate,
    required void Function(double) onActivity,
  });
  Future<void> stop();
  Future<void> dispose();
}

abstract interface class VoicePlayback {
  /// Completes after playback ends, or after stop has stopped playback.
  Future<void> play(String path);
  Future<void> stop();
  Future<void> dispose();
}
