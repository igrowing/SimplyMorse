import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/level_tracker.dart';

/// Feeds [count] samples of amplitude [level] and returns the last
/// decision.
bool feed(LevelTracker t, double level, int count, {double dtMs = 5}) {
  var on = false;
  for (var i = 0; i < count; i++) {
    on = t.process(level, dtMs);
  }
  return on;
}

void main() {
  group('LevelTracker', () {
    test('is not ready before bootstrap completes', () {
      final t = LevelTracker(bootstrapSamples: 50);
      expect(t.isReady, isFalse);
      feed(t, 0.01, 10);
      expect(t.isReady, isFalse);
    });

    test('seed makes it ready immediately', () {
      final t = LevelTracker()..seed(markDb: -20, spaceDb: -60);
      expect(t.isReady, isTrue);
      expect(t.separationDb, closeTo(40, 1e-9));
    });

    test('seed keeps the space level below the mark level', () {
      final t = LevelTracker()..seed(markDb: -40, spaceDb: -10);
      expect(t.spaceDb, lessThan(t.markDb!));
    });

    test('threshold sits below the mark level when SNR is high', () {
      final t = LevelTracker(thresholdOffsetDb: 3, noiseMarginDb: 10)
        ..seed(markDb: -20, spaceDb: -70);
      // 50 dB separation: auto-sensitivity scales the offset down
      // to 90 % (snrFactor = 20/50 clamped to 0.9), giving an
      // adaptive offset of 2.7 dB. The mark anchor (-22.7) is above
      // the space anchor (-60), so it wins — a higher threshold
      // for strong signals, for cleaner edges and noise resistance.
      expect(t.thresholdDb, closeTo(-22.7, 1e-9));
    });

    test('threshold keeps a margin above the space level at low SNR', () {
      final t = LevelTracker(thresholdOffsetDb: 3, noiseMarginDb: 10)
        ..seed(markDb: -20, spaceDb: -24);
      // 4 dB separation: the margin is capped at 60 % of it, so the
      // space anchor is -24 + 2.4 = -21.6, which beats the mark
      // anchor of -23.3 (auto-sensitivity scales the offset up to
      // 110 %: 3 × 1.1 = 3.3) and pulls the threshold up towards the
      // tone.
      expect(t.thresholdDb, closeTo(-21.6, 1e-9));
    });

    test('auto-sensitivity scales offset by SNR', () {
      // At 20 dB separation, the factor is 1.0 (baseline).
      final t20 = LevelTracker(thresholdOffsetDb: 4)
        ..seed(markDb: -20, spaceDb: -40);
      expect(t20.thresholdDb, closeTo(-24, 1e-9));

      // At 40 dB separation, the factor is 0.9 (clamped from 0.5).
      final t40 = LevelTracker(thresholdOffsetDb: 4)
        ..seed(markDb: -20, spaceDb: -60);
      expect(t40.thresholdDb, closeTo(-23.6, 1e-9));

      // At 10 dB separation, the factor is 1.1 (clamped from 2.0),
      // but the space anchor (-24.0) beats the mark anchor (-24.4).
      final t10 = LevelTracker(thresholdOffsetDb: 4)
        ..seed(markDb: -20, spaceDb: -30);
      expect(t10.thresholdDb, closeTo(-24.0, 1e-9));
    });

    test('squelches while the two levels are closer than the minimum', () {
      final t = LevelTracker(minSeparationDb: 6)
        ..seed(markDb: -20, spaceDb: -23);
      expect(t.isConfident, isFalse);
      // Even a sample far above the threshold reports off while the
      // levels are this close — there is no signal worth decoding.
      expect(t.process(1, 5), isFalse);
    });

    test('detects a mark once the levels separate', () {
      final t = LevelTracker()..seed(markDb: -20, spaceDb: -70);
      // -70 dB is 0.000316 in amplitude, -20 dB is 0.1.
      expect(feed(t, 0.1, 10), isTrue);
      expect(feed(t, 0.0003, 60), isFalse);
    });

    test('hysteresis holds the state between the two thresholds', () {
      final t = LevelTracker(hysteresisDb: 3, thresholdOffsetDb: 6)
        ..seed(markDb: -20, spaceDb: -60);
      // 40 dB separation: auto-sensitivity scales offset to 6 × 0.9 =
      // 5.4. Threshold is -25.4 dB, band is -22.4 to -28.4 dB.
      final threshold = t.thresholdDb;
      final inBand = pow(10, threshold / 20).toDouble();
      expect(feed(t, inBand, 5), isFalse, reason: 'starts off, stays off');

      final t2 = LevelTracker(hysteresisDb: 3, thresholdOffsetDb: 6)
        ..seed(markDb: -20, spaceDb: -60);
      feed(t2, 0.1, 5); // well above threshold + hysteresis, turns on
      expect(t2.isOn, isTrue);
      expect(feed(t2, inBand, 3), isTrue, reason: 'held on inside the band');
    });

    test('mark level follows a signal that gets quieter', () {
      final t = LevelTracker(attackMs: 120, releaseMs: 150)
        ..seed(markDb: -20, spaceDb: -70);
      final before = t.markDb!;
      // A 20 dB quieter mark, held for well over the release constant.
      feed(t, 0.01, 400);
      expect(t.markDb, lessThan(before - 10));
    });

    test('seedFromEnvelopes derives both levels from a batch', () {
      final envelopes = <double>[
        ...List.filled(50, 0.001),
        ...List.filled(50, 0.1),
      ];
      final t = LevelTracker()..seedFromEnvelopes(envelopes);
      expect(t.isReady, isTrue);
      expect(t.markDb, greaterThan(t.spaceDb!));
      expect(t.separationDb, greaterThan(20));
    });

    test('seedFromEnvelopes ignores batches that are too small', () {
      final t = LevelTracker()..seedFromEnvelopes([0.1, 0.2]);
      expect(t.isReady, isFalse);
    });

    test('reset clears everything', () {
      final t = LevelTracker()..seed(markDb: -20, spaceDb: -60);
      feed(t, 0.1, 5);
      t.reset();
      expect(t.isReady, isFalse);
      expect(t.isOn, isFalse);
      expect(t.separationDb, 0);
    });
  });
}
