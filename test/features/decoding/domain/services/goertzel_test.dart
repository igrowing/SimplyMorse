import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/goertzel.dart';

void main() {
  group('Goertzel', () {
    List<double> generateSineWave(
      double freq,
      int sampleRate,
      int n,
    ) {
      return List.generate(n, (i) {
        return sin(2 * pi * freq * i / sampleRate);
      });
    }

    test('high power at target frequency', () {
      const sampleRate = 8000;
      const targetFreq = 700.0;
      const blockSize = 256;

      final goertzel = Goertzel(
        sampleRate: sampleRate,
        targetFreq: targetFreq,
        blockSize: blockSize,
      );

      final samples = generateSineWave(
        targetFreq,
        sampleRate,
        blockSize,
      );
      final power = goertzel.process(samples);

      expect(power, greaterThan(0));
      // Power should be significant
      expect(power, greaterThan(100));
    });

    test('low power at wrong frequency', () {
      const sampleRate = 8000;
      const targetFreq = 700.0;
      const blockSize = 256;

      final goertzel = Goertzel(
        sampleRate: sampleRate,
        targetFreq: targetFreq,
        blockSize: blockSize,
      );

      // Generate tone at 500 Hz, not 700 Hz
      final samples = generateSineWave(
        500,
        sampleRate,
        blockSize,
      );
      final power = goertzel.process(samples);

      // Should be much lower than at the target frequency
      final targetSamples = generateSineWave(
        targetFreq,
        sampleRate,
        blockSize,
      );
      final targetPower = goertzel.process(targetSamples);

      expect(power, lessThan(targetPower * 0.1));
    });

    test('processStream returns multiple results', () {
      const sampleRate = 8000;
      const targetFreq = 700.0;
      const blockSize = 80;
      const hopSize = 40;

      final goertzel = Goertzel(
        sampleRate: sampleRate,
        targetFreq: targetFreq,
        blockSize: blockSize,
      );

      final samples = generateSineWave(
        targetFreq,
        sampleRate,
        400,
      );
      final results = goertzel.processStream(
        samples,
        hopSize: hopSize,
      );

      // (400 - 80) / 40 + 1 = 9 windows
      expect(results, hasLength(9));
      for (final p in results) {
        expect(p, greaterThan(0));
      }
    });

    test('silence produces near-zero power', () {
      const sampleRate = 8000;
      const targetFreq = 700.0;
      const blockSize = 256;

      final goertzel = Goertzel(
        sampleRate: sampleRate,
        targetFreq: targetFreq,
        blockSize: blockSize,
      );

      final samples = List<double>.filled(blockSize, 0);
      final power = goertzel.process(samples);

      expect(power.abs(), lessThan(1e-6));
    });

    test('power scales with amplitude', () {
      const sampleRate = 8000;
      const targetFreq = 700.0;
      const blockSize = 256;

      final goertzel = Goertzel(
        sampleRate: sampleRate,
        targetFreq: targetFreq,
        blockSize: blockSize,
      );

      final samples1 = generateSineWave(
        targetFreq,
        sampleRate,
        blockSize,
      );
      final samples2 = samples1.map((s) => s * 2).toList();

      final power1 = goertzel.process(samples1);
      final power2 = goertzel.process(samples2);

      // Doubling amplitude quadruples power
      expect(power2, closeTo(power1 * 4, power1 * 0.01));
    });
  });
}
