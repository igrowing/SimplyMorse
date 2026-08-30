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

  /// Minimum duration (ms) between transitions to filter
  /// noise at the camera frame rate. At 30fps each frame is
  /// ~33ms; requiring at least 50ms eliminates single-frame
  /// glitches.
  final int minTransitionMs;

  double _min = 1;
  double _max = 0;
  bool _isOn = false;
  bool _initialized = false;
  int _lastTransitionMs = 0;

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
    if (!_initialized) {
      _min = brightness;
      _max = brightness;
      _initialized = true;
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
    if (r < minRange) return _isOn;

    final onThreshold = _min + r * onFactor;
    final offThreshold = _min + r * offFactor;

    if (!_isOn && brightness >= onThreshold) {
      // Only transition if enough time has passed since last transition
      if (timestampMs == null ||
          timestampMs - _lastTransitionMs >= minTransitionMs) {
        _isOn = true;
        _lastTransitionMs = timestampMs ?? _lastTransitionMs;
      }
    } else if (_isOn && brightness <= offThreshold) {
      if (timestampMs == null ||
          timestampMs - _lastTransitionMs >= minTransitionMs) {
        _isOn = false;
        _lastTransitionMs = timestampMs ?? _lastTransitionMs;
      }
    }

    return _isOn;
  }

  /// Resets the threshold state.
  void reset() {
    _min = 1;
    _max = 0;
    _isOn = false;
    _initialized = false;
    _lastTransitionMs = 0;
  }
}
