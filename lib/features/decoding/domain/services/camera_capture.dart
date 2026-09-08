import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';

/// Debug callback for camera capture lifecycle events.
///
/// Emitted for every capture-setup decision so the debug log shows
/// which frame rate was requested, whether it was granted, and what
/// rate actually arrives once the stream runs.
typedef DebugCaptureEventCallback =
    void Function({
      required int timestampMs,
      required String event,
      String? detail,
    });

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

  /// Measured frames per second of the live stream, over roughly
  /// the last second of frames.
  ///
  /// This is what the device actually delivers — the requested
  /// rate may be silently downgraded by the platform.
  double get measuredFps;

  /// Optional debug hook for capture lifecycle events.
  ///
  /// Set by the composition layer; the capture implementation
  /// reports init attempts, fallbacks, and measured rates here.
  DebugCaptureEventCallback? get onDebugEvent;
  set onDebugEvent(DebugCaptureEventCallback? callback);
}
