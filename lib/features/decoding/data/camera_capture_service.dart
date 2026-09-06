import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/frame_rate_meter.dart';

/// Platform implementation of [CameraCapture] using the
/// `camera` package.
///
/// Captures low-resolution frames, extracts luminance from
/// the YUV420 Y plane, downsamples to ~80×60, and exposes
/// the [CameraController] for preview rendering.
///
/// Frame-rate strategy: video decoding accuracy is limited by
/// frame rate (a 20 WPM dit is 1.8 frames at 30 fps), so
/// [initialize] first asks for the highest capture rate at the
/// lowest resolution, and falls back step by step to the
/// platform default when a rate is not supported. The actually
/// delivered rate is measured while streaming and exposed via
/// [measuredFps] — a request that the platform silently
/// downgrades is detectable there, not in the requested value.
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
  final FrameRateMeter _frameRateMeter = FrameRateMeter();

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
  double get measuredFps => _frameRateMeter.fps;

  @override
  DebugCaptureEventCallback? onDebugEvent;

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
    if (cameras.isEmpty) {
      _emitDebug('init_failed', detail: 'no camera available');
      return;
    }

    // Try progressively lower capture rates.
    //
    // Frame rate, not thresholding, is what limits the video decoder
    // at speed: at 30 fps a 20 WPM dit is 1.8 frames, which leaves the
    // dah and character-gap duration clusters overlapping so no
    // classifier can separate them. Doubling the rate halves that
    // quantisation. Not every device offers every rate, and asking for
    // an unsupported one fails at initialize(), so fall back in order.
    for (final fps in _preferredFrameRates) {
      final request = fps == null ? 'platform default' : '$fps fps';
      _emitDebug(
        'init_attempt',
        detail: 'requesting low resolution @ $request',
      );
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
        _emitDebug(
          'init_ok',
          detail: 'low resolution @ $_frameRate fps granted',
        );
        break;
      } on CameraException catch (e) {
        await controller.dispose();
        _emitDebug(
          'init_fallback',
          detail: '$request failed (code: ${e.code}, ${e.description})',
        );
      }
    }

    if (_controller == null) {
      _emitDebug('init_failed', detail: 'no supported capture rate');
      return;
    }

    // Lock exposure for consistent brightness detection.
    try {
      await _controller!.setExposureMode(ExposureMode.locked);
      _emitDebug('exposure_locked');
    } on CameraException {
      // Not all devices support locked exposure —
      // continue with auto exposure.
      _emitDebug('exposure_auto', detail: 'locked mode unsupported');
    }

    _isHighFrameRate = _frameRate > _defaultFrameRate;
  }

  /// Capture rates to try, best first. `null` asks for the platform
  /// default rather than a specific rate.
  static const List<int?> _preferredFrameRates = [120, 60, null];

  static const int _defaultFrameRate = 30;

  @override
  void startImageStream(void Function(VideoFrame frame) onFrame) {
    if (kIsWeb) return;
    if (_controller == null || !isInitialized) return;
    _isActive = true;
    _frameRateMeter.reset();
    _framesSinceRateReport = 0;

    unawaited(
      _controller!.startImageStream((image) {
        if (!_isActive) return;
        final frame = _processImage(image);
        _frameRateMeter.add(frame.timestampMs);
        // The delivered frame rate is what decides whether a given
        // sending speed is decodable at all — at 30 fps a 16 WPM dit
        // spans barely two frames — and the platform may grant less
        // than was requested without saying so. Record it periodically
        // so a log can be read against what the camera actually did.
        if (++_framesSinceRateReport >= _framesPerRateReport) {
          _framesSinceRateReport = 0;
          _emitDebug(
            'frame_rate',
            detail: 'measured_fps=${_frameRateMeter.fps.toStringAsFixed(1)}',
          );
        }
        onFrame(frame);
      }),
    );
  }

  int _framesSinceRateReport = 0;

  /// Frames between measured-rate reports — about three seconds at
  /// 30 fps, often enough to see a rate change, rare enough not to
  /// bloat the log.
  static const int _framesPerRateReport = 90;

  @override
  Future<void> stop() async {
    _isActive = false;
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  void _emitDebug(String event, {String? detail}) {
    onDebugEvent?.call(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      event: event,
      detail: detail,
    );
  }

  /// Extracts luminance from the YUV420 Y plane and downsamples to
  /// ~80×60, taking the BRIGHTEST source pixel in each output
  /// cell's block rather than a single strided sample.
  ///
  /// A single-sample point-pick (reading e.g. pixel (4y, 4x) out of
  /// each 4×4 block and discarding the other 15) is O(target) —
  /// independent of sensor resolution, which is why it was used
  /// here: the decoder targets up to 120 fps, and a full block scan
  /// is ~16x more per-frame Dart arithmetic. But it aliases: the
  /// transmitting light's on-screen footprint is often a handful of
  /// pixels, and whether the strided grid happens to land on it is
  /// pure luck — a source can flicker in and out of the downsampled
  /// buffer as it drifts by sub-sample amounts (hand shake), which
  /// looks to the decoder like the signal itself is unstable.
  ///
  /// Taking the block's max instead costs the same O(source) scan a
  /// mean/box-filter would, but never dilutes or misses a bright
  /// spot the way a point-sample (misses unless the stride lands on
  /// it) or a mean (dilutes it toward the surrounding background,
  /// proportionally to how small the spot is) can — whichever pixel
  /// in the block is brightest survives into the output cell.
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
      final startY = y * scaleY;
      final endY = min(startY + scaleY, srcHeight);
      for (var x = 0; x < targetWidth; x++) {
        final startX = x * scaleX;
        final endX = min(startX + scaleX, srcWidth);

        var maxByte = 0;
        for (var srcY = startY; srcY < endY; srcY++) {
          final rowBase = srcY * bytesPerRow;
          for (var srcX = startX; srcX < endX; srcX++) {
            final idx = rowBase + srcX;
            if (idx >= bytes.length) continue;
            final v = bytes[idx];
            if (v > maxByte) maxByte = v;
          }
        }
        luminance.add(maxByte / 255);
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
