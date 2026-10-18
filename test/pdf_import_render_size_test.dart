import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/camera/image_input_service.dart';

void main() {
  group('PDF import render sizing', () {
    test('caps normal A4 pages to the safe longest side', () {
      final size = resolvePdfPageRenderSizeForTest(
        pageWidth: 595,
        pageHeight: 842,
      );

      expect(size['height'], lessThanOrEqualTo(1600));
      expect(size['width']! * size['height']!, lessThanOrEqualTo(2200000));
    });

    test('downscales oversized poster pages before rendering', () {
      final size = resolvePdfPageRenderSizeForTest(
        pageWidth: 3600,
        pageHeight: 5400,
      );

      expect(size['height'], lessThanOrEqualTo(1600));
      expect(size['width']! * size['height']!, lessThanOrEqualTo(2200000));
    });

    test('rejects invalid page size', () {
      expect(
        () => resolvePdfPageRenderSizeForTest(pageWidth: 0, pageHeight: 842),
        throwsStateError,
      );
    });
  });
}
