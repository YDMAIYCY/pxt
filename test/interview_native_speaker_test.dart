import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pxt1/interview/speech/native_voice_backends.dart';
import 'package:pxt1/interview/speech/voice_backends.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late LocalChineseVoiceSpeaker speaker;
  late List<MethodCall> calls;
  late List<dynamic>? voices;
  late String engine;
  late bool languageAvailable;
  late bool rejectVoice;
  late Completer<void>? pendingVoices;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    calls = [];
    voices = [];
    engine = 'default';
    languageAvailable = false;
    rejectVoice = false;
    pendingVoices = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      switch (call.method) {
        case 'getVoices':
          await pendingVoices?.future;
          return engine == 'chinese.engine'
              ? [
                  {
                    'name': 'mandarin',
                    'locale': 'zh-CN',
                    'network_required': '0',
                  },
                ]
              : voices;
        case 'getEngines':
          return ['default', 'chinese.engine'];
        case 'setEngine':
          engine = call.arguments as String;
          return 1;
        case 'isLanguageAvailable':
          return languageAvailable;
        case 'setVoice':
          return rejectVoice ? 0 : 1;
        case 'speak':
          scheduleMicrotask(() {
            binding.defaultBinaryMessenger.handlePlatformMessage(
              'flutter_tts',
              const StandardMethodCodec().encodeMethodCall(
                const MethodCall('speak.onComplete'),
              ),
              (_) {},
            );
          });
          return 1;
        default:
          return 1;
      }
    });
    speaker = LocalChineseVoiceSpeaker();
  });
  tearDown(() async {
    await speaker.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> speak() => speaker
      .speak('请说明时间复杂度', volume: 0.6, rate: 0.4, onActivity: (_) {})
      .timeout(const Duration(seconds: 3));

  test('Chinese voice without network metadata is usable', () async {
    voices = [
      {'name': '中文', 'locale': 'zh_Hans'},
    ];
    await speak();
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    expect(calls.any((c) => c.method == 'setEngine'), isFalse);
    expect(calls.firstWhere((c) => c.method == 'setVolume').arguments, 0.6);
    expect(calls.firstWhere((c) => c.method == 'setSpeechRate').arguments, 0.4);
  });

  test('engine with null voice list can still speak Chinese', () async {
    voices = null;
    languageAvailable = true;
    await speak();
    expect(
      calls.any((c) => c.method == 'setLanguage' && c.arguments == 'zh-CN'),
      isTrue,
    );
    expect(calls.any((c) => c.method == 'setEngine'), isFalse);
  });

  test(
    'vendor Chinese network voice is usable when no local voice exists',
    () async {
      voices = [
        {'name': '系统中文', 'locale': 'zh-CN', 'network_required': '1'},
      ];
      await speak();
      expect(calls.any((c) => c.method == 'speak'), isTrue);
      expect(calls.any((c) => c.method == 'setEngine'), isFalse);
    },
  );

  test('local Chinese voice is preferred over a network voice', () async {
    voices = [
      {'name': 'network', 'locale': 'zh-CN', 'network_required': '1'},
      {'name': 'local', 'locale': 'zh-CN', 'network_required': '0'},
    ];
    await speak();
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments, {
      'name': 'local',
      'locale': 'zh-CN',
    });
  });

  test(
    'missing Chinese in default engine tries another installed engine',
    () async {
      await speak();
      expect(engine, 'chinese.engine');
      expect(calls.any((c) => c.method == 'speak'), isTrue);
    },
  );

  test('rejected voice is not treated as successful setup', () async {
    rejectVoice = true;
    await expectLater(speak(), throwsStateError);
    expect(calls.any((c) => c.method == 'speak'), isFalse);
  });

  test('stop during language discovery prevents late playback', () async {
    pendingVoices = Completer<void>();
    final result = speak();
    final cancelled = expectLater(result, throwsA(isA<VoiceCancelled>()));
    await Future<void>.delayed(Duration.zero);
    await speaker.stop();
    pendingVoices!.complete();
    await cancelled;
    expect(calls.any((c) => c.method == 'speak'), isFalse);
  });
}
