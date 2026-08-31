import 'dart:math';

import 'package:simply_morse/features/decoding/domain/services/biquad_bandpass.dart';

/// Default 3 dB cutoff of the envelope lowpass, in Hz.
///
/// Shared between [IirEnvelopeDetector] and `AudioDecoder` (which always
/// passes its own [IirEnvelopeDetector.envelopeCutoffHz] through
/// explicitly) so the two constructors' defaults can't drift apart —
/// they previously did, silently, because editing one didn't touch
/// the other.
///
/// 30 Hz beats the original 40 Hz on the reference recordings (25.9 %
/// → 11.1 % CER on the 1000 Hz / 8 WPM one, unchanged on the other
/// four) — the wider 40 Hz smoothing let noise cross the on/off
/// threshold during the envelope's decay tail on that recording's
/// weaker signal-to-noise ratio.
const double kDefaultEnvelopeCutoffHz = 30;

/// IIR bandpass + rectify + lowpass envelope detector.
///
/// Replaces the Goertzel + EnvelopeDetector combination with a
/// more robust approach:
///
/// 1. **Bandpass filter** — a 2nd-order IIR biquad isolates the
///    tone band. Unlike Goertzel (which evaluates power at one
///    exact frequency), the bandpass integrates energy across
///    its bandwidth, making it robust to frequency drift and
///    beating.
/// 2. **Rectify** — the absolute value of the filtered signal
///    gives the amplitude.
/// 3. **Lowpass** — a one-pole filter smooths the rectified
///    signal into a continuous envelope.
///
/// The filter is sample-by-sample (stateful), so there are no
/// block-boundary resets that cause Goertzel power oscillation.
/// The envelope is smooth and continuous.
class IirEnvelopeDetector {
  IirEnvelopeDetector({
    required this.sampleRate,
    required this.centerFreq,
    this.bandwidth = 80.0,
    this.envelopeCutoffHz = kDefaultEnvelopeCutoffHz,
  }) {
    _bandpass = BiquadBandpass(
      sampleRate: sampleRate,
      centerFreq: centerFreq,
      bandwidth: bandwidth,
    );
    _lpfAlpha = 1 - exp(-2 * pi * envelopeCutoffHz / sampleRate);
  }

  final int sampleRate;
  final double centerFreq;
  final double bandwidth;
  final double envelopeCutoffHz;

  late final BiquadBandpass _bandpass;
  late final double _lpfAlpha;

  double _envelope = 0;

  /// Current envelope level.
  double get envelope => _envelope;

  /// Processes a block of audio samples and returns the envelope
  /// value at the end of the block.
  ///
  /// Every sample in the block is filtered sample-by-sample
  /// (maintaining filter state), so the envelope is continuous
  /// across block boundaries.
  double processBlock(List<double> samples) {
    for (final s in samples) {
      final filtered = _bandpass.process(s);
      final rectified = filtered.abs();
      _envelope = _lpfAlpha * rectified + (1 - _lpfAlpha) * _envelope;
    }
    return _envelope;
  }

  /// Resets the detector to its initial state.
  void reset() {
    _bandpass.reset();
    _envelope = 0;
  }
}
