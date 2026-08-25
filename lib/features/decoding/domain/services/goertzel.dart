import 'dart:math';

/// Goertzel algorithm for efficient single-frequency detection.
///
/// Much cheaper per-sample than a full FFT — used once a
/// candidate tone frequency has been identified by the wideband
/// scan, to track the tone's on/off envelope at short,
/// frequently-updated windows (10-20 ms).
class Goertzel {
  Goertzel({
    required this.sampleRate,
    required this.targetFreq,
    required this.blockSize,
  }) {
    _initCoefficients();
  }

  final int sampleRate;
  final double targetFreq;
  final int blockSize;

  late final double _coeff;
  late final double _coeff2;

  void _initCoefficients() {
    final k = (blockSize * targetFreq / sampleRate).round();
    final omega = 2 * pi * k / blockSize;
    _coeff = 2 * cos(omega);
    _coeff2 = 2 * cos(2 * pi * targetFreq / sampleRate);
  }

  /// Processes [samples] and returns the power at
  /// [targetFreq].
  ///
  /// [samples] should have length [blockSize].
  double process(List<double> samples) {
    double s1 = 0;
    double s2 = 0;

    for (final sample in samples) {
      final s0 = sample + _coeff * s1 - s2;
      s2 = s1;
      s1 = s0;
    }

    return s1 * s1 + s2 * s2 - _coeff * s1 * s2;
  }

  /// Processes [samples] with a sliding window and returns
  /// power values for each position.
  ///
  /// [hopSize] is the number of samples to advance between
  /// windows.
  List<double> processStream(
    List<double> samples, {
    required int hopSize,
  }) {
    final results = <double>[];
    for (var i = 0; i + blockSize <= samples.length; i += hopSize) {
      final block = samples.sublist(i, i + blockSize);
      results.add(process(block));
    }
    return results;
  }

  /// Updates the target frequency (for tracking frequency
  /// drift) and recomputes coefficients.
  void updateFrequency(double newFreq) {
    // ignore: prefer_constant_constructors
    final newGoertzel = Goertzel(
      sampleRate: sampleRate,
      targetFreq: newFreq,
      blockSize: blockSize,
    );
    _coeff = newGoertzel._coeff;
  }
}
