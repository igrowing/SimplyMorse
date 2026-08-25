import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/alpha_beta_filter.dart';

void main() {
  group('AlphaBetaFilter', () {
    test('starts uninitialized', () {
      final f = AlphaBetaFilter();
      expect(f.isInitialized, isFalse);
      expect(f.x, 0);
      expect(f.y, 0);
      expect(f.innovation, 0);
    });

    test('initialize sets position and resets velocity', () {
      final f = AlphaBetaFilter();
      f.initialize(40, 30);
      expect(f.isInitialized, isTrue);
      expect(f.x, 40);
      expect(f.y, 30);
      expect(f.vx, 0);
      expect(f.vy, 0);
    });

    test('predict moves position by velocity * dt', () {
      final f = AlphaBetaFilter(alpha: 0.7, beta: 0.1);
      f.initialize(40, 30);

      f.update(50, 40, 1.0);
      expect(f.x, closeTo(47, 0.01));
      expect(f.vx, closeTo(1.0, 0.01));

      f.predict(1.0);
      expect(f.x, closeTo(48, 0.01));
    });

    test('update corrects position toward measurement', () {
      final f = AlphaBetaFilter(alpha: 0.7, beta: 0.1);
      f.initialize(40, 30);

      f.update(45, 35, 1.0);
      expect(f.x, closeTo(43.5, 0.01));
      expect(f.y, closeTo(33.5, 0.01));
    });

    test(
      'tracks steady drift (sliding motion)',
      () {
        final f = AlphaBetaFilter(alpha: 0.7, beta: 0.1);

        var trueX = 40.0;
        var trueY = 30.0;
        f.initialize(trueX, trueY);

        for (var i = 0; i < 100; i++) {
          trueX += 2;
          trueY += 1;
          f.predict(0.033);
          f.update(trueX, trueY, 0.033);
        }

        expect(f.x, closeTo(trueX, 3));
        expect(f.y, closeTo(trueY, 2));
        expect(f.vx, closeTo(60, 15));
      },
    );

    test('smooths oscillation (hand shaking)', () {
      // Lower alpha → more smoothing
      final f = AlphaBetaFilter(alpha: 0.1, beta: 0.01);

      f.initialize(40, 30);

      for (var i = 0; i < 200; i++) {
        f.predict(0.033);
        final measX = 40 + 5 * sin(i * 0.5);
        f.update(measX, 30, 0.033);
      }

      // With low alpha, filter should stay close to the
      // mean (40) and not follow the oscillation
      expect(f.x, closeTo(40, 3));
      expect(f.vx.abs(), lessThan(10));
    });

    test('innovation reflects prediction error', () {
      final f = AlphaBetaFilter(alpha: 0.7, beta: 0.1);
      f.initialize(40, 30);

      f.predict(0.033);
      f.update(41, 30, 0.033);
      expect(f.innovation, closeTo(1, 0.5));

      f.predict(0.033);
      f.update(60, 30, 0.033);
      expect(f.innovation, greaterThan(10));
    });

    test('innovation is zero on perfect prediction', () {
      final f = AlphaBetaFilter(alpha: 0.7, beta: 0.1);
      f.initialize(40, 30);

      f.predict(0.033);
      f.update(f.x, f.y, 0.033);
      expect(f.innovation, closeTo(0, 0.001));
    });

    test('reset clears all state', () {
      final f = AlphaBetaFilter();
      f.initialize(40, 30);
      f.update(50, 40, 1.0);

      f.reset();
      expect(f.isInitialized, isFalse);
      expect(f.x, 0);
      expect(f.y, 0);
      expect(f.vx, 0);
      expect(f.vy, 0);
      expect(f.innovation, 0);
    });

    test('handles combination of shake and drift', () {
      final f = AlphaBetaFilter(alpha: 0.5, beta: 0.08);

      var trueX = 40.0;
      f.initialize(trueX, 30);

      for (var i = 0; i < 200; i++) {
        trueX += 1;
        f.predict(0.033);
        final measX = trueX + 3 * sin(i * 0.3);
        f.update(measX, 30, 0.033);
      }

      expect(f.x, closeTo(trueX, 5));
      expect(f.vx, greaterThan(0));
    });

    test('update on uninitialized filter initializes it', () {
      final f = AlphaBetaFilter();
      f.update(42, 28, 0.033);
      expect(f.isInitialized, isTrue);
      expect(f.x, 42);
      expect(f.y, 28);
    });

    test(
      'predict on uninitialized filter is a no-op',
      () {
        final f = AlphaBetaFilter();
        f.predict(0.033);
        expect(f.x, 0);
        expect(f.y, 0);
      },
    );
  });
}
