import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';

/// Platform implementation of [CameraCapture] using the
/// `camera` package.
///
/// Captures low-resolution frames, extracts luminance from
/// the YUV420 Y plane, downsamples to ~80×60, and exposes
/// the [CameraController] for preview rendering.
///
/// On web, camera frame streaming (`startImageStream`) is
/// not supported — methods return early and [isInitialized]
/// stays `false`.
class CameraCaptureImpl implements CameraCapture {
  CameraCaptureImpl();

  CameraController? _controller;
  bool _isActive = false;
  bool _isHighFrameRate = false;
  int _frameRate = _defaultFrameRate;

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

  /// Capture rate actually in use, in frames per second.
  int get frameRate => _frameRate;

  @override
  Future<bool> hasPermission() async {
    if (kIsWeb) return false;
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
    if (kIsWeb) return;

    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    // Try progressively lower capture rates.
    //
    // Frame rate, not thresholding, is what limits the video decoder
    // at speed: at 30 fps a 20 WPM dit is 1.8 frames, which leaves the
    // dah and character-gap duration clusters overlapping so no
    // classifier can separate them. Doubling the rate halves that
    // quantisation. Not every device offers every rate, and asking for
    // an unsupported one fails at initialize(), so fall back in order.
    for (final fps in _preferredFrameRates) {
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
        fps: fps,
      );
      try {
        await controller.initialize();
        _controller = controller;
        _frameRate = fps ?? _defaultFrameRate;
        break;
      } on CameraException {
        await controller.dispose();
      }
    }

    if (_controller == null) return;

    // Lock exposure for consistent brightness detection.
    try {
      await _controller!.setExposureMode(
        ExposureMode.locked,
      );
    } on CameraException {
      // Not all devices support locked exposure —
      // continue with auto exposure.
    }

    _isHighFrameRate = _frameRate > _defaultFrameRate;
  }

  /// Capture rates to try, best first. `null` asks for the platform
  /// default rather than a specific rate.
  static const List<int?> _preferredFrameRates = [120, 60, null];

  static const int _defaultFrameRate = 30;

  @override
  void startImageStream(
    void Function(VideoFrame frame) onFrame,
  ) {
    if (kIsWeb) return;
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
