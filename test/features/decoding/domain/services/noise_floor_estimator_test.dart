import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/noise_floor_estimator.dart';

void main() {
  group('NoiseFloorEstimator', () {
    test('returns zero when empty', () {
      final estimator = NoiseFloorEstimator();
      expect(estimator.noiseFloor, 0);
      expect(estimator.length, 0);
      expect(estimator.isReady, isFalse);
    });

    test('returns median of stored values', () {
      final estimator = NoiseFloorEstimator(windowSize: 10);

      estimator
        ..update(10)
        ..update(20)
        ..update(30);

      // Median of [10, 20, 30] = 20
      expect(estimator.noiseFloor, 20);
    });

    test('handles even number of values', () {
      final estimator = NoiseFloorEstimator(windowSize: 10);

      estimator
        ..update(10)
        ..update(20)
        ..update(30)
        ..update(40);

      // Median of [10, 20, 30, 40] = (20 + 30) / 2 = 25
      expect(estimator.noiseFloor, 25);
    });

    test('is ready after 5 updates', () {
      final estimator = NoiseFloorEstimator();

      for (var i = 0; i < 4; i++) {
        estimator.update(i.toDouble());
      }
      expect(estimator.isReady, isFalse);

      estimator.update(4);
      expect(estimator.isReady, isTrue);
    });

    test('trims to window size', () {
      final estimator = NoiseFloorEstimator(windowSize: 5);

      for (var i = 0; i < 10; i++) {
        estimator.update(i.toDouble());
      }

      expect(estimator.length, 5);
      // Last 5 values: [5, 6, 7, 8, 9], median = 7
      expect(estimator.noiseFloor, 7);
    });

    test('reset clears all values', () {
      final estimator = NoiseFloorEstimator();

      for (var i = 0; i < 10; i++) {
        estimator.update(i.toDouble());
      }
      expect(estimator.length, 10);

      estimator.reset();
      expect(estimator.length, 0);
      expect(estimator.noiseFloor, 0);
      expect(estimator.isReady, isFalse);
    });

    test('handles negative values', () {
      final estimator = NoiseFloorEstimator();

      estimator
        ..update(-10)
        ..update(0)
        ..update(10);

      expect(estimator.noiseFloor, 0);
    });
  });
}
