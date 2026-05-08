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
}
