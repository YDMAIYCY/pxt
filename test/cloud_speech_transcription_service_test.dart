import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pxt1/database/models/llm_provider_config.dart';
import 'package:pxt1/generator/cloud_speech_transcription_service.dart';

void main() {
  test('uploads audio to OpenAI-compatible transcription endpoint', () async {
    late Uri requestedUri;
    late String authorization;
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'pxt_test_audio_${DateTime.now().microsecondsSinceEpoch}.m4a',
    );
    await tempFile.writeAsBytes([1, 2, 3, 4]);
    addTearDown(() async {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    });

    final service = CloudSpeechTranscriptionService(
      httpClient: MockClient((request) async {
        requestedUri = request.url;
        authorization = request.headers['Authorization'] ?? '';
        return http.Response.bytes(
          utf8.encode(jsonEncode({'text': '函数是映射关系'})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final text = await service.transcribeAudioFile(
      audioPath: tempFile.path,
      config: LlmProviderConfig.emptyForUser(1).copyWith(
        provider: 'openai',
        apiKey: 'sk-test',
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-5.4-mini',
      ),
    );

    expect(text, '函数是映射关系');
    expect(
      requestedUri.toString(),
      'https://api.openai.com/v1/audio/transcriptions',
    );
    expect(authorization, 'Bearer sk-test');
  });
}
