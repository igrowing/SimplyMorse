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
        expect(decoder.isScanning, isTrue);
        expect(decoder.isCalibrating, isTrue); // backward compat alias
        expect(decoder.lockedFrequency, 0);
      });

      test('reset returns to scanning state', () {
        final decoder = AudioDecoder();
        decoder.reset();
        expect(decoder.state, DecoderState.scanning);
        expect(decoder.lockedFrequency, 0);
      });

      test('has configurable parameters', () {
        final decoder = AudioDecoder(
          sampleRate: 16000,
          minFreq: 500,
          maxFreq: 900,
          fftSize: 512,
          blockSize: 160,
          scanPersistenceFrames: 5,
          signalTimeoutMs: 3000,
        );
        expect(decoder.sampleRate, 16000);
        expect(decoder.minFreq, 500);
        expect(decoder.maxFreq, 900);
        expect(decoder.fftSize, 512);
        expect(decoder.blockSize, 160);
        expect(decoder.scanPersistenceFrames, 5);
        expect(decoder.signalTimeoutMs, 3000);
      });
    });

    group('scanning phase', () {
      test('stays scanning with pure silence', () {
        final decoder = AudioDecoder();
        // Feed 5 seconds of silence — should never lock
        decoder.processSamples(generateSilence(8000 * 5));
        expect(decoder.state, DecoderState.scanning);
      });

      test('stays scanning with only noise', () {
        final decoder = AudioDecoder();
        // Feed 5 seconds of noise — no sustained tone to lock on
        decoder.processSamples(generateNoise(8000 * 5));
        expect(decoder.state, DecoderState.scanning);
      });

      test('locks after persistent tone with strong signal', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Feed a strong tone for enough frames to pass persistence
        // 5 frames * 256 samples = 1280 samples = 160ms
        decoder.processSamples(generateTone(700, 8000, 256 * 8));

        expect(decoder.state, DecoderState.locked);
        expect(decoder.lockedFrequency, greaterThan(0));
        expect(decoder.isScanning, isFalse);
      });

      test('does not lock on brief tone bursts', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 10,
          minElementMs: 0,
        );

        // Feed 2 frames of tone, then silence, then 2 frames of tone
        // Not enough consecutive frames to pass persistence
        decoder.processSamples(generateTone(700, 8000, 256 * 2));
        decoder.processSamples(generateSilence(256 * 5));
        decoder.processSamples(generateTone(700, 8000, 256 * 2));
        decoder.processSamples(generateSilence(256 * 5));

        expect(decoder.state, DecoderState.scanning);
      });

      test('does not detect tone outside frequency range', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 3,
          minElementMs: 0,
        );

        // 200 Hz is below minFreq (400 Hz)
        decoder.processSamples(
          generateTone(200, 8000, 256 * 10, amplitude: 0.001),
        );

        expect(decoder.state, DecoderState.scanning);
      });

      test('noise between tone bursts resets persistence counter', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 10,
          minElementMs: 0,
        );

        // 8 frames of tone (not enough for 10-frame persistence)
        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.scanning);

        // Noise resets the counter
        decoder.processSamples(generateNoise(256 * 3));

        // 8 more frames — should still need 10 consecutive
        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.scanning);
      });
    });

    group('locked phase', () {
      test('emits on-element when tone starts', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Lock with persistent tone
        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);

        // Continue feeding tone (tracking blocks)
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Should have emitted transitions
        expect(elements, isNotEmpty);
      });

      test('emits off-element when tone stops', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);

        // Tone on
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Tone off — need enough silence for envelope to decay
        decoder.processSamples(generateSilence(80 * 100));

        // Should have at least one on-element (the tone itself)
        final onElements = elements.where((e) => e.isOn);
        expect(onElements, isNotEmpty);
      });

      test('emits elements with positive duration', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        decoder.processSamples(generateTone(700, 8000, 80 * 10));
        decoder.processSamples(generateSilence(80 * 100));

        for (final el in elements) {
          expect(el.durationMs, greaterThan(0));
        }
      });

      test('frequency does not drift after locking', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);

        final lockedFreq = decoder.lockedFrequency;

        // Feed a different tone — should not drift
        decoder.processSamples(generateTone(800, 8000, 80 * 20));

        expect(decoder.lockedFrequency, lockedFreq);
      });

      test('onLock callback is invoked when locked', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );
        var lockedFreq = 0.0;
        decoder.onLock = (freq) => lockedFreq = freq;

        decoder.processSamples(generateTone(700, 8000, 256 * 8));

        expect(lockedFreq, greaterThan(0));
      });
    });

    group('signal timeout', () {
      test('unlocks after prolonged silence', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 3,
          signalTimeoutMs: 500,
          minElementMs: 0,
        );

        // Lock with tone
        decoder.processSamples(generateTone(700, 8000, 256 * 6));
        expect(decoder.state, DecoderState.locked);

        // Feed tone to trigger first on transition (sets _seenFirstOn)
        decoder.processSamples(generateTone(700, 8000, 80 * 5));

        // Feed silence long enough to exceed timeout
        // 500ms at 8000 Hz = 4000 samples
        decoder.processSamples(generateSilence(80 * 60));

        expect(decoder.state, DecoderState.scanning);
        expect(decoder.lockedFrequency, 0);
      });

      test('onUnlock callback is invoked on timeout', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 3,
          signalTimeoutMs: 500,
          minElementMs: 0,
        );
        var unlocked = false;
        decoder.onUnlock = () => unlocked = true;

        decoder.processSamples(generateTone(700, 8000, 256 * 6));
        decoder.processSamples(generateTone(700, 8000, 80 * 5));
        decoder.processSamples(generateSilence(80 * 60));

        expect(unlocked, isTrue);
      });

      test('does not unlock while tone is present', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 3,
          signalTimeoutMs: 1000,
          minElementMs: 0,
        );

        // Lock and keep feeding tone for a long time
        decoder.processSamples(generateTone(700, 8000, 256 * 6));
        decoder.processSamples(generateTone(700, 8000, 80 * 200));

        expect(decoder.state, DecoderState.locked);
      });
    });

    group('reset', () {
      test('clears all state', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );

        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();
        expect(decoder.state, DecoderState.scanning);
        expect(decoder.lockedFrequency, 0);
      });

      test('allows re-detection after reset', () {
        final decoder = AudioDecoder(
          scanPersistenceFrames: 5,
          minElementMs: 0,
        );

        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();

        decoder.processSamples(generateTone(700, 8000, 256 * 8));
        expect(decoder.state, DecoderState.locked);
      });
    });

    group('buffer handling', () {
      test('processes samples in correct window sizes', () {
        final decoder = AudioDecoder();

        for (var i = 0; i < 10; i++) {
          decoder.processSamples(generateSilence(256));
        }

        expect(decoder.state, DecoderState.scanning);
      });

      test('handles samples not aligned to window size', () {
        final decoder = AudioDecoder();

        decoder.processSamples(generateSilence(300));
        decoder.processSamples(generateSilence(200));
        decoder.processSamples(generateSilence(256 * 4));

        expect(decoder.state, DecoderState.scanning);
      });
    });
  });
}
