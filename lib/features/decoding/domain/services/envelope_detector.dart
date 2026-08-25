import 'dart:math';

/// Fast-attack / slow-release envelope follower.
///
/// Used to smooth the Goertzel power values into a continuous
/// envelope, which is then thresholded to produce the on/off
/// (dit/dah) stream.
class EnvelopeDetector {
  EnvelopeDetector({
    this.attackMs = 2,
    this.releaseMs = 50,
  }) : assert(attackMs > 0, 'attackMs must be positive'),
       assert(releaseMs > 0, 'releaseMs must be positive');

  /// Attack time constant in ms. Smaller = faster rise.
  final double attackMs;

  /// Release time constant in ms. Larger = slower decay.
  final double releaseMs;

  double _value = 0;

  /// Current envelope level.
  double get value => _value;

  /// Processes a power value that arrives every [hopMs]
  /// milliseconds.
  double process(double input, {required double hopMs}) {
    final attackCoeff = exp(-hopMs / attackMs);
    final releaseCoeff = exp(-hopMs / releaseMs);

    if (input > _value) {
      _value = input * (1 - attackCoeff) + _value * attackCoeff;
    } else {
      _value = input * (1 - releaseCoeff) + _value * releaseCoeff;
    }
    return _value;
  }

  /// Resets the envelope to zero.
  void reset() {
    _value = 0;
  }
}
