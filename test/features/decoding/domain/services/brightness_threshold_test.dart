import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';

void main() {
  group('BrightnessThreshold', () {
    test('stays off when range is below minRange', () {
      final bt = BrightnessThreshold(minRange: 0.1);
      expect(bt.process(0.5), isFalse);
      expect(bt.process(0.51), isFalse);
      expect(bt.process(0.49), isFalse);
    });

    test('turns on when brightness exceeds on threshold', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 1, // no forgetting
        minRange: 0.01,
      );

      // First sample initializes to 0.0
      bt.process(0);

      // 1.0 exceeds on threshold (0 + 1*0.7 = 0.7) → on
      expect(bt.process(1), isTrue);

      // 0.2 below off threshold (0 + 1*0.3 = 0.3) → off
      expect(bt.process(0.2), isFalse);

      // 0.8 above on threshold → on again
      expect(bt.process(0.8), isTrue);
    });

    test('hysteresis prevents flicker between thresholds', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 1,
        minRange: 0.01,
      );

      bt.process(0);
      bt.process(1); // turns on
      expect(bt.isOn, isTrue);

      // Between thresholds — stays on
      expect(bt.process(0.5), isTrue);
      expect(bt.process(0.6), isTrue);
      expect(bt.process(0.4), isTrue);
    });

    test('decay factor slowly narrows the range', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 0.9, // forgetRate = 0.1
        minRange: 0.001,
      );

      // Prime with extremes. After process(0.0) then
      // process(1.0): _min drifts up slightly.
      bt
        ..process(0)
        ..process(1);
      expect(bt.range, greaterThan(0.8));

      // After 20 samples at 0.5, both bounds drift toward
      // 0.5 and the range shrinks significantly.
      for (var i = 0; i < 20; i++) {
        bt.process(0.5);
      }

      expect(bt.range, lessThan(0.3));
    });

    test('reset clears all state', () {
      final bt = BrightnessThreshold(decayFactor: 1);

      bt
        ..process(0)
        ..process(1)
        ..process(0.8);
      expect(bt.isOn, isTrue);

      bt.reset();
      expect(bt.isOn, isFalse);
      // After reset, next call re-initializes
      expect(bt.process(0.5), isFalse);
      expect(bt.process(0.5), isFalse);
    });

    test('processes alternating high/low signal correctly', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 1,
        minRange: 0.01,
      );

      // Prime with full range
      bt.process(0);
      // process(1.0) turns on
      bt.process(1);

      // Now test alternating pattern
      final results = <bool>[];
      for (final v in [0.1, 0.9, 0.1, 0.9]) {
        results.add(bt.process(v));
      }

      expect(results, [false, true, false, true]);
    });

    test('first sample initializes min and max', () {
      final bt = BrightnessThreshold();
      bt.process(0.42);
      // No range yet — stays off
      expect(bt.isOn, isFalse);
    });

    test('the default thresholds form a real hysteresis band', () {
      // Regression: onFactor and offFactor both defaulted to 0.4, so
      // the two thresholds were the same number and there was no dead
      // band at all — verified across 2894 tracking rows of three
      // field captures, on_thr equalled off_thr in every single row.
      final bt = BrightnessThreshold();
      for (final v in [0.0, 1.0, 0.0, 1.0]) {
        bt.process(v, timestampMs: 0);
      }
      expect(bt.onThreshold, greaterThan(bt.offThreshold));
    });

    test('thresholds sit between the tracked ON and OFF levels', () {
      // The band is anchored to the two plateaus, not to the min/max
      // extremes: a transient darker than the OFF plateau used to drag
      // `_min` down and pull the whole band with it, landing the
      // threshold at 26% of the plateau span instead of the middle.
      final bt = BrightnessThreshold();
      var t = 0;
      for (var i = 0; i < 40; i++) {
        bt.process(i.isEven ? 0.8 : 0.2, timestampMs: t);
        t += 100;
      }
      // One frame far darker than anything the source produces.
      bt.process(-5, timestampMs: t);
      t += 100;
      for (var i = 0; i < 20; i++) {
        bt.process(i.isEven ? 0.8 : 0.2, timestampMs: t);
        t += 100;
      }

      expect(bt.offLevel, greaterThan(-1));
      expect(bt.onThreshold, greaterThan(bt.offLevel));
      expect(bt.onThreshold, lessThan(bt.onLevel));
      expect(bt.offThreshold, greaterThan(bt.offLevel));
    });
  });
}
