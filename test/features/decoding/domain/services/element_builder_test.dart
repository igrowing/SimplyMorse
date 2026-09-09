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

    test('tick releases the pending element once it cannot be merged', () {
      final b = make(minElementMs: 5, glitchRatio: 0.25);
      // Establish a ~100 ms unit so the glitch threshold is trusted
      // (tick is inert until currentUnitMs is known).
      var t = 0.0;
      b.transition(nowOn: false, timeMs: t);
      for (var i = 0; i < 8; i++) {
        b
          ..transition(nowOn: true, timeMs: t += 100)
          ..transition(nowOn: false, timeMs: t += 100);
      }
      expect(b.currentUnitMs, 100);

      // One more mark, then an OFF segment. After these two
      // transitions the ON mark is the pending element.
      b
        ..transition(nowOn: true, timeMs: t += 100)
        ..transition(nowOn: false, timeMs: t += 100);
      final n = out.length;
      expect(b.isOn, isFalse);

      // Still within the glitch window (100 * 0.25 = 25 ms) — nothing.
      b.tick(t + 20);
      expect(out, hasLength(n));

      // OFF has outlasted the glitch threshold — release the mark.
      b.tick(t + 40);
      expect(out, hasLength(n + 1));
      expect(out.last.isOn, isTrue);
      expect(out.last.durationMs, 100);

      // Idempotent until the next transition.
      b.tick(t + 500);
      expect(out, hasLength(n + 1));
    });

    test('tick is inert before the element rate is known', () {
      final b = make()
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100)
        ..transition(nowOn: false, timeMs: 200);
      expect(b.currentUnitMs, isNull);
      final n = out.length;
      b.tick(100000);
      expect(out, hasLength(n));
    });

    test('onMerge fires when a glitch is folded back', () {
      final merges = <Map<String, Object>>[];
      out = [];
      final b = ElementBuilder(
        onElement: out.add,
        onMerge: ({required absorbedMs, required intoOn}) {
          merges.add({'absorbedMs': absorbedMs, 'intoOn': intoOn});
        },
        minElementMs: 10,
        glitchRatio: 0.25,
      );

      // Build enough mark history for a dit estimate (6 marks of
      // 100 ms → unit 100 ms → glitch threshold 25 ms). Elements
      // emit one transition late, so 7 cycles are needed for the
      // 6th mark to reach the history.
      var t = 0.0;
      for (var i = 0; i < 7; i++) {
        b
          ..transition(nowOn: true, timeMs: t)
          ..transition(nowOn: false, timeMs: t + 100);
        t += 160; // 100 ms mark + 60 ms gap
      }
      expect(b.currentUnitMs, 100);
      expect(merges, isEmpty);

      // A 10 ms off-blip in the middle of a mark — well under
      // the 25 ms threshold — folds back into the pending ON
      // element, which is the segment the glitch interrupted.
      b
        ..transition(nowOn: true, timeMs: t)
        ..transition(nowOn: false, timeMs: t + 150)
        ..transition(nowOn: true, timeMs: t + 160)
        ..transition(nowOn: false, timeMs: t + 300);

      expect(merges, hasLength(1));
      expect(merges.single['absorbedMs'], 10);
      expect(merges.single['intoOn'], isTrue);
    });

    test('onMerge stays silent for segments at or above threshold', () {
      final merges = <Map<String, Object>>[];
      out = [];
      final b = ElementBuilder(
        onElement: out.add,
        onMerge: ({required absorbedMs, required intoOn}) {
          merges.add({'absorbedMs': absorbedMs, 'intoOn': intoOn});
        },
        minElementMs: 10,
        glitchRatio: 0.25,
      );

      b
        ..transition(nowOn: false, timeMs: 0)
        ..transition(nowOn: true, timeMs: 100)
        ..transition(nowOn: false, timeMs: 200)
        ..transition(nowOn: true, timeMs: 300)
        ..flush();

      expect(merges, isEmpty);
      expect(out, isNotEmpty);
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

    test('unit estimate survives a fragment storm', () {
      // Hardware 20 WPM capture: threshold chatter chopped dahs
      // into 20-45 ms fragments that dragged the old running
      // percentile from 60 ms down to 30 ms. The hardened
      // estimate must ignore them.
      final b = make(minElementMs: 5);
      var t = 0.0;
      b.transition(nowOn: false, timeMs: t);
      void mark(double d) {
        b
          ..transition(nowOn: true, timeMs: t += 150)
          ..transition(nowOn: false, timeMs: t += d);
      }

      // Bootstrap: eight healthy 100 ms marks.
      for (var i = 0; i < 8; i++) {
        mark(100);
      }
      expect(b.currentUnitMs, 100);

      // Storm: eight rounds of a chopped mark (30 ms) plus an
      // intact one (100 ms). The old percentile would read the
      // 25th percentile straight into the fragment cluster.
      for (var i = 0; i < 8; i++) {
        mark(30);
        mark(100);
      }
      expect(b.currentUnitMs, greaterThanOrEqualTo(80));
      expect(b.currentUnitMs, lessThanOrEqualTo(125));
    });

    test('unit estimate re-bootstraps after a genuine speed change', () {
      final b = make(minElementMs: 5);
      var t = 0.0;
      b.transition(nowOn: false, timeMs: t);
      void mark(double d) {
        b
          ..transition(nowOn: true, timeMs: t += 150)
          ..transition(nowOn: false, timeMs: t += d);
      }

      for (var i = 0; i < 8; i++) {
        mark(100);
      }
      expect(b.currentUnitMs, 100);

      // The operator speeds up: all marks now 60 ms — below the
      // 0.7x band edge. Once the 24-mark history window has fully
      // turned over, no in-band marks remain, so the estimate
      // re-bootstraps instead of holding a stale unit forever.
      for (var i = 0; i < 24; i++) {
        mark(60);
      }
      // The first re-bootstrap step is clamped to 0.65x the stale
      // unit (65 ms); the next converges onto the 60 ms cluster.
      mark(60);
      expect(b.currentUnitMs, greaterThanOrEqualTo(55));
      expect(b.currentUnitMs, lessThanOrEqualTo(81));
    });

    test('unit estimate moves at most 25% up per element', () {
      final b = make(minElementMs: 5);
      var t = 0.0;
      b.transition(nowOn: false, timeMs: t);
      void mark(double d) {
        b
          ..transition(nowOn: true, timeMs: t += 150)
          ..transition(nowOn: false, timeMs: t += d);
      }

      for (var i = 0; i < 8; i++) {
        mark(100);
      }
      // A jump of dah-scale marks cannot snap the estimate up:
      // each step is clamped to 1.25x the previous value.
      mark(220);
      expect(b.currentUnitMs, lessThanOrEqualTo(125));
    });
  });
}
