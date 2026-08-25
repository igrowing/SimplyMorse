import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';

void main() {
  group('BrightnessThreshold', () {
    test(
      'stays off when range is below minRange',
      () {
        final bt = BrightnessThreshold(
          minRange: 0.1,
        );
        expect(bt.process(0.5), isFalse);
        expect(bt.process(0.51), isFalse);
        expect(bt.process(0.49), isFalse);
      },
    );

    test('turns on when brightness exceeds on threshold', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 1.0, // no forgetting
        minRange: 0.01,
      );

      // First sample initializes to 0.0
      bt.process(0.0);

      // 1.0 exceeds on threshold (0 + 1*0.7 = 0.7) → on
      expect(bt.process(1.0), isTrue);

      // 0.2 below off threshold (0 + 1*0.3 = 0.3) → off
      expect(bt.process(0.2), isFalse);

      // 0.8 above on threshold → on again
      expect(bt.process(0.8), isTrue);
    });

    test('hysteresis prevents flicker between thresholds', () {
      final bt = BrightnessThreshold(
        onFactor: 0.7,
        offFactor: 0.3,
        decayFactor: 1.0,
        minRange: 0.01,
      );

      bt.process(0.0);
      bt.process(1.0); // turns on
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
      bt.process(0.0);
      bt.process(1.0);
      expect(bt.range, greaterThan(0.8));

      // After 20 samples at 0.5, both bounds drift toward
      // 0.5 and the range shrinks significantly.
      for (var i = 0; i < 20; i++) {
        bt.process(0.5);
      }

      expect(bt.range, lessThan(0.3));
    });

    test('reset clears all state', () {
      final bt = BrightnessThreshold(
        decayFactor: 1.0,
      );

      bt.process(0.0);
      bt.process(1.0);
      bt.process(0.8);
      expect(bt.isOn, isTrue);

      bt.reset();
      expect(bt.isOn, isFalse);
      // After reset, next call re-initializes
      expect(bt.process(0.5), isFalse);
      expect(bt.process(0.5), isFalse);
    });

    test(
      'processes alternating high/low signal correctly',
      () {
        final bt = BrightnessThreshold(
          onFactor: 0.7,
          offFactor: 0.3,
          decayFactor: 1.0,
          minRange: 0.01,
        );

        // Prime with full range
        bt.process(0.0);
        // process(1.0) turns on
        bt.process(1.0);

        // Now test alternating pattern
        final results = <bool>[];
        for (final v in [0.1, 0.9, 0.1, 0.9]) {
          results.add(bt.process(v));
        }

        expect(results, [false, true, false, true]);
      },
    );

    test('first sample initializes min and max', () {
      final bt = BrightnessThreshold();
      bt.process(0.42);
      // No range yet — stays off
      expect(bt.isOn, isFalse);
    });
  });
}
