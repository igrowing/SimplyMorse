/// Adaptive hysteresis threshold for brightness on/off
/// detection.
///
/// Tracks a rolling minimum and maximum of the brightness
/// signal (with exponential forgetting) and classifies
/// each sample as "on" or "off" using two thresholds
/// derived from the current range.
class BrightnessThreshold {
  BrightnessThreshold({
    this.onFactor = 0.4,
    this.offFactor = 0.4,
    this.decayFactor = 0.995,
    this.minRange = 0.01,
    this.minTransitionMs = 50,
  }) : assert(
         onFactor >= offFactor,
         'onFactor must be greater than or equal to offFactor',
       ),
       assert(
         decayFactor > 0 && decayFactor <= 1,
         'decayFactor must be in (0, 1]',
       );

  /// Fraction of the range above which the signal is "on".
  final double onFactor;

  /// Fraction of the range below which the signal is "off".
  final double offFactor;

  /// Controls how quickly min/max forget past extremes.
  /// 1.0 = never forget (absolute min/max), lower values
  /// adapt faster. Must be in (0, 1].
  final double decayFactor;

  /// Minimum range to produce a valid on/off decision.
  final double minRange;

  /// Minimum duration (ms) between transitions, to filter noise at
  /// the camera frame rate. At 30 fps each frame is ~33 ms;
  /// requiring at least 50 ms eliminates single-frame glitches.
  ///
  /// This is deliberately *not* delegated to the shared
  /// `ElementBuilder`'s rate-relative threshold. Measured over the
  /// reference recordings, suppressing the transition outright beats
  /// merging it afterwards for video, because at 30 fps a single bad
  /// frame is already a third of a 20 WPM dit.
  final int minTransitionMs;

  double _min = 1;
  double _max = 0;
  bool _isOn = false;
  bool _initialized = false;
  int _lastTransitionMs = 0;

  double _prevBrightness = 0;
  int _prevTimestampMs = 0;
  double _lastEdgeMs = 0;

  /// Timestamp of the most recent transition, interpolated between
  /// the two frames that straddled the threshold.
  ///
  /// A 30 fps camera samples every 33 ms while a dit is only 60 ms at
  /// 20 WPM, so quantising edges to frame boundaries blurs the mark
  /// and gap durations. Linear interpolation of the brightness ramp
  /// recovers sub-frame precision.
  ///
  /// Measured over the 30 fps reference recordings this makes no
  /// difference — the light saturates within a single frame, so there
  /// is usually no intermediate sample to interpolate from. It is kept
  /// for higher capture rates, where transitions do straddle frames.
  /// Callers that want it must use it explicitly; the decoders time
  /// elements from frame timestamps.
  double get lastEdgeMs => _lastEdgeMs;

  /// Whether the signal is currently "on".
  bool get isOn => _isOn;

  /// Current tracked minimum brightness.
  double get minBrightness => _min;

  /// Current tracked maximum brightness.
  double get maxBrightness => _max;

  /// Current range (max - min).
  double get range => _max - _min;

  /// Processes a brightness sample and returns the on/off
  /// state.
  bool process(double brightness, {int? timestampMs}) {
    final t = timestampMs ?? _prevTimestampMs;

    if (!_initialized) {
      _min = brightness;
      _max = brightness;
      _initialized = true;
      _prevBrightness = brightness;
      _prevTimestampMs = t;
      _lastEdgeMs = t.toDouble();
      return _isOn;
    }

    final forgetRate = 1 - decayFactor;

    // Track min/max with exponential forgetting:
    // extremes snap immediately, otherwise drift toward
    // the current value so stale bounds don't persist.
    if (brightness < _min) {
      _min = brightness;
    } else {
      _min += (brightness - _min) * forgetRate;
    }

    if (brightness > _max) {
      _max = brightness;
    } else {
      _max += (brightness - _max) * forgetRate;
    }

    final r = _max - _min;
    if (r < minRange) {
      _prevBrightness = brightness;
      _prevTimestampMs = t;
      return _isOn;
    }

    final onThreshold = _min + r * onFactor;
    final offThreshold = _min + r * offFactor;

    final crossed = !_isOn
        ? brightness >= onThreshold
        : brightness <= offThreshold;

    if (crossed &&
        (timestampMs == null || t - _lastTransitionMs >= minTransitionMs)) {
      _lastEdgeMs = _interpolateEdge(
        _isOn ? offThreshold : onThreshold,
        brightness,
        t,
      );
      _isOn = !_isOn;
      _lastTransitionMs = t;
    }

    _prevBrightness = brightness;
    _prevTimestampMs = t;
    return _isOn;
  }

  /// Places the edge between the previous and current frame at the
  /// point where the brightness ramp crosses [threshold].
  double _interpolateEdge(double threshold, double brightness, int t) {
    final span = brightness - _prevBrightness;
    final dt = (t - _prevTimestampMs).toDouble();
    if (span.abs() < 1e-9 || dt <= 0) return t.toDouble();
    final f = ((threshold - _prevBrightness) / span).clamp(0.0, 1.0);
    return _prevTimestampMs + f * dt;
  }

  /// Resets the threshold state.
  void reset() {
    _min = 1;
    _max = 0;
    _isOn = false;
    _initialized = false;
    _lastTransitionMs = 0;
    _prevBrightness = 0;
    _prevTimestampMs = 0;
    _lastEdgeMs = 0;
  }
}
