import 'dart:math';

/// Second-order IIR bandpass filter (biquad).
///
/// Uses the RBJ Audio EQ Cookbook bandpass (constant 0 dB peak gain)
/// formula. After FFT calibration finds the approximate tone
/// frequency, this filter isolates a narrow band around it.
///
/// Unlike a Goertzel filter, which evaluates power at one exact
/// frequency and is sensitive to frequency mismatch (causing
/// power oscillation / beating), a bandpass filter integrates
/// energy across its entire bandwidth. This makes it robust to
/// tone drift, beating, and sub-bin frequency estimation errors.
///
/// The filter is sample-by-sample (stateful), so there are no
/// block-boundary resets — the envelope is smooth and continuous.
class BiquadBandpass {
  BiquadBandpass({
    required this.sampleRate,
    required this.centerFreq,
    required this.bandwidth,
  }) {
    _init();
  }

  final int sampleRate;
  final double centerFreq;
  final double bandwidth;

  // Normalized coefficients
  late final double _b0;
  late final double _b1;
  late final double _b2;
  late final double _a1;
  late final double _a2;

  // Filter state (Direct Form I)
  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  void _init() {
    final w0 = 2 * pi * centerFreq / sampleRate;
    final q = centerFreq / bandwidth;
    final alpha = sin(w0) / (2 * q);

    final b0 = alpha;
    const b1 = 0.0;
    final b2 = -alpha;
    final a0 = 1 + alpha;
    final a1 = -2 * cos(w0);
    final a2 = 1 - alpha;

    // Normalize by a0
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  /// Processes a single sample and returns the filtered output.
  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  /// Resets the filter state to zero.
  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }
}
