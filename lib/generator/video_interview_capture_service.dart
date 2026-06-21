import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

// ========== 视频面试采集 ==========
// 管理页面内摄像头预览、开始录制和结束录制。

class CapturedVideoAnswer {
  const CapturedVideoAnswer({required this.path, required this.name});

  final String path;
  final String name;
}

abstract class VideoInterviewCameraSession {
  bool get isInitialized;

  bool get isRecording;

  Widget buildPreview();

  Future<void> initialize();

  Future<void> startRecording();

  Future<CapturedVideoAnswer?> stopRecording();

  Future<void> dispose();
}

class VideoInterviewCaptureService {
  Future<VideoInterviewCameraSession> createSession() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('没有检测到可用摄像头');
    }

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    return _CameraPluginInterviewSession(frontCamera);
  }
}

class _CameraPluginInterviewSession implements VideoInterviewCameraSession {
  _CameraPluginInterviewSession(this._camera);

  final CameraDescription _camera;
  CameraController? _controller;

  @override
  bool get isInitialized => _controller?.value.isInitialized ?? false;

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return CameraPreview(controller);
  }

  @override
  Future<void> initialize() async {
    final controller = CameraController(
      _camera,
      ResolutionPreset.medium,
      enableAudio: true,
    );
    _controller = controller;
    await controller.initialize();
  }

  @override
  Future<void> startRecording() async {
    final controller = _requireController();
    if (controller.value.isRecordingVideo) {
      return;
    }
    await controller.startVideoRecording();
  }

  @override
  Future<CapturedVideoAnswer?> stopRecording() async {
    final controller = _requireController();
    if (!controller.value.isRecordingVideo) {
      return null;
    }
    final file = await controller.stopVideoRecording();
    return CapturedVideoAnswer(path: file.path, name: path.basename(file.path));
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
  }

  CameraController _requireController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('摄像头还没有准备好');
    }
    return controller;
  }
}
