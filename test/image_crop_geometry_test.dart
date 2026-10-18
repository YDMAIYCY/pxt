import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:pxt1/common/image_crop_service.dart';

void main() {
  group('ImageCropGeometry', () {
    test('maps a normalized crop rect into the contained image area', () {
      final imageRect = ImageCropGeometry.containedImageRect(
        viewportSize: const Size(400, 300),
        imageSize: const Size(800, 400),
      );
      final cropRect = ImageCropGeometry.toViewportRect(
        normalizedRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
        containedImageRect: imageRect,
      );

      expect(imageRect, const Rect.fromLTWH(0, 50, 400, 200));
      expect(cropRect, const Rect.fromLTWH(100, 100, 200, 100));
    });

    test('clamps dragged selections to the image and a minimum size', () {
      final clamped = ImageCropGeometry.clampNormalizedRect(
        const Rect.fromLTWH(-0.2, 0.9, 0.1, 0.03),
      );

      expect(clamped.left, 0);
      expect(clamped.top, closeTo(0.82, 0.001));
      expect(clamped.width, closeTo(0.18, 0.001));
      expect(clamped.height, closeTo(0.18, 0.001));
    });
  });
}
