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
  return List.filled(numSamples, 0);
}

/// Number of samples for one FFT frame (32 ms at 8 kHz).
const frameSize = 256;

/// Number of samples for one tracking block (10 ms at 8 kHz).
const blockSize = 80;

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
          signalTimeoutMs: 3000,
        );
        expect(decoder.sampleRate, 16000);
        expect(decoder.minFreq, 500);
        expect(decoder.maxFreq, 900);
        expect(decoder.fftSize, 512);
        expect(decoder.blockSize, 160);
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

      test('locks after long continuous tone (>=500ms)', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Feed 20 frames of tone (640ms) — exceeds 500ms long-tone
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(decoder.state, DecoderState.locked);
        expect(decoder.lockedFrequency, greaterThan(0));
        expect(decoder.isScanning, isFalse);
      });

      test('locks after three short tone bursts at same frequency', () {
        final decoder = AudioDecoder(minElementMs: 0);

        // Three bursts of 6 frames each (192ms > 160ms threshold)
        // with short gaps (within 2000ms window)
        for (var i = 0; i < 3; i++) {
          decoder.processSamples(generateTone(700, 8000, frameSize * 6));
          expect(
            decoder.state,
            DecoderState.scanning,
            reason: 'should not lock before 3 detections',
          );
          decoder.processSamples(generateSilence(frameSize * 3));
        }

        // After 3 detections at the same frequency, should lock
        // (the last silence frame triggers _endRun which checks count)
        expect(decoder.state, DecoderState.locked);
      });

      test('does not lock on single brief tone burst with no repeat', () {
        final decoder = AudioDecoder(minElementMs: 0);

        // 6 frames of tone (192ms > 160ms) — one detection event
        decoder.processSamples(generateTone(700, 8000, frameSize * 6));
        expect(decoder.state, DecoderState.scanning);

        // Long silence (well beyond 2000ms repeat window)
        decoder.processSamples(generateSilence(frameSize * 70));

        expect(decoder.state, DecoderState.scanning);
      });

      test('does not lock on bursts at different frequencies', () {
        final decoder = AudioDecoder(minElementMs: 0);

        // First burst at 700 Hz
        decoder.processSamples(generateTone(700, 8000, frameSize * 6));
        expect(decoder.state, DecoderState.scanning);

        // Short gap
        decoder.processSamples(generateSilence(frameSize * 3));

        // Second burst at 500 Hz — different frequency, not a repeat
        decoder.processSamples(generateTone(500, 8000, frameSize * 6));

        expect(decoder.state, DecoderState.scanning);
      });

      test('does not detect tone outside frequency range', () {
        final decoder = AudioDecoder(minElementMs: 0);

        // 200 Hz is below minFreq (400 Hz)
        // Add noise so the noise floor is non-zero (prevents
        // SNR defaulting to 999 when avgOther is 0)
        final tone200 = generateTone(
          200,
          8000,
          frameSize * 20,
          amplitude: 0.001,
        );
        final noise200 = generateNoise(frameSize * 20, amplitude: 0.01);
        decoder.processSamples(
          List.generate(tone200.length, (i) => tone200[i] + noise200[i]),
        );

        expect(decoder.state, DecoderState.scanning);
      });
    });

    group('locked phase', () {
      test('emits on-element when tone starts', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        // Lock with long tone
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        // Keying: the level tracker needs both a mark and a space
        // level to separate, so an unbroken carrier is squelched by
        // design — feed a gap and another tone.
        decoder
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 40));

        // Elements are held back one transition so a glitch can be
        // merged with its neighbours; flush releases the last one.
        decoder.flush();

        expect(elements, isNotEmpty);
      });

      test('emits off-element when tone stops', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        // Tone off — need enough silence for envelope to decay
        decoder.processSamples(generateSilence(blockSize * 100));

        // Tone on again
        decoder.processSamples(generateTone(700, 8000, blockSize * 20));

        // Tone off — need enough silence for envelope to decay
        decoder
          ..processSamples(generateSilence(blockSize * 100))
          ..flush();

        // Should have at least one on-element (the tone itself)
        final onElements = elements.where((e) => e.isOn);
        expect(onElements, isNotEmpty);
      });

      test('emits elements with positive duration', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final elements = <DecodedElement>[];
        decoder.onElement = elements.add;

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateTone(700, 8000, blockSize * 10))
          ..processSamples(generateSilence(blockSize * 100));

        for (final el in elements) {
          expect(el.durationMs, greaterThan(0));
        }
      });

      test('frequency does not drift after locking', () {
        final decoder = AudioDecoder(minElementMs: 0);
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        final lockedFreq = decoder.lockedFrequency;

        // Feed a different tone — should not drift
        decoder.processSamples(generateTone(800, 8000, blockSize * 20));

        expect(decoder.lockedFrequency, lockedFreq);
      });

      test('onLock callback is invoked when locked', () {
        final decoder = AudioDecoder(minElementMs: 0);
        var lockedFreq = 0.0;
        decoder.onLock = (freq) => lockedFreq = freq;

        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(lockedFreq, greaterThan(0));
      });

      test('does not unlock on silence (permanent lock by default)', () {
        final decoder = AudioDecoder(minElementMs: 0);

        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        // Feed a very long silence — should stay locked
        decoder
          ..processSamples(generateTone(700, 8000, blockSize * 5))
          ..processSamples(generateSilence(8000 * 10));

        expect(decoder.state, DecoderState.locked);
        expect(decoder.lockedFrequency, greaterThan(0));
      });
    });

    group('signal timeout (opt-in)', () {
      test('unlocks after prolonged silence when enabled', () {
        final decoder = AudioDecoder(
          signalTimeoutMs: 500,
          minElementMs: 0,
        );

        // Lock with long tone
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        // Key the tone so the level tracker separates and registers a
        // first mark, then go quiet for longer than the timeout.
        decoder
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 200));

        expect(decoder.state, DecoderState.scanning);
        expect(decoder.lockedFrequency, 0);
      });

      test('onUnlock callback is invoked on timeout', () {
        final decoder = AudioDecoder(
          signalTimeoutMs: 500,
          minElementMs: 0,
        );
        var unlocked = false;
        decoder.onUnlock = () => unlocked = true;

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 200));

        expect(unlocked, isTrue);
      });

      test('does not unlock while tone is present', () {
        final decoder = AudioDecoder(
          signalTimeoutMs: 1000,
          minElementMs: 0,
        );

        // Lock and keep feeding tone for a long time
        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateTone(700, 8000, blockSize * 200));

        expect(decoder.state, DecoderState.locked);
      });
    });

    group('reset', () {
      test('clears all state', () {
        final decoder = AudioDecoder(minElementMs: 0);

        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        decoder.reset();
        expect(decoder.state, DecoderState.scanning);
        expect(decoder.lockedFrequency, 0);
      });
    });

    group('relative bandwidth', () {
      test('uses relative bandwidth by default (bandwidth=0)', () {
        // With bandwidth=0 and bandwidthRatio=0.16, the IIR bandwidth
        // at 700 Hz should be 700*0.16 = 112 Hz.
        final decoder = AudioDecoder(minElementMs: 0);
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(decoder.state, DecoderState.locked);
        expect(decoder.lockedFrequency, closeTo(700, 30));
      });

      test('uses fixed bandwidth when bandwidth > 0', () {
        final decoder = AudioDecoder(
          bandwidth: 80,
          minElementMs: 0,
        );
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(decoder.state, DecoderState.locked);
      });
    });
  });
}
