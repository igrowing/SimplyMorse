import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/biquad_bandpass.dart';

void main() {
  group('BiquadBandpass', () {
    test('passes signal at center frequency', () {
      final filter = BiquadBandpass(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
      );

      // Generate 100ms of 700Hz sine wave
      const duration = 800; // 100ms at 8kHz
      final samples = List<double>.generate(duration, (i) {
        return sin(2 * pi * 700 * i / 8000);
      });

      // Process all samples, measure RMS of last 400 (steady state)
      double sumSq = 0;
      for (var i = 0; i < samples.length; i++) {
        final out = filter.process(samples[i]);
        if (i >= 400) sumSq += out * out;
      }
      final rms = sqrt(sumSq / 400);

      // At center frequency, the filter should pass with near-unity gain
      expect(rms, greaterThan(0.4));
    });

    test('attenuates signal outside the band', () {
      final filter = BiquadBandpass(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
      );

      // 200Hz is well outside the 660-740Hz band
      const duration = 800;
      final samples = List<double>.generate(duration, (i) {
        return sin(2 * pi * 200 * i / 8000);
      });

      double sumSq = 0;
      for (var i = 0; i < samples.length; i++) {
        final out = filter.process(samples[i]);
        if (i >= 400) sumSq += out * out;
      }
      final rms = sqrt(sumSq / 400);

      // 200Hz should be heavily attenuated
      expect(rms, lessThan(0.05));
    });

    test('attenuates signal at band edge partially', () {
      final filter = BiquadBandpass(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
      );

      // 760Hz is just outside the band edge
      const duration = 800;
      final samples = List<double>.generate(duration, (i) {
        return sin(2 * pi * 760 * i / 8000);
      });

      double sumSq = 0;
      for (var i = 0; i < samples.length; i++) {
        final out = filter.process(samples[i]);
        if (i >= 400) sumSq += out * out;
      }
      final rms = sqrt(sumSq / 400);

      // At band edge, signal should be attenuated but not zero
      // -3dB point is at centerFreq ± bandwidth/2 = 700 ± 40 = 660/740
      // 760Hz is 20Hz beyond the -3dB point
      final centerRms = _measureRms(filter, 700, 800, 8000);
      expect(rms, lessThan(centerRms * 0.7));
    });

    test('reset clears filter state', () {
      final filter = BiquadBandpass(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
      );

      // Feed a strong signal to build up state
      for (var i = 0; i < 200; i++) {
        filter.process(sin(2 * pi * 700 * i / 8000));
      }

      // Reset
      filter.reset();

      // Process silence — output should be near zero (no ringing)
      double maxOut = 0;
      for (var i = 0; i < 100; i++) {
        final out = filter.process(0.0);
        if (out.abs() > maxOut) maxOut = out.abs();
      }
      expect(maxOut, lessThan(1e-10));
    });

    test('handles wide frequency range', () {
      for (final freq in [400.0, 600.0, 700.0, 800.0, 1000.0]) {
        final filter = BiquadBandpass(
          sampleRate: 8000,
          centerFreq: freq,
          bandwidth: 80,
        );
        const duration = 800;
        final samples = List<double>.generate(
          duration,
          (i) => sin(2 * pi * freq * i / 8000),
        );

        double sumSq = 0;
        for (var i = 0; i < samples.length; i++) {
          final out = filter.process(samples[i]);
          if (i >= 400) sumSq += out * out;
        }
        final rms = sqrt(sumSq / 400);
        // Each frequency should pass through its own filter
        expect(rms, greaterThan(0.3), reason: 'Failed at $freq Hz');
      }
    });
  });
}

double _measureRms(
  BiquadBandpass filter,
  double freq,
  int duration,
  int sampleRate,
) {
  final samples = List<double>.generate(
    duration,
    (i) => sin(2 * pi * freq * i / sampleRate),
  );
  double sumSq = 0;
  for (var i = 0; i < samples.length; i++) {
    final out = filter.process(samples[i]);
    if (i >= 400) sumSq += out * out;
  }
  return sqrt(sumSq / (duration - 400));
}
