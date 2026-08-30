import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/iir_envelope_detector.dart';

void main() {
  group('IirEnvelopeDetector', () {
    test('envelope rises when tone is present', () {
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
        envelopeCutoffHz: 40,
      );

      // Generate 200ms of 700Hz tone at amplitude 1.0
      const duration = 1600; // 200ms at 8kHz
      final samples = List<double>.generate(
        duration,
        (i) => sin(2 * pi * 700 * i / 8000),
      );

      // Feed in two blocks, check envelope rises
      detector.processBlock(samples.sublist(0, 80));
      final env1 = detector.envelope;
      detector.processBlock(samples.sublist(80, 1600));
      final env2 = detector.envelope;

      expect(env2, greaterThan(env1));
      expect(env2, greaterThan(0.1));
    });

    test('envelope decays toward zero when tone stops', () {
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
        envelopeCutoffHz: 40,
      );

      // 200ms of tone
      final tone = List<double>.generate(
        1600,
        (i) => sin(2 * pi * 700 * i / 8000),
      );
      detector.processBlock(tone);
      final envOn = detector.envelope;
      expect(envOn, greaterThan(0.1));

      // 200ms of silence
      final silence = List<double>.filled(1600, 0.0);
      detector.processBlock(silence);
      final envOff = detector.envelope;

      // Envelope should drop significantly
      expect(envOff, lessThan(envOn * 0.1));
    });

    test('envelope is continuous across block boundaries', () {
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
        envelopeCutoffHz: 40,
      );

      // Generate a continuous tone
      const total = 3200;
      final samples = List<double>.generate(
        total,
        (i) => sin(2 * pi * 700 * i / 8000),
      );

      // Process in small blocks
      const blockSize = 80;
      final envelopes = <double>[];
      for (var i = 0; i < total; i += blockSize) {
        final end = (i + blockSize < total) ? i + blockSize : total;
        detector.processBlock(samples.sublist(i, end));
        envelopes.add(detector.envelope);
      }

      // After settling, envelope should be smooth (no sudden jumps)
      for (var i = 10; i < envelopes.length - 1; i++) {
        final delta = (envelopes[i + 1] - envelopes[i]).abs();
        // No sudden jumps (> 50% of current value) in steady state
        expect(
          delta,
          lessThan(envelopes[i] * 0.5 + 0.001),
          reason: 'Jump at frame $i: $delta vs ${envelopes[i]}',
        );
      }
    });

    test('envelope tracks amplitude modulation', () {
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
        envelopeCutoffHz: 40,
      );

      // 100ms tone at amplitude 1.0
      final tone1 = List<double>.generate(
        800,
        (i) => sin(2 * pi * 700 * i / 8000),
      );
      detector.processBlock(tone1);
      final envHigh = detector.envelope;

      // 50ms gap
      detector.processBlock(List.filled(400, 0.0));

      // 100ms tone at amplitude 0.5
      final tone2 = List<double>.generate(
        800,
        (i) => 0.5 * sin(2 * pi * 700 * i / 8000),
      );
      detector.processBlock(tone2);
      final envLow = detector.envelope;

      // Lower amplitude tone should produce lower envelope
      expect(envLow, lessThan(envHigh));
      expect(envLow, greaterThan(0.01));
    });

    test('reset clears state', () {
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
      );

      final tone = List<double>.generate(
        800,
        (i) => sin(2 * pi * 700 * i / 8000),
      );
      detector.processBlock(tone);
      expect(detector.envelope, greaterThan(0.1));

      detector.reset();
      expect(detector.envelope, equals(0.0));

      // After reset, processing silence should keep envelope near zero
      detector.processBlock(List.filled(80, 0.0));
      expect(detector.envelope, lessThan(0.001));
    });

    test('handles frequency mismatch within bandwidth', () {
      // Detector centered at 700Hz, but tone is at 710Hz (within band)
      final detector = IirEnvelopeDetector(
        sampleRate: 8000,
        centerFreq: 700,
        bandwidth: 80,
        envelopeCutoffHz: 40,
      );

      final tone = List<double>.generate(
        1600,
        (i) => sin(2 * pi * 710 * i / 8000),
      );
      detector.processBlock(tone);

      // Even with 10Hz frequency mismatch, envelope should still detect the tone
      expect(detector.envelope, greaterThan(0.05));
    });
  });
}
