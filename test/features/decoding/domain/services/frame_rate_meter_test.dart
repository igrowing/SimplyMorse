import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/frame_rate_meter.dart';

void main() {
  group('FrameRateMeter', () {
    test('reports 0 before any frames', () {
      final meter = FrameRateMeter();
      expect(meter.fps, 0);
    });

    test('reports 0 with a single frame', () {
      final meter = FrameRateMeter();
      meter.add(1000);
      expect(meter.fps, 0);
    });

    test('measures a steady 30 fps stream', () {
      final meter = FrameRateMeter();
      for (var i = 0; i < 30; i++) {
        meter.add(i * 33);
      }
      expect(meter.fps, closeTo(30.3, 0.1));
    });

    test('measures a 60 fps stream', () {
      final meter = FrameRateMeter();
      for (var i = 0; i < 60; i++) {
        meter.add(i * 16);
      }
      expect(meter.fps, closeTo(62.5, 0.1));
    });

    test('detects a mid-stream rate change within the window', () {
      final meter = FrameRateMeter(window: 10);
      // Start at 60 fps.
      for (var i = 0; i < 20; i++) {
        meter.add(i * 16);
      }
      expect(meter.fps, closeTo(62.5, 0.1));

      // Device throttles to 30 fps.
      var t = 20 * 16;
      for (var i = 0; i < 10; i++) {
        t += 33;
        meter.add(t);
      }
      expect(meter.fps, closeTo(30.3, 1.0));
    });

    test('ignores out-of-order timestamps', () {
      final meter = FrameRateMeter();
      meter.add(1000);
      meter.add(1033);
      meter.add(1020); // clock hiccup — must not drag the average
      meter.add(1066);
      expect(meter.fps, closeTo(30.3, 0.1));
    });

    test('reset clears the measurement', () {
      final meter = FrameRateMeter();
      for (var i = 0; i < 10; i++) {
        meter.add(i * 33);
      }
      meter.reset();
      expect(meter.fps, 0);
    });
  });
}
