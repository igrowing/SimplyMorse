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
    this.biasHistorySize = 10,
    this.minSamplesForBias = 4,
    this.biasMaxFrameFraction = 0.5,
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

  /// How many recent completed on/off segments feed the mark/space
  /// bias estimate. See [biasMaxFrameFraction].
  final int biasHistorySize;

  /// Minimum on-segments *and* off-segments in history before a bias
  /// correction is attempted — a couple of samples on either side is
  /// too easily skewed by one landing near a threshold boundary.
  final int minSamplesForBias;

  /// Cap on the bias correction, as a fraction of the observed frame
  /// period. See [_currentBiasMs] for why a cap is needed at all.
  final double biasMaxFrameFraction;

  double _min = 1;
  double _max = 0;
  bool _isOn = false;
  bool _initialized = false;
  int _lastTransitionMs = 0;

  double _prevBrightness = 0;
  int _prevTimestampMs = 0;
  double _lastEdgeMs = 0;

  // -- Mark/space bias correction --
  //
  // Camera frame integration and LED/sensor persistence delay the
  // *falling* edge (on -> off) more than the rising edge: a frame
  // whose exposure window mostly overlapped a lit mark still reads
  // "on" even after the source has switched off. The rising edge has
  // no equivalent delay. Net effect, confirmed on the reference
  // recordings: marks measure systematically longer than the 1-unit
  // gaps that follow them — by up to several frames at 20 WPM, where
  // a mark is only ~1.8 frames to begin with, this dilation collapses
  // dits into dahs before any decoder-side logic runs.
  //
  // The fix estimates the bias online — half the gap between the
  // median mark and the median *short* gap (a proxy for "should be
  // the same duration") — and shifts only the falling edge earlier by
  // that amount. No fixed millisecond constant: frame rate, sending
  // speed and camera behaviour all vary, so the correction is derived
  // from what this stream is actually doing.
  double _segStartMs = 0;
  double _avgFrameMs = 33;
  bool _avgFrameMsSeeded = false;
  final List<double> _onHistoryMs = [];
  final List<double> _offHistoryMs = [];
  double _effectiveTransitionMs = 0;

  /// The time callers should report this frame's transition at,
  /// instead of the raw frame timestamp.
  ///
  /// Equal to the frame timestamp on every call except the one where
  /// a falling (on -> off) edge is detected, where it is shifted
  /// earlier by the current bias correction — see the class docs
  /// above [_segStartMs]. Safe to read unconditionally after every
  /// [process] call.
  double get effectiveTransitionMs => _effectiveTransitionMs;

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
      _segStartMs = t.toDouble();
      _effectiveTransitionMs = t.toDouble();
      return _isOn;
    }

    // Track the observed frame period so the bias cap (below) scales
    // to the actual capture rate rather than assuming one.
    final dt = t - _prevTimestampMs;
    if (dt > 0) {
      if (!_avgFrameMsSeeded) {
        _avgFrameMs = dt.toDouble();
        _avgFrameMsSeeded = true;
      } else {
        _avgFrameMs += (dt - _avgFrameMs) * 0.2;
      }
    }

    // Defaults to the raw timestamp; overridden below only on a
    // falling edge, once bias correction is warranted.
    _effectiveTransitionMs = t.toDouble();

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

      if (_isOn) {
        // Falling edge: on -> off. Shift it earlier by the current
        // bias and record the (corrected) mark duration.
        _effectiveTransitionMs = t - _currentBiasMs();
        final durationMs = _effectiveTransitionMs - _segStartMs;
        if (durationMs > 0) _pushHistory(_onHistoryMs, durationMs);
      } else {
        // Rising edge: off -> on. No correction — only persistence
        // and integration on the falling side are asymmetric.
        final durationMs = _effectiveTransitionMs - _segStartMs;
        if (durationMs > 0) _pushHistory(_offHistoryMs, durationMs);
      }

      _isOn = !_isOn;
      _lastTransitionMs = t;
      _segStartMs = _effectiveTransitionMs;
    }

    _prevBrightness = brightness;
    _prevTimestampMs = t;
    return _isOn;
  }

  void _pushHistory(List<double> history, double durationMs) {
    history.add(durationMs);
    if (history.length > biasHistorySize) history.removeAt(0);
  }

  /// Current falling-edge bias correction, in ms.
  ///
  /// Half the gap between the median mark and the median *short* off
  /// segment (off segments longer than 2.5x the median mark are
  /// character/word gaps, not comparable 1-unit gaps, and are
  /// excluded). Marks and 1-unit gaps should be equal in valid Morse,
  /// so this gap is exactly the dilation to correct for — see the
  /// class docs above [_segStartMs].
  ///
  /// Capped at [biasMaxFrameFraction] of the observed frame period:
  /// the underlying cause is at most a frame or so of integration and
  /// persistence, so a larger estimate is noise, not signal, and
  /// applying it uncorrected has caused more harm than good in
  /// testing.
  double _currentBiasMs() {
    if (_onHistoryMs.length < minSamplesForBias ||
        _offHistoryMs.length < minSamplesForBias) {
      return 0;
    }
    final sortedOn = List<double>.from(_onHistoryMs)..sort();
    final medianOn = sortedOn[sortedOn.length ~/ 2];

    final shortOffs = _offHistoryMs.where((d) => d < medianOn * 2.5).toList();
    if (shortOffs.length < minSamplesForBias) return 0;
    shortOffs.sort();
    final medianOff = shortOffs[shortOffs.length ~/ 2];

    final bias = (medianOn - medianOff) / 2.0;
    final cap = _avgFrameMs * biasMaxFrameFraction;
    return bias.clamp(0.0, cap);
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
    _segStartMs = 0;
    _avgFrameMs = 33;
    _avgFrameMsSeeded = false;
    _onHistoryMs.clear();
    _offHistoryMs.clear();
    _effectiveTransitionMs = 0;
  }
}
