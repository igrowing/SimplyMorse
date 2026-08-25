import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';

/// Abstract interface for camera capture.
///
/// Implementations live in the data layer (using the
/// `camera` package on mobile). The domain layer depends
/// only on this interface.
abstract interface class CameraCapture {
  /// Checks whether the camera permission has been granted.
  Future<bool> hasPermission();

  /// Initialises the camera (must be called before
  /// [startImageStream]).
  Future<void> initialize();

  /// Starts streaming frames. [onFrame] is called for each
  /// captured frame.
  void startImageStream(void Function(VideoFrame frame) onFrame);

  /// Stops streaming frames.
  Future<void> stop();

  /// Whether the stream is currently active.
  bool get isActive;

  /// Whether the camera has been initialised.
  bool get isInitialized;

  /// Whether the camera supports high-frame-rate capture.
  /// When `false`, decoding is limited to ~7 WPM.
  bool get isHighFrameRate;
}
