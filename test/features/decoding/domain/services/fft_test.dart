import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';

void main() {
  group('FFT', () {
    var fft = FFT(256);

    List<double> generateSineWave(
      double freq,
      int sampleRate,
      int n,
    ) {
      return List.generate(n, (i) {
        return sin(2 * pi * freq * i / sampleRate);
      });
    }

    test('power spectrum finds peak at correct frequency', () {
      const sampleRate = 8000;
      const freq = 700.0;

      final samples = generateSineWave(freq, sampleRate, 256);
      final power = fft.powerSpectrum(Float64List.fromList(samples));

      // Find peak bin
      var maxBin = 0;
      var maxPower = 0.0;
      for (var i = 0; i < power.length; i++) {
        if (power[i] > maxPower) {
          maxPower = power[i];
          maxBin = i;
        }
      }

      final peakFreq = fft.binFrequency(maxBin, sampleRate);
      // Should be close to 700 Hz (within one bin
      // resolution = 8000/256 = 31.25 Hz)
      expect((peakFreq - freq).abs(), lessThan(32));
    });

    test('power spectrum finds peak for 400 Hz', () {
      const sampleRate = 8000;
      const freq = 400.0;

      final samples = generateSineWave(freq, sampleRate, 256);
      final power = fft.powerSpectrum(Float64List.fromList(samples));

      var maxBin = 0;
      var maxPower = 0.0;
      for (var i = 0; i < power.length; i++) {
        if (power[i] > maxPower) {
          maxPower = power[i];
          maxBin = i;
        }
      }

      final peakFreq = fft.binFrequency(maxBin, sampleRate);
      expect((peakFreq - freq).abs(), lessThan(32));
    });

    test('power spectrum finds peak for 1000 Hz', () {
      const sampleRate = 8000;
      const freq = 1000.0;

      final samples = generateSineWave(freq, sampleRate, 256);
      final power = fft.powerSpectrum(Float64List.fromList(samples));

      var maxBin = 0;
      var maxPower = 0.0;
      for (var i = 0; i < power.length; i++) {
        if (power[i] > maxPower) {
          maxPower = power[i];
          maxBin = i;
        }
      }

      final peakFreq = fft.binFrequency(maxBin, sampleRate);
      expect((peakFreq - freq).abs(), lessThan(32));
    });

    test('silence produces near-zero power spectrum', () {
      final samples = List<double>.filled(256, 0);
      final power = fft.powerSpectrum(Float64List.fromList(samples));

      for (final p in power) {
        expect(p, lessThan(1e-6));
      }
    });

    test('binFrequency and frequencyToBin are inverse', () {
      const sampleRate = 8000;
      for (var bin = 0; bin < 128; bin++) {
        final freq = fft.binFrequency(bin, sampleRate);
        final backBin = fft.frequencyToBin(freq, sampleRate);
        expect((backBin - bin).abs(), lessThanOrEqualTo(1));
      }
    });

    test('handles different sizes', () {
      fft = FFT(512);
      const sampleRate = 8000;
      const freq = 500.0;

      final samples = generateSineWave(freq, sampleRate, 512);
      final power = fft.powerSpectrum(Float64List.fromList(samples));

      var maxBin = 0;
      var maxPower = 0.0;
      for (var i = 0; i < power.length; i++) {
        if (power[i] > maxPower) {
          maxPower = power[i];
          maxBin = i;
        }
      }

      final peakFreq = fft.binFrequency(maxBin, sampleRate);
      expect((peakFreq - freq).abs(), lessThan(16));
    });

    test('asserts on non-power-of-two size', () {
      expect(() => FFT(100), throwsA(isA<AssertionError>()));
      expect(() => FFT(7), throwsA(isA<AssertionError>()));
    });
  });
}
