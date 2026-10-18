import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/ocr/ocr_text_quality_evaluator.dart';

void main() {
  group('OCR text quality evaluator', () {
    test('flags noisy screen captures whose cleaner made no useful change', () {
      final result = OcrTextQualityEvaluator.evaluate(
        rawText: '''
YCY/pxt
0数学定义与理解豆包
□ 绘图 □ 素材 PageAgent 视频生成 更多
16:34
函数是什么？
一句话：函数就是一种“输入—处理—输出”的固定规则。
''',
        cleanText: '''
YCY/pxt
0数学定义与理解豆包
□ 绘图 □ 素材 PageAgent 视频生成 更多
16:34
函数是什么？
一句话：函数就是一种“输入—处理—输出”的固定规则。
''',
      );

      expect(result.isUsableForAutomation, isFalse);
      expect(result.level, OcrQualityLevel.low);
      expect(result.reasons, contains(OcrQualityReason.uiNoise));
      expect(result.reasons, contains(OcrQualityReason.ineffectiveCleaning));
    });

    test('accepts readable structured study text', () {
      final result = OcrTextQualityEvaluator.evaluate(
        rawText: '''
函数的定义与理解
一句话：函数就是一种“输入 → 处理 → 输出”的固定规则。
通俗理解：
- 你给它一个输入
- 它按固定规则算出结果
- 最后返回一个输出
数学里的函数写成：y = f(x)
''',
        cleanText: '''
函数的定义与理解
一句话：函数就是一种“输入 → 处理 → 输出”的固定规则。
通俗理解：
- 你给它一个输入
- 它按固定规则算出结果
- 最后返回一个输出
数学里的函数写成：y = f(x)
''',
      );

      expect(result.isUsableForAutomation, isTrue);
      expect(result.level, isNot(OcrQualityLevel.low));
    });
  });
}
