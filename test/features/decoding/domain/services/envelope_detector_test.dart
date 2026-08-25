import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/envelope_detector.dart';

void main() {
  group('EnvelopeDetector', () {
    test('rises quickly on step input (fast attack)', () {
      final detector = EnvelopeDetector(
        attackMs: 2,
        releaseMs: 50,
      );

      // Feed a constant high value for several hops
      var env = 0.0;
      for (var i = 0; i < 10; i++) {
        env = detector.process(100, hopMs: 10);
      }

      // After 100ms with 2ms attack, should be very close
      expect(env, greaterThan(95));
    });

    test('falls slowly on step down (slow release)', () {
      final detector = EnvelopeDetector(
        attackMs: 2,
        releaseMs: 50,
      );

      // Rise first
      for (var i = 0; i < 10; i++) {
        detector.process(100, hopMs: 10);
      }

      // Drop to zero
      var env = 0.0;
      for (var i = 0; i < 5; i++) {
        env = detector.process(0, hopMs: 10);
      }

      // After 50ms with 50ms release, should be roughly at
      // 1/e ≈ 37% of original
      expect(env, greaterThan(30));
      expect(env, lessThan(60));
    });

    test('tracks varying input', () {
      final detector = EnvelopeDetector(
        attackMs: 1,
        releaseMs: 20,
      );

      detector.process(50, hopMs: 5);
      final v1 = detector.value;
      expect(v1, greaterThan(0));

      detector.process(80, hopMs: 5);
      final v2 = detector.value;
      expect(v2, greaterThan(v1));

      detector.process(30, hopMs: 5);
      final v3 = detector.value;
      expect(v3, lessThan(v2));
      expect(v3, greaterThan(25));
    });

    test('reset sets value to zero', () {
      final detector = EnvelopeDetector();

      for (var i = 0; i < 10; i++) {
        detector.process(100, hopMs: 10);
      }
      expect(detector.value, greaterThan(0));

      detector.reset();
      expect(detector.value, 0);
    });

    test('asserts on non-positive time constants', () {
      expect(
        () => EnvelopeDetector(attackMs: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EnvelopeDetector(releaseMs: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
