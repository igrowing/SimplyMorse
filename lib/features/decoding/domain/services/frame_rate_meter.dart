/// Measures the achieved frame rate of a video stream from frame
/// arrival timestamps.
///
/// The camera's requested frame rate (`CameraController.fps`) is
/// what we ask the platform for; this class measures what actually
/// arrives. The two differ — a device may accept a 60 fps request
/// but only deliver 30, or start strong and throttle under thermal
/// load. The measured value is what limits video decoding accuracy,
/// so it is the one shown to the user and written to the debug log.
class FrameRateMeter {
  /// Number of most-recent timestamps the rate is computed over.
  ///
  /// At 30 fps, 30 timestamps span ~1 s — long enough to smooth
  /// per-frame jitter, short enough to notice a mid-session throttle
  /// within a second.
  FrameRateMeter({this.window = 30});

  final int window;

  final List<int> _timestamps = [];

  double _fps = 0;

  /// Measured frames per second over the last [window] frames.
  ///
  /// Returns 0 until at least two frames have been recorded.
  double get fps => _fps;

  /// Records the arrival of a frame at [timestampMs].
  ///
  /// Out-of-order timestamps (clock hiccups) are ignored so a single
  /// negative delta can't drag the average down.
  void add(int timestampMs) {
    if (_timestamps.isNotEmpty && timestampMs <= _timestamps.last) {
      return;
    }
    _timestamps.add(timestampMs);
    if (_timestamps.length > window) {
      _timestamps.removeAt(0);
    }
    if (_timestamps.length >= 2) {
      final span = _timestamps.last - _timestamps.first;
      if (span > 0) {
        _fps = 1000.0 * (_timestamps.length - 1) / span;
      }
    }
  }

  /// Clears the measurement.
  void reset() {
    _timestamps.clear();
    _fps = 0;
  }
}
