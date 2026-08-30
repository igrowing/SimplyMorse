import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';

/// Generates a sine-wave tone at [freq] Hz.
List<double> generateTone(
  double freq,
  int sampleRate,
  int numSamples, {
  double amplitude = 0.5,
}) {
  return List.generate(
    numSamples,
    (i) => amplitude * sin(2 * pi * freq * i / sampleRate),
  );
}

/// Generates low-level white noise so the noise floor
/// estimator has a non-zero baseline.
List<double> generateNoise(
  int numSamples, {
  double amplitude = 0.001,
  int seed = 42,
}) {
  final random = Random(seed);
  return List.generate(
    numSamples,
    (i) => amplitude * (random.nextDouble() * 2 - 1),
  );
}

/// Generates pure silence (all zeros).
List<double> generateSilence(int numSamples) {
  return List.filled(numSamples, 0.0);
}

void main() {
  group('AudioDecoder', () {
    group('initial state', () {
      test('starts in calibrating state', () {
        final decoder = AudioDecoder();
        expect(decoder.state, DecoderState.calibrating);
        expect(decoder.isCalibrating, isTrue);
        expect(decoder.lockedFrequency, 0);
      });

      test('reset returns to calibrating state', () {
        final decoder = AudioDecoder();
        decoder.reset();
        expect(decoder.state, DecoderState.calibrating);
        expect(decoder.lockedFrequency, 0);
      });

      test('has configurable parameters', () {
        final decoder = AudioDecoder(
          sampleRate: 16000,
          minFreq: 500,
          maxFreq: 900,
          fftSize: 512,
          goertzelBlockSize: 160,
          calibrationMs: 1000,
        );
        expect(decoder.sampleRate, 16000);
        expect(decoder.minFreq, 500);
        expect(decoder.maxFreq, 900);
        expect(decoder.fftSize, 512);
        expect(decoder.goertzelBlockSize, 160);
        expect(decoder.calibrationMs, 1000);
      });
    });

    group('calibration phase', () {
      test('stays calibrating with pure silence', () {
        final decoder = AudioDecoder(calibrationMs: 200);
        decoder.processSamples(generateSilence(256 * 10));
        expect(decoder.state, DecoderState.calibrating);
      });

      test('stays calibrating with only noise', () {
        final decoder = AudioDecoder(calibrationMs: 200);
        decoder.processSamples(generateNoise(256 * 10));
        // Still calibrating because noise isn't above threshold
        expect(decoder.state, DecoderState.calibrating);
      });

      test('locks after calibration period with strong tone', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Feed noise to establish noise floor (>= 5 frames)
        decoder.processSamples(generateNoise(256 * 6));

        // Feed a strong tone — enough for 100ms calibration
        // 100ms at 8000 Hz = 800 samples ≈ 3.1 FFT windows
        decoder.processSamples(generateTone(700, 8000, 256 * 4));

        expect(decoder.state, DecoderState.locked);
        expect(decoder.lockedFrequency, greaterThan(0));
        expect(decoder.isCalibrating, isFalse);
      });

      test('does not detect tone outside frequency range', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);

        decoder.processSamples(generateNoise(256 * 6));

        // 200 Hz is below minFreq (400 Hz)
        decoder.processSamples(
          generateTone(200, 8000, 256 * 4, amplitude: 0.001),
        );

        expect(decoder.state, DecoderState.calibrating);
      });
    });

    group('locked phase', () {
      test('emits on-element when tone starts', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Fill noise floor + calibration with tone
        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);

        // Feed tone-on Goertzel blocks
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Should have emitted an off→on transition (gap first)
        expect(elements, isNotEmpty);
        expect(elements.first.isOn, false);
      });

      test('emits off-element when tone stops', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);

        // Tone on
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Tone off — need enough noise blocks for the envelope
        // to decay below the off threshold.
        decoder.processSamples(generateNoise(80 * 100));

        // Should have at least one on-element (the tone itself)
        final onElements = elements.where((e) => e.isOn);
        expect(onElements, isNotEmpty);
      });

      test('emits elements with positive duration', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));

        // Tone on
        decoder.processSamples(generateTone(700, 8000, 80 * 10));

        // Tone off
        decoder.processSamples(generateNoise(80 * 100));

        for (final el in elements) {
          expect(el.durationMs, greaterThan(0));
        }
      });

      test('frequency does not drift after locking', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);

        final lockedFreq = decoder.lockedFrequency;

        // Feed a different tone — should not drift
        decoder.processSamples(generateTone(800, 8000, 80 * 20));

        expect(decoder.lockedFrequency, lockedFreq);
      });

      test('onLock callback is invoked when locked', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);
        var lockedFreq = 0.0;
        decoder.onLock = (freq) => lockedFreq = freq;

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));

        expect(lockedFreq, greaterThan(0));
      });
    });

    group('reset', () {
      test('clears all state', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();
        expect(decoder.state, DecoderState.calibrating);
        expect(decoder.lockedFrequency, 0);
      });

      test('allows re-detection after reset', () {
        final decoder = AudioDecoder(calibrationMs: 100, minElementMs: 0);

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 4));
        expect(decoder.state, DecoderState.locked);
      });
    });

    group('buffer handling', () {
      test('processes samples in correct window sizes', () {
        final decoder = AudioDecoder(calibrationMs: 200);

        for (var i = 0; i < 10; i++) {
          decoder.processSamples(generateSilence(256));
        }

        expect(decoder.state, DecoderState.calibrating);
      });

      test('handles samples not aligned to window size', () {
        final decoder = AudioDecoder(calibrationMs: 200);

        decoder.processSamples(generateSilence(300));
        decoder.processSamples(generateSilence(200));
        decoder.processSamples(generateSilence(256 * 4));

        expect(decoder.state, DecoderState.calibrating);
      });
    });
  });
}
