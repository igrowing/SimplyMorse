import 'dart:math';

import 'package:camera/camera.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';

/// Platform implementation of [CameraCapture] using the
/// `camera` package.
///
/// Captures low-resolution frames, extracts luminance from
/// the YUV420 Y plane, downsamples to ~80×60, and exposes
/// the [CameraController] for preview rendering.
class CameraCaptureImpl implements CameraCapture {
  CameraCaptureImpl();

  CameraController? _controller;
  bool _isActive = false;
  bool _isHighFrameRate = false;

  /// The underlying [CameraController], exposed so the
  /// presentation layer can render the live preview via
  /// [CameraPreview].
  CameraController? get controller => _controller;

  @override
  bool get isActive => _isActive;

  @override
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  @override
  bool get isHighFrameRate => _isHighFrameRate;

  @override
  Future<bool> hasPermission() async {
    try {
      if (!isInitialized) {
        await initialize();
      }
      return isInitialized;
    } on CameraException {
      return false;
    }
  }

  @override
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _controller!.initialize();

    // Lock exposure for consistent brightness detection.
    try {
      await _controller!.setExposureMode(
        ExposureMode.locked,
      );
    } on CameraException {
      // Not all devices support locked exposure —
      // continue with auto exposure.
    }

    // The camera package does not expose high-frame-rate
    // modes for image streams, so we use standard ~30fps.
    _isHighFrameRate = false;
  }

  @override
  void startImageStream(
    void Function(VideoFrame frame) onFrame,
  ) {
    if (_controller == null || !isInitialized) return;
    _isActive = true;

    _controller!.startImageStream((CameraImage image) {
      if (!_isActive) return;
      onFrame(_processImage(image));
    });
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  /// Extracts luminance from the YUV420 Y plane and
  /// downsamples to ~80×60.
  VideoFrame _processImage(CameraImage image) {
    const targetWidth = 80;
    const targetHeight = 60;

    final yPlane = image.planes.first;
    final bytes = yPlane.bytes;
    final srcWidth = image.width;
    final srcHeight = image.height;
    final bytesPerRow = yPlane.bytesPerRow;

    final scaleX = max(srcWidth ~/ targetWidth, 1);
    final scaleY = max(srcHeight ~/ targetHeight, 1);

    final luminance = <double>[];
    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final srcY = min(y * scaleY, srcHeight - 1);
        final srcX = min(x * scaleX, srcWidth - 1);
        final idx = srcY * bytesPerRow + srcX;
        if (idx < bytes.length) {
          luminance.add(bytes[idx] / 255);
        } else {
          luminance.add(0);
        }
      }
    }

    return VideoFrame(
      luminance: luminance,
      width: targetWidth,
      height: targetHeight,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Disposes the camera controller and releases resources.
  Future<void> dispose() async {
    await stop();
    await _controller?.dispose();
    _controller = null;
  }
}
