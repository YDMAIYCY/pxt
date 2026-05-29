import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/database/models/ocr_text_record.dart';

void main() {
  test('OCR record prefers confirmed finalText for downstream generation', () {
    final record = OcrTextRecord.fromMap({
      'id': 1,
      'document_id': 2,
      'raw_text': 'raw noisy text',
      'clean_text': 'clean text',
      'final_text': 'confirmed final text',
      'quality_score': 42,
      'quality_level': 'low',
      'quality_reasons_json': '["ui_noise","ineffective_cleaning"]',
      'language': 'zh-CN',
      'created_at': '2026-05-29T00:00:00.000Z',
      'updated_at': '2026-05-29T00:00:00.000Z',
    });

    expect(record.finalText, 'confirmed final text');
    expect(record.effectiveText, 'confirmed final text');
    expect(record.qualityScore, 42);
    expect(record.qualityLevel, 'low');
    expect(record.qualityReasons, ['ui_noise', 'ineffective_cleaning']);
  });

  test('OCR record falls back to clean text when finalText is absent', () {
    final record = OcrTextRecord.fromMap({
      'id': 1,
      'document_id': 2,
      'raw_text': 'raw text',
      'clean_text': 'clean text',
      'language': 'zh-CN',
      'created_at': '2026-05-29T00:00:00.000Z',
      'updated_at': '2026-05-29T00:00:00.000Z',
    });

    expect(record.finalText, isNull);
    expect(record.effectiveText, 'clean text');
    expect(record.qualityScore, isNull);
    expect(record.qualityReasons, isEmpty);
  });
}
