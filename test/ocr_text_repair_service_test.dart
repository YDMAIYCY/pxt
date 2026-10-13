import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/llm/minimax_client.dart';
import 'package:pxt1/ocr/ocr_text_repair_service.dart';

void main() {
  test('AI OCR repair returns structured final text from model JSON', () async {
    final client = _FakeMiniMaxClient({
      'final_text': '''
函数的定义与理解

一句话：函数就是一种“输入 → 处理 → 输出”的固定规则。

- 输入：x
- 规则：f
- 输出：y
''',
      'summary': '已去除浏览器和工具栏噪声',
    });
    final service = OcrTextRepairService(client: client);

    final result = await service.repair(
      rawText: 'YCY/pxt PageAgent 视频生成 16:34 函数是什么？',
      cleanText: 'YCY/pxt PageAgent 视频生成 16:34 函数是什么？',
    );

    expect(result.finalText, contains('函数的定义与理解'));
    expect(result.finalText, contains('输入 → 处理 → 输出'));
    expect(result.summary, contains('噪声'));
    expect(client.lastUserPrompt, contains('rawText'));
    expect(client.lastUserPrompt, contains('cleanText'));
  });
}

class _FakeMiniMaxClient extends MiniMaxClient {
  _FakeMiniMaxClient(this.response);

  final Map<String, dynamic> response;
  String lastUserPrompt = '';

  @override
  Future<Map<String, dynamic>> generateStructuredJson({
    required String systemPrompt,
    required String userPrompt,
    Map<String, dynamic>? jsonSchema,
    List<({String base64, String mimeType})>? images,
  }) async {
    lastUserPrompt = userPrompt;
    return response;
  }
}
