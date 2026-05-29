import 'dart:convert';

import '../llm/minimax_client.dart';

class OcrTextRepairResult {
  const OcrTextRepairResult({required this.finalText, required this.summary});

  final String finalText;
  final String summary;
}

class OcrTextRepairService {
  OcrTextRepairService({MiniMaxClient? client})
    : _client = client ?? MiniMaxClient();

  final MiniMaxClient _client;

  Future<OcrTextRepairResult> repair({
    required String rawText,
    required String cleanText,
  }) async {
    final response = await _client.generateStructuredJson(
      systemPrompt: _systemPrompt,
      userPrompt: _buildUserPrompt(rawText: rawText, cleanText: cleanText),
      jsonSchema: _jsonSchema,
    );

    final finalText = _readString(response, const [
      'final_text',
      'finalText',
      'text',
      'content',
    ]);
    if (finalText.trim().isEmpty) {
      throw const FormatException('AI 未返回可用的 final_text');
    }

    return OcrTextRepairResult(
      finalText: finalText.trim(),
      summary: _readString(response, const ['summary', 'notes']).trim(),
    );
  }

  static const String _systemPrompt = '''
你是 OCR 文本修复助手。你的任务是把拍照/截图 OCR 得到的杂乱文本整理成可进入知识库和 AI 生成流程的 finalText。
要求：
1. 去掉浏览器、工具栏、页面按钮、时间、电量、路径、无关应用 UI 噪声。
2. 保留原始学习内容，不要凭空补充知识点。
3. 如果文本可读，整理为清晰的 Markdown 标题、短句和列表。
4. 如果内容缺失或不确定，用「[不确定]」标注，不要强行编造。
只返回 JSON。
''';

  static String _buildUserPrompt({
    required String rawText,
    required String cleanText,
  }) {
    return const JsonEncoder.withIndent('  ').convert({
      'task': 'repair_ocr_text',
      'rawText': rawText,
      'cleanText': cleanText,
      'output': {
        'final_text': '整理后的 Markdown 文本',
        'summary': '一句话说明删除了哪些噪声或做了哪些结构化处理',
      },
    });
  }

  static const Map<String, dynamic> _jsonSchema = {
    'type': 'object',
    'properties': {
      'final_text': {'type': 'string'},
      'summary': {'type': 'string'},
    },
    'required': ['final_text'],
  };

  static String _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }
}
