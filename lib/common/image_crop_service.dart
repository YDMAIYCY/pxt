import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

class ImageCropGeometry {
  const ImageCropGeometry._();

  static const double minNormalizedSize = 0.18;

  static Rect containedImageRect({
    required Size viewportSize,
    required Size imageSize,
  }) {
    if (viewportSize.isEmpty || imageSize.isEmpty) {
      return Rect.zero;
    }

    final fittedScale = math.min(
      viewportSize.width / imageSize.width,
      viewportSize.height / imageSize.height,
    );
    final fittedSize = Size(
      imageSize.width * fittedScale,
      imageSize.height * fittedScale,
    );
    return Offset(
          (viewportSize.width - fittedSize.width) / 2,
          (viewportSize.height - fittedSize.height) / 2,
        ) &
        fittedSize;
  }

  static Rect toViewportRect({
    required Rect normalizedRect,
    required Rect containedImageRect,
  }) {
    final clamped = clampNormalizedRect(normalizedRect);
    return Rect.fromLTWH(
      containedImageRect.left + clamped.left * containedImageRect.width,
      containedImageRect.top + clamped.top * containedImageRect.height,
      clamped.width * containedImageRect.width,
      clamped.height * containedImageRect.height,
    );
  }

  static Rect fromViewportRect({
    required Rect viewportRect,
    required Rect containedImageRect,
  }) {
    if (containedImageRect.isEmpty) {
      return const Rect.fromLTWH(0.08, 0.08, 0.84, 0.84);
    }
    return clampNormalizedRect(
      Rect.fromLTRB(
        (viewportRect.left - containedImageRect.left) /
            containedImageRect.width,
        (viewportRect.top - containedImageRect.top) / containedImageRect.height,
        (viewportRect.right - containedImageRect.left) /
            containedImageRect.width,
        (viewportRect.bottom - containedImageRect.top) /
            containedImageRect.height,
      ),
    );
  }

  static Rect clampNormalizedRect(Rect rect) {
    var width = rect.width.abs();
    var height = rect.height.abs();
    width = width < minNormalizedSize ? minNormalizedSize : width;
    height = height < minNormalizedSize ? minNormalizedSize : height;
    width = width > 1 ? 1 : width;
    height = height > 1 ? 1 : height;

    var left = rect.left < rect.right ? rect.left : rect.right;
    var top = rect.top < rect.bottom ? rect.top : rect.bottom;
    if (left < 0) left = 0;
    if (top < 0) top = 0;
    if (left + width > 1) left = 1 - width;
    if (top + height > 1) top = 1 - height;

    return Rect.fromLTWH(left, top, width, height);
  }
}

class ImageCropService {
  const ImageCropService();

  Future<Size> readImageSize(String imagePath) async {
    final image = await _decodeImage(imagePath);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    return size;
  }

  Future<String> cropToNewFile({
    required String sourcePath,
    required Rect normalizedRect,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw StateError('图片文件不存在，无法裁剪');
    }

    final image = await _decodeImage(sourcePath);
    final cropRect = _toImagePixelRect(
      normalizedRect: normalizedRect,
      imageWidth: image.width,
      imageHeight: image.height,
    );
    if (cropRect.width < 2 || cropRect.height < 2) {
      image.dispose();
      throw StateError('框选区域太小，请重新选择');
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final targetRect = Rect.fromLTWH(0, 0, cropRect.width, cropRect.height);
    canvas.drawImageRect(image, cropRect, targetRect, Paint());
    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(
      cropRect.width.round(),
      cropRect.height.round(),
    );
    picture.dispose();
    image.dispose();

    final byteData = await croppedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    croppedImage.dispose();
    if (byteData == null) {
      throw StateError('裁剪图片编码失败');
    }

    final outputPath = _buildOutputPath(sourcePath);
    await File(
      outputPath,
    ).writeAsBytes(byteData.buffer.asUint8List(), flush: true);
    return outputPath;
  }

  Future<ui.Image> _decodeImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return frame.image;
  }

  Rect _toImagePixelRect({
    required Rect normalizedRect,
    required int imageWidth,
    required int imageHeight,
  }) {
    final rect = ImageCropGeometry.clampNormalizedRect(normalizedRect);
    return Rect.fromLTWH(
      rect.left * imageWidth,
      rect.top * imageHeight,
      rect.width * imageWidth,
      rect.height * imageHeight,
    ).intersect(
      Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()),
    );
  }

  String _buildOutputPath(String sourcePath) {
    final directory = p.dirname(sourcePath);
    final baseName = p.basenameWithoutExtension(sourcePath);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return p.join(directory, '${baseName}_crop_$timestamp.png');
  }
}
