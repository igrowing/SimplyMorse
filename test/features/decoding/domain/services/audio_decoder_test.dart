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
        final decoder = AudioDecoder(signalTimeoutMs: 500, minElementMs: 0);

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
        final decoder = AudioDecoder(signalTimeoutMs: 500, minElementMs: 0);
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
        final decoder = AudioDecoder(signalTimeoutMs: 1000, minElementMs: 0);

        // Lock and keep feeding tone for a long time
        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateTone(700, 8000, blockSize * 200));

        expect(decoder.state, DecoderState.locked);
      });
    });

    group('debug logging', () {
      test('onDebugScanning reports concentration and run state', () {
        final decoder = AudioDecoder(minElementMs: 0);
        Map<String, Object?>? last;
        decoder.onDebugScanning =
            ({
              required timestampMs,
              required frameIdx,
              required dominantBin,
              required dominantFreqHz,
              required dominantPower,
              required avgOtherPower,
              required snr,
              required concentration,
              required noiseFloor,
              required runLen,
              required runBin,
              required runFreqHz,
              required detectionCount,
              required framesSinceDetection,
              required monotonic,
              required locked,
            }) {
              last = {
                'timestampMs': timestampMs,
                'frameIdx': frameIdx,
                'concentration': concentration,
                'snr': snr,
                'runLen': runLen,
                'runBin': runBin,
                'monotonic': monotonic,
                'locked': locked,
                'noiseFloor': noiseFloor,
              };
            };

        decoder.processSamples(generateTone(700, 8000, frameSize * 2));

        expect(last, isNotNull);
        expect(last!['monotonic'], isTrue);
        // A pure keyed tone concentrates nearly all its in-band
        // energy around one frequency — the property that
        // rejects voice and bursts.
        expect(last!['concentration']! as double, greaterThan(0.6));
        expect(last!['snr']! as double, greaterThan(4));
        // Both frames were monotonic at the same bin.
        expect(last!['runLen'], 2);
        expect(last!['runBin'], 22);
        // _frameIndex counts processed FFT frames 1-based.
        expect(last!['frameIdx'], 2);
      });

      test('onDebugLock reports the long_tone path and bin grid', () {
        final decoder = AudioDecoder(minElementMs: 0);
        Map<String, Object?>? lockRow;
        decoder.onDebugLock =
            ({
              required timestampMs,
              required freqHz,
              required interpFreqHz,
              required bin,
              required bestAvgPower,
              required noiseFloor,
              required onThresholdFactor,
              required path,
            }) {
              lockRow = {
                'timestampMs': timestampMs,
                'freqHz': freqHz,
                'bin': bin,
                'bestAvgPower': bestAvgPower,
                'noiseFloor': noiseFloor,
                'path': path,
              };
            };

        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(decoder.state, DecoderState.locked);
        expect(lockRow, isNotNull);
        expect(lockRow!['path'], 'long_tone');
        // Parabolic interpolation recovers the true frequency
        // from the 31.25 Hz FFT bin grid (700 Hz = bin 22.4).
        expect(lockRow!['bin'], 22);
        expect(lockRow!['freqHz']! as double, closeTo(700, 10));
        expect(lockRow!['timestampMs']! as int, greaterThan(0));
        expect(lockRow!['noiseFloor']! as double, greaterThanOrEqualTo(0));
      });

      test('onDebugDetection and onDebugLock report the repeats path', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final detectionCounts = <int>[];
        decoder.onDebugDetection =
            ({
              required timestampMs,
              required frameIdx,
              required runBin,
              required runFreqHz,
              required runLenFrames,
              required runMs,
              required detectionCount,
              required gapFrames,
            }) {
              detectionCounts.add(detectionCount);
            };
        Map<String, Object?>? lockRow;
        decoder.onDebugLock =
            ({
              required freqHz,
              required interpFreqHz,
              required bin,
              required bestAvgPower,
              required noiseFloor,
              required onThresholdFactor,
              required path,
              required timestampMs,
            }) {
              lockRow = {'path': path, 'freqHz': freqHz};
            };

        for (var i = 0; i < 3; i++) {
          decoder.processSamples(generateTone(700, 8000, frameSize * 6));
          decoder.processSamples(generateSilence(frameSize * 3));
        }

        expect(decoder.state, DecoderState.locked);
        expect(detectionCounts, [1, 2, 3]);
        expect(lockRow!['path'], 'repeats');
      });

      test('onDebugReplay reports seeded levels and profile', () {
        final decoder = AudioDecoder(minElementMs: 0);
        Map<String, Object?>? replayRow;
        decoder.onDebugReplay =
            ({
              required timestampMs,
              required blocks,
              required windowMs,
              required markDb,
              required spaceDb,
              required ditEstimateMs,
              required profile,
              required detail,
            }) {
              replayRow = {
                'blocks': blocks,
                'windowMs': windowMs,
                'markDb': markDb,
                'spaceDb': spaceDb,
                'ditEstimateMs': ditEstimateMs,
                'profile': profile,
              };
            };

        for (var i = 0; i < 3; i++) {
          decoder.processSamples(generateTone(700, 8000, frameSize * 6));
          decoder.processSamples(generateSilence(frameSize * 3));
        }

        expect(replayRow, isNotNull);
        // The three-burst pattern gives the dit estimator three
        // on-runs, so it can pick a profile: 192 ms marks are
        // slower than the 85.7 ms fast boundary → normal.
        expect(replayRow!['blocks']! as int, greaterThan(0));
        expect(replayRow!['ditEstimateMs']! as int, greaterThan(150));
        expect(replayRow!['ditEstimateMs']! as int, lessThan(250));
        expect(replayRow!['profile'], 'normal');
        expect(
          replayRow!['markDb']! as double,
          greaterThan(replayRow!['spaceDb']! as double),
        );
      });

      test('onDebugReplay reports convergence passes over the window', () {
        final decoder = AudioDecoder(minElementMs: 0);
        String? replayDetail;
        int? blockCount;
        decoder.onDebugReplay =
            ({
              required timestampMs,
              required blocks,
              required windowMs,
              required markDb,
              required spaceDb,
              required ditEstimateMs,
              required profile,
              required detail,
            }) {
              blockCount = blocks;
              if (blocks > 0) replayDetail = detail;
            };

        for (var i = 0; i < 3; i++) {
          decoder.processSamples(generateTone(700, 8000, frameSize * 6));
          decoder.processSamples(generateSilence(frameSize * 3));
        }

        expect(blockCount! > 0, isTrue);
        // The replay seed is no longer the raw percentile — it is
        // the fixed point of the adaptation converged over the
        // window, and the detail reports how many passes that took.
        expect(replayDetail, isNotNull);
        expect(replayDetail, matches(RegExp('^converge_passes=[1-9]')));
      });

      test('onDebugTransition reports ascending sequence numbers', () {
        final decoder = AudioDecoder(minElementMs: 0);
        final seqs = <int>[];
        decoder.onDebugTransition =
            ({
              required timestampMs,
              required blockIdx,
              required isOn,
              required durationMs,
              required seq,
              required ditMs,
              required wpm,
            }) {
              seqs.add(seq);
            };

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..flush();

        expect(seqs, isNotEmpty);
        expect(seqs, List.generate(seqs.length, (i) => i + 1));
      });

      test('onDebugUnlock reports content-time and reason', () {
        final decoder = AudioDecoder(signalTimeoutMs: 500, minElementMs: 0);
        Map<String, Object?>? unlockRow;
        decoder.onDebugUnlock =
            ({
              required timestampMs,
              required reason,
              required blockIdx,
            }) {
              unlockRow = {
                'timestampMs': timestampMs,
                'reason': reason,
                'blockIdx': blockIdx,
              };
            };

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 200));

        expect(decoder.state, DecoderState.scanning);
        expect(unlockRow, isNotNull);
        expect(unlockRow!['reason'], 'signal_timeout');
        // Content-time timestamp — the old wiring hardcoded 0.
        expect(unlockRow!['timestampMs']! as int, greaterThan(0));
        expect(unlockRow!['blockIdx']! as int, greaterThan(0));
      });

      test('onDebugToneQuality reports tone presence without changing '
          'the decode', () {
        final decoder = AudioDecoder(
          minElementMs: 0,
          toneQualityIntervalBlocks: 10,
        );
        final qualityRows = <Map<String, Object?>>[];
        decoder.onDebugToneQuality =
            ({
              required timestampMs,
              required blockIdx,
              required lockedFreqHz,
              required lockedPower,
              required avgOtherPower,
              required snr,
              required concentration,
              required tonePresent,
            }) {
              qualityRows.add({
                'snr': snr,
                'concentration': concentration,
                'present': tonePresent,
              });
            };

        // Lock on a 700 Hz tone.
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        // Tone present: quality checks must fire and see a
        // concentrated, high-SNR signal.
        final before = qualityRows.length;
        decoder.processSamples(generateTone(700, 8000, blockSize * 40));
        expect(qualityRows.length, greaterThan(before));
        expect(
          qualityRows.last['present'],
          isTrue,
          reason: 'a keyed tone at the locked frequency must read present',
        );
        expect(qualityRows.last['concentration'], greaterThan(0.5));

        // Silence: no other-band power, so the frame can read as
        // high-SNR, but concentration collapses — a tone is not
        // present. Either way `present` must go false.
        decoder.processSamples(generateSilence(blockSize * 40));
        expect(qualityRows.last['present'], isFalse);

        // Observation only: the decoder stays locked throughout.
        expect(decoder.state, DecoderState.locked);
      });

      test('tone gate stays open through legitimate word gaps', () {
        // The gate must never close mid-transmission: measured on
        // the reference recordings, the 3 WPM inter-word gap is
        // ~5.4 s and the inter-repetition pause ~4.9 s — the 8000 ms
        // default must clear both (4000 ms closed mid-pause and
        // corrupted the first character after it in the recordings).
        for (final timeoutMs in [0, 8000]) {
          final decoder = AudioDecoder(
            minElementMs: 0,
            toneGateTimeoutMs: timeoutMs,
          );
          final gateRows = <bool>[];
          decoder.onDebugToneGate =
              ({
                required timestampMs,
                required blockIdx,
                required closed,
                required absentMs,
              }) {
                gateRows.add(closed);
              };
          final transitions = <int>[];
          decoder.onDebugTransition =
              ({
                required timestampMs,
                required blockIdx,
                required isOn,
                required durationMs,
                required seq,
                required ditMs,
                required wpm,
              }) {
                transitions.add(seq);
              };

          decoder
            ..processSamples(generateTone(700, 8000, frameSize * 20))
            // 5.5 s gap: above the longest measured recording pause
            // (5.4 s), below the 8000 ms default.
            ..processSamples(generateSilence(8000 * 55 ~/ 10))
            ..processSamples(generateTone(700, 8000, blockSize * 20))
            ..processSamples(generateSilence(blockSize * 40))
            ..flush();

          expect(decoder.state, DecoderState.locked);
          expect(
            gateRows,
            isEmpty,
            reason: 'gate must not close for a $timeoutMs ms configuration',
          );
          expect(transitions, isNotEmpty);
        }
      });

      test('tone gate closes after timeout and suppresses junk elements', () {
        // Explicit 4000 ms timeout keeps the noise span short; the
        // default (8000 ms) is exercised by the recordings.
        final decoder = AudioDecoder(
          minElementMs: 0,
          toneGateTimeoutMs: 4000,
        );
        final gateRows = <Map<String, Object?>>[];
        decoder.onDebugToneGate =
            ({
              required timestampMs,
              required blockIdx,
              required closed,
              required absentMs,
            }) {
              gateRows.add({
                'timestampMs': timestampMs,
                'closed': closed,
                'absentMs': absentMs,
              });
            };
        final transitions = <int>[];
        decoder.onDebugTransition =
            ({
              required timestampMs,
              required blockIdx,
              required isOn,
              required durationMs,
              required seq,
              required ditMs,
              required wpm,
            }) {
              transitions.add(timestampMs);
            };

        // Lock, then replace the tone with room noise (the voice
        // scenario: in-band energy, but no concentrated tone).
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);
        final transitionsAtClose = transitions.length;

        // 4.5 s of noise: past the 4000 ms gate timeout.
        final noise = generateNoise(8000 * 45 ~/ 10, amplitude: 0.05);
        decoder.processSamples(noise);
        decoder.flush();

        expect(gateRows, isNotEmpty);
        expect(gateRows.last['closed'], isTrue);
        expect(gateRows.last['absentMs'], greaterThan(4000));
        // No transitions may be emitted after the gate closes —
        // whatever the noise does to the band-pass envelope must
        // not become elements.
        expect(
          transitions.length,
          transitionsAtClose,
          reason: 'voice/noise past the gate must not emit elements',
        );
      });

      test('tone gate reopens when the tone returns', () {
        final decoder = AudioDecoder(
          minElementMs: 0,
          toneGateTimeoutMs: 4000,
        );
        final gateRows = <Map<String, Object?>>[];
        decoder.onDebugToneGate =
            ({
              required timestampMs,
              required blockIdx,
              required closed,
              required absentMs,
            }) {
              gateRows.add({'closed': closed});
            };
        final transitions = <int>[];
        decoder.onDebugTransition =
            ({
              required timestampMs,
              required blockIdx,
              required isOn,
              required durationMs,
              required seq,
              required ditMs,
              required wpm,
            }) {
              transitions.add(timestampMs);
            };

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateNoise(8000 * 45 ~/ 10, amplitude: 0.05));
        expect(gateRows, isNotEmpty);
        expect(gateRows.last['closed'], isTrue);

        // The keyed tone returns: the gate must reopen and the
        // elements must flow again.
        decoder
          ..processSamples(generateTone(700, 8000, blockSize * 20))
          ..processSamples(generateSilence(blockSize * 40))
          ..flush();

        expect(gateRows.last['closed'], isFalse);
        expect(decoder.state, DecoderState.locked);
        expect(transitions, isNotEmpty);
      });

      test('gate reopen replay recovers the first element', () {
        final decoder = AudioDecoder(
          minElementMs: 0,
          toneGateTimeoutMs: 4000,
        );
        final gateRows = <Map<String, Object?>>[];
        decoder.onDebugToneGate =
            ({
              required timestampMs,
              required blockIdx,
              required closed,
              required absentMs,
            }) {
              gateRows.add({'closed': closed, 't': timestampMs});
            };
        final replays = <Map<String, Object?>>[];
        decoder.onDebugGateReplay =
            ({
              required timestampMs,
              required blockIdx,
              required blocks,
              required spanMs,
            }) {
              replays.add({'blocks': blocks, 'spanMs': spanMs});
            };
        final transitions = <Map<String, Object?>>[];
        decoder.onDebugTransition =
            ({
              required timestampMs,
              required blockIdx,
              required isOn,
              required durationMs,
              required seq,
              required ditMs,
              required wpm,
            }) {
              transitions.add({
                't': timestampMs,
                'on': isOn,
                'dur': durationMs,
              });
            };

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateNoise(8000 * 45 ~/ 10, amplitude: 0.05));
        expect(gateRows.last['closed'], isTrue);

        final reopenedAt = gateRows.last['t'] as int;

        // A single dit returns: the replay must recover its ON edge
        // (the pre-replay code swallowed it — W became M on
        // hardware).
        decoder
          ..processSamples(generateTone(700, 8000, 1200)) // 150 ms dit
          ..processSamples(generateSilence(blockSize * 40))
          ..flush();

        expect(gateRows.last['closed'], isFalse);
        expect(
          replays,
          isNotEmpty,
          reason: 'a gate_replay row must be logged on reopen',
        );
        final afterReopen = transitions
            .where((tr) => (tr['t'] as int) >= reopenedAt - 2000)
            .toList();
        expect(afterReopen, isNotEmpty);
        final ons = afterReopen.where((tr) => tr['on'] as bool).toList();
        expect(
          ons,
          isNotEmpty,
          reason: 'the returning dit must produce a recovered ON edge',
        );
        final dit = ons.last;
        expect(
          (dit['dur'] as num).toDouble(),
          inInclusiveRange(100, 200),
          reason: 'recovered dit duration ~150 ms, got ${dit['dur']}',
        );
      });

      test('levels stay frozen while the gate is closed', () {
        final decoder = AudioDecoder(
          minElementMs: 0,
          toneGateTimeoutMs: 4000,
        );
        var gateClosed = false;
        final marksWhileClosed = <double>[];
        decoder.onDebugToneGate =
            ({
              required timestampMs,
              required blockIdx,
              required closed,
              required absentMs,
            }) {
              gateClosed = closed;
            };
        decoder.onDebugTracking =
            ({
              required timestampMs,
              required blockIdx,
              required freqHz,
              required env,
              required envDb,
              required markDb,
              required spaceDb,
              required thresholdDb,
              required onThrDb,
              required offThrDb,
              required separationDb,
              required isReady,
              required wantOn,
              required isOn,
              required ditMs,
              required wpm,
              required profile,
            }) {
              if (gateClosed && isReady && markDb != null) {
                marksWhileClosed.add(markDb);
              }
            };

        decoder
          ..processSamples(generateTone(700, 8000, frameSize * 20))
          ..processSamples(generateNoise(8000 * 45 ~/ 10, amplitude: 0.05))
          ..flush();

        expect(gateClosed, isTrue);
        expect(marksWhileClosed, isNotEmpty);
        expect(
          marksWhileClosed.every((m) => m == marksWhileClosed.first),
          isTrue,
          reason:
              'loud in-band noise during closure must not move the '
              'frozen mark level',
        );
      });

      test('onDebugRetuneCheck reports dominant vs locked frequency', () {
        final decoder = AudioDecoder(
          reTuneIntervalBlocks: 5,
          minElementMs: 0,
        );
        final retuneRows = <Map<String, Object?>>[];
        decoder.onDebugRetuneCheck =
            ({
              required timestampMs,
              required blockIdx,
              required dominantFreqHz,
              required dominantPower,
              required lockedFreqHz,
              required lockedPower,
              required avgOtherPower,
              required unlocked,
            }) {
              retuneRows.add({
                'dominantFreqHz': dominantFreqHz,
                'lockedFreqHz': lockedFreqHz,
                'unlocked': unlocked,
              });
            };
        Map<String, Object?>? unlockRow;
        decoder.onDebugUnlock =
            ({required timestampMs, required reason, required blockIdx}) {
              unlockRow = {'reason': reason};
            };

        // Lock at 700 Hz, then QSY to 500 Hz. The new tone carries
        // background noise — a pure tone drives avgOther to ~0 in
        // float, which makes the re-tune comparison of
        // locked-frequency power against the band average
        // meaningless; a real microphone always provides a floor.
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));
        expect(decoder.state, DecoderState.locked);

        final newTone = generateTone(500, 8000, 80 * 40);
        final newNoise = generateNoise(80 * 40, amplitude: 0.01);
        final noisy = List.generate(
          newTone.length,
          (i) => newTone[i] + newNoise[i],
        );
        for (var i = 0; i < 40 && decoder.state == DecoderState.locked; i++) {
          decoder.processSamples(noisy.sublist(i * 80, (i + 1) * 80));
        }

        expect(retuneRows, isNotEmpty);
        // Every check reports the frequency the decoder is locked
        // to — the parabolic-interpolated ~691 Hz for a true 700 Hz
        // tone on this bin grid.
        for (final row in retuneRows) {
          expect(row['lockedFreqHz']! as double, closeTo(700, 15));
        }
        // The first check may still see residual 700 Hz audio from
        // the lock tone trailing the pipeline; the unlock happens
        // on the first check with a genuine 500 Hz dominant.
        expect(retuneRows.last['unlocked'] as bool?, isTrue);
        expect(
          retuneRows.last['dominantFreqHz']! as double,
          closeTo(500, 40),
        );
        expect(unlockRow!['reason'], 'retune');
        expect(decoder.state, DecoderState.scanning);
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
        final decoder = AudioDecoder(bandwidth: 80, minElementMs: 0);
        decoder.processSamples(generateTone(700, 8000, frameSize * 20));

        expect(decoder.state, DecoderState.locked);
      });
    });
  });
}
