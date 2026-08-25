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
      test('starts in scanning state', () {
        final decoder = AudioDecoder();
        expect(decoder.state, DecoderState.scanning);
      });

      test('reset returns to scanning state', () {
        final decoder = AudioDecoder();
        decoder.reset();
        expect(decoder.state, DecoderState.scanning);
      });

      test('has configurable parameters', () {
        final decoder = AudioDecoder(
          sampleRate: 16000,
          minFreq: 500,
          maxFreq: 900,
          fftSize: 512,
          goertzelBlockSize: 160,
          confirmFrames: 5,
        );
        expect(decoder.sampleRate, 16000);
        expect(decoder.minFreq, 500);
        expect(decoder.maxFreq, 900);
        expect(decoder.fftSize, 512);
        expect(decoder.goertzelBlockSize, 160);
        expect(decoder.confirmFrames, 5);
      });
    });

    group('scanning phase', () {
      test('stays in scanning with pure silence', () {
        final decoder = AudioDecoder();
        decoder.processSamples(generateSilence(256 * 10));
        expect(decoder.state, DecoderState.scanning);
      });

      test('stays in scanning with insufficient frames', () {
        final decoder = AudioDecoder();
        // Only 3 FFT windows — not enough for noise floor (needs 5)
        decoder.processSamples(generateNoise(256 * 3));
        expect(decoder.state, DecoderState.scanning);
      });

      test('transitions to confirming when tone detected', () {
        final decoder = AudioDecoder();

        // Feed enough noise to fill the noise floor (>= 5 frames)
        decoder.processSamples(generateNoise(256 * 6));

        // Feed a strong tone in the 400-1000 Hz band
        decoder.processSamples(generateTone(700, 8000, 256));

        expect(decoder.state, DecoderState.confirming);
      });

      test('does not detect tone outside frequency range', () {
        final decoder = AudioDecoder();

        // Use noise to establish a non-zero noise floor
        decoder.processSamples(generateNoise(256 * 6));

        // 200 Hz is below minFreq (400 Hz). Using
        // low amplitude so spectral leakage stays below threshold.
        decoder.processSamples(generateTone(200, 8000, 256, amplitude: 0.001));

        expect(decoder.state, DecoderState.scanning);
      });
    });

    group('confirming phase', () {
      test('locks after confirmFrames consecutive matches', () {
        final decoder = AudioDecoder(confirmFrames: 3);

        // Fill noise floor with stable noise
        decoder.processSamples(generateNoise(256 * 6));

        decoder.processSamples(generateTone(700, 8000, 256));
        expect(decoder.state, DecoderState.confirming);

        decoder.processSamples(generateTone(700, 8000, 256));
        expect(decoder.state, DecoderState.confirming);

        decoder.processSamples(generateTone(700, 8000, 256));
        expect(decoder.state, DecoderState.locked);
      });

      test('returns to scanning if peak shifts significantly', () {
        final decoder = AudioDecoder(confirmFrames: 3);

        decoder.processSamples(generateNoise(256 * 6));

        decoder.processSamples(generateTone(700, 8000, 256));
        expect(decoder.state, DecoderState.confirming);

        // 950 Hz is far enough that the peak bin differs > ±1
        decoder.processSamples(generateTone(950, 8000, 256, amplitude: 0.8));
        expect(decoder.state, DecoderState.scanning);
      });
    });

    group('locked phase', () {
      test('emits on-element when tone starts', () {
        final decoder = AudioDecoder(confirmFrames: 3);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Fill noise floor + confirm + lock
        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));
        expect(decoder.state, DecoderState.locked);

        // Feed tone-on Goertzel blocks
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Should have emitted an off→on transition (gap first)
        expect(elements, isNotEmpty);
        expect(elements.first.isOn, false);
      });

      test('emits off-element when tone stops', () {
        final decoder = AudioDecoder(confirmFrames: 3);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Fill noise floor + confirm + lock
        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));
        expect(decoder.state, DecoderState.locked);

        // Tone on
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Tone off — need enough noise blocks for the envelope
        // to decay below the off threshold. Release time is 50ms,
        // hop is 10ms → ~70+ blocks needed.
        decoder.processSamples(generateNoise(80 * 100));

        // Should have at least one on-element (the tone itself)
        final onElements = elements.where((e) => e.isOn);
        expect(onElements, isNotEmpty);
      });

      test('emits elements with positive duration', () {
        final decoder = AudioDecoder(confirmFrames: 3);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));

        // Tone on
        decoder.processSamples(generateTone(700, 8000, 80 * 10));

        // Tone off
        decoder.processSamples(generateNoise(80 * 100));

        for (final el in elements) {
          expect(el.durationMs, greaterThan(0));
        }
      });
    });

    group('reset', () {
      test('clears all state', () {
        final decoder = AudioDecoder(confirmFrames: 3);

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();
        expect(decoder.state, DecoderState.scanning);
      });

      test('allows re-detection after reset', () {
        final decoder = AudioDecoder(confirmFrames: 3);

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();

        decoder.processSamples(generateNoise(256 * 6));
        decoder.processSamples(generateTone(700, 8000, 256 * 3));
        expect(decoder.state, DecoderState.locked);
      });
    });

    group('buffer handling', () {
      test('processes samples in correct window sizes', () {
        final decoder = AudioDecoder(fftSize: 256, confirmFrames: 3);

        for (var i = 0; i < 10; i++) {
          decoder.processSamples(generateSilence(256));
        }

        expect(decoder.state, DecoderState.scanning);
      });

      test('handles samples not aligned to window size', () {
        final decoder = AudioDecoder(fftSize: 256, confirmFrames: 3);

        decoder.processSamples(generateSilence(300));
        decoder.processSamples(generateSilence(200));
        decoder.processSamples(generateSilence(256 * 4));

        expect(decoder.state, DecoderState.scanning);
      });
    });
  });
}
