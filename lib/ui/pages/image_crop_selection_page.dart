import 'dart:io';

import 'package:flutter/material.dart';

import '../../common/image_crop_service.dart';
import '../theme/app_theme.dart';

class ImageCropSelectionPage extends StatefulWidget {
  const ImageCropSelectionPage({
    required this.imagePath,
    this.cropService = const ImageCropService(),
    super.key,
  });

  final String imagePath;
  final ImageCropService cropService;

  @override
  State<ImageCropSelectionPage> createState() => _ImageCropSelectionPageState();
}

class _ImageCropSelectionPageState extends State<ImageCropSelectionPage> {
  static const Rect _defaultSelection = Rect.fromLTWH(0.08, 0.08, 0.84, 0.84);

  late Future<Size> _imageSizeFuture;
  Rect _selection = _defaultSelection;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _imageSizeFuture = widget.cropService.readImageSize(widget.imagePath);
  }

  Future<void> _confirmCrop() async {
    if (_isCropping) {
      return;
    }
    setState(() => _isCropping = true);
    try {
      final croppedPath = await widget.cropService.cropToNewFile(
        sourcePath: widget.imagePath,
        normalizedRect: _selection,
      );
      if (mounted) {
        Navigator.of(context).pop(croppedPath);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('裁剪失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isCropping = false);
      }
    }
  }

  void _moveSelection(DragUpdateDetails details, Rect imageRect) {
    final delta = Offset(
      details.delta.dx / imageRect.width,
      details.delta.dy / imageRect.height,
    );
    setState(() {
      _selection = ImageCropGeometry.clampNormalizedRect(
        _selection.shift(delta),
      );
    });
  }

  void _resizeSelection(
    DragUpdateDetails details,
    Rect imageRect,
    _CropHandle handle,
  ) {
    final dx = details.delta.dx / imageRect.width;
    final dy = details.delta.dy / imageRect.height;
    var left = _selection.left;
    var top = _selection.top;
    var right = _selection.right;
    var bottom = _selection.bottom;

    switch (handle) {
      case _CropHandle.topLeft:
        left += dx;
        top += dy;
        break;
      case _CropHandle.topRight:
        right += dx;
        top += dy;
        break;
      case _CropHandle.bottomLeft:
        left += dx;
        bottom += dy;
        break;
      case _CropHandle.bottomRight:
        right += dx;
        bottom += dy;
        break;
    }

    setState(() {
      _selection = ImageCropGeometry.clampNormalizedRect(
        Rect.fromLTRB(left, top, right, bottom),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('框选 OCR 范围'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isCropping
                ? null
                : () => setState(() => _selection = _defaultSelection),
            child: const Text('重置'),
          ),
        ],
      ),
      body: FutureBuilder<Size>(
        future: _imageSizeFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _CropError(
              onRetry: () {
                setState(() {
                  _imageSizeFuture = widget.cropService.readImageSize(
                    widget.imagePath,
                  );
                });
              },
            );
          }

          return Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    final imageRect = ImageCropGeometry.containedImageRect(
                      viewportSize: viewportSize,
                      imageSize: snapshot.data!,
                    );
                    final selectionRect = ImageCropGeometry.toViewportRect(
                      normalizedRect: _selection,
                      containedImageRect: imageRect,
                    );

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: Image.file(
                            File(widget.imagePath),
                            fit: BoxFit.contain,
                          ),
                        ),
                        CustomPaint(
                          painter: _CropOverlayPainter(
                            imageRect: imageRect,
                            selectionRect: selectionRect,
                          ),
                        ),
                        Positioned.fromRect(
                          rect: selectionRect,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onPanUpdate: (details) =>
                                _moveSelection(details, imageRect),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: AppColors.primary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                        ..._buildHandles(selectionRect, imageRect),
                      ],
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '拖动边角调整范围，排除顶部工具栏、底部按钮、时间、电量等无关区域。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _isCropping ? null : _confirmCrop,
                        icon: _isCropping
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.crop_rounded),
                        label: const Text('使用框选范围并重新 OCR'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildHandles(Rect selectionRect, Rect imageRect) {
    return <Widget>[
      _buildHandle(selectionRect.topLeft, imageRect, _CropHandle.topLeft),
      _buildHandle(selectionRect.topRight, imageRect, _CropHandle.topRight),
      _buildHandle(selectionRect.bottomLeft, imageRect, _CropHandle.bottomLeft),
      _buildHandle(
        selectionRect.bottomRight,
        imageRect,
        _CropHandle.bottomRight,
      ),
    ];
  }

  Widget _buildHandle(Offset center, Rect imageRect, _CropHandle handle) {
    const size = 34.0;
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => _resizeSelection(details, imageRect, handle),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  const _CropOverlayPainter({
    required this.imageRect,
    required this.selectionRect,
  });

  final Rect imageRect;
  final Rect selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRect(selectionRect);
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    canvas.drawPath(
      Path.combine(PathOperation.difference, overlay, hole),
      paint,
    );

    final guidePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var i = 1; i < 3; i++) {
      final x = selectionRect.left + selectionRect.width * i / 3;
      canvas.drawLine(
        Offset(x, selectionRect.top),
        Offset(x, selectionRect.bottom),
        guidePaint,
      );
      final y = selectionRect.top + selectionRect.height * i / 3;
      canvas.drawLine(
        Offset(selectionRect.left, y),
        Offset(selectionRect.right, y),
        guidePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return imageRect != oldDelegate.imageRect ||
        selectionRect != oldDelegate.selectionRect;
  }
}

class _CropError extends StatelessWidget {
  const _CropError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              '图片读取失败，无法框选。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight }
