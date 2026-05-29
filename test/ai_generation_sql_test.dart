import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository SQL does not inline localized document title fallbacks', () {
    final source = File(
      'lib/database/ai_generation_repository.dart',
    ).readAsStringSync();
    final unsafeFallbacks = RegExp(
      r"COALESCE\(documents\.original_title,\s*'(?!'\))",
    ).allMatches(source);

    expect(unsafeFallbacks, isEmpty);
  });

  test('generated-result queries exclude wrong-question similar drills', () {
    final source = File(
      'lib/database/ai_generation_repository.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'questions\.question_kind\s*=\s*\?').allMatches(source).length,
      greaterThanOrEqualTo(2),
    );
    expect(
      RegExp(r'PracticeQuestionKind\.normal').allMatches(source).length,
      greaterThanOrEqualTo(3),
    );
  });

  test('deleting a knowledge library deletes its study packages too', () {
    final source = File(
      'lib/database/knowledge_library_repository.dart',
    ).readAsStringSync();

    expect(source, contains('AppDatabase.tableDocumentBatches'));
    expect(source, contains("where: 'user_id = ? AND library_id = ?'"));
  });
}
