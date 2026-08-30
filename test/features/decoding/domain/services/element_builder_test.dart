import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';

void main() {
  group('ElementBuilder', () {
    late List<DecodedElement> out;
    ElementBuilder make({int minElementMs = 10, double glitchRatio = 0.25}) {
      out = [];
      return ElementBuilder(
        onElement: out.add,
        minElementMs: minElementMs,
        glitchRatio: glitchRatio,
      );
    }

    test('emits nothing before the second transition', () {
      make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100);
      expect(out, isEmpty);
    });

    test('emits elements one transition late', () {
      final b = make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100)
        ..transition(nowOn: false, timeMs: 300);
      expect(out, hasLength(1));
      expect(out.single.isOn, isFalse);
      expect(out.single.durationMs, 100);

      b
        ..flush()
        ..flush();
      expect(out, hasLength(2));
      expect(out.last.isOn, isTrue);
      expect(out.last.durationMs, 200);
    });

    test('flush is idempotent', () {
      final b = make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100)
        ..flush()
        ..flush();
      expect(out, hasLength(1));
      b.flush();
      expect(out, hasLength(1));
    });

    test('merges a glitch into its neighbours instead of splitting', () {
      // ON 100 / off 5 / ON 100 should read as a single 205 ms mark,
      // not as two marks — dropping the gap would keep the split.
      make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 50)
        ..transition(nowOn: false, timeMs: 150)
        ..transition(nowOn: true, timeMs: 155)
        ..transition(nowOn: false, timeMs: 255)
        ..flush();

      final marks = out.where((e) => e.isOn).toList();
      expect(marks, hasLength(1));
      expect(marks.single.durationMs, 205);
    });

    test('keeps segments at or above the threshold', () {
      make(minElementMs: 10)
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 50)
        ..transition(nowOn: false, timeMs: 150)
        ..transition(nowOn: true, timeMs: 175)
        ..transition(nowOn: false, timeMs: 275)
        ..flush();

      expect(out.where((e) => e.isOn), hasLength(2));
    });

    test('glitch threshold scales with the observed element rate', () {
      final b = make(minElementMs: 5, glitchRatio: 0.25);
      // Before any history the floor applies.
      expect(b.glitchThresholdMs, 5);
      expect(b.currentUnitMs, isNull);

      // Feed eight 60 ms marks separated by 60 ms gaps.
      var t = 0.0;
      b.transition(nowOn: false, timeMs: t);
      for (var i = 0; i < 8; i++) {
        b
          ..transition(nowOn: true, timeMs: t += 60)
          ..transition(nowOn: false, timeMs: t += 60);
      }
      expect(b.currentUnitMs, 60);
      // A 60 ms dit at ratio 0.25 gives a 15 ms threshold.
      expect(b.glitchThresholdMs, 15);
    });

    test('ignores a transition to the state it is already in', () {
      make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: false, timeMs: 50)
        ..transition(nowOn: true, timeMs: 100)
        ..transition(nowOn: true, timeMs: 150)
        ..transition(nowOn: false, timeMs: 200)
        ..flush();
      expect(out.map((e) => e.durationMs), [100, 100]);
    });

    test('reset clears history and pending state', () {
      final b = make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100)
        ..reset()
        ..flush();
      expect(out, isEmpty);
      expect(b.isOn, isFalse);
    });
  });
}
