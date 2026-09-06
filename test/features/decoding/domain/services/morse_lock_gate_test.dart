import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

DecodedElement on_(int ms) => DecodedElement(isOn: true, durationMs: ms);
DecodedElement off(int ms) => DecodedElement(isOn: false, durationMs: ms);

void main() {
  group('MorseLockGate', () {
    test('does not emit anything before minElementsToLock accumulates', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(onElement: out.add);
      [on_(100), off(100), on_(100), off(100)].forEach(gate.add);
      expect(out, isEmpty);
      expect(gate.isLocked, isFalse);
    });

    test('locks and flushes the whole buffer on a clean slow pattern', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 8,
        minMarksToLock: 4,
      );
      // Marks at 200/600 ms (dit/dah) — a 200 ms unit, well above the
      // 120 ms fast/slow line, so the gate should actively fit-check
      // this.
      final clean = [
        on_(200),
        off(200),
        on_(600),
        off(200),
        on_(200),
        off(600),
        on_(200),
        off(200),
      ];
      clean.forEach(gate.add);
      expect(gate.isLocked, isTrue);
      expect(gate.isGating, isFalse);
      expect(out, clean);
    });

    test(
      'drops a leading run of junk before locking onto real slow timing',
      () {
        final out = <DecodedElement>[];
        final gate = MorseLockGate(
          onElement: out.add,
          minElementsToLock: 8,
          minMarksToLock: 4,
        );

        // Junk: durations bearing no small-integer relationship to a
        // consistent unit (mimics camera-settling / countdown flicker).
        final junk = [
          off(660),
          on_(3993),
          off(825),
          on_(1749),
          off(1683),
          on_(99),
          off(132),
          on_(66),
          off(1353),
          on_(2673),
          off(363),
        ];
        final real = [
          on_(300),
          off(300),
          on_(900),
          off(300),
          on_(300),
          off(900),
          on_(300),
          off(300),
          on_(300),
        ];

        [...junk, ...real].forEach(gate.add);
        gate.flush();

        expect(gate.isLocked, isTrue);
        // None of the junk should have reached the output.
        expect(out.any((e) => e.durationMs > 1000), isFalse);
        expect(out, containsAll(real));
      },
    );

    test('bypasses fast sending immediately instead of gating it', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(onElement: out.add);
      // 60 ms unit (20 WPM) — well below the 120 ms fast/slow line.
      // Include some quantization-style jitter that a strict fit
      // check would reject, to prove it is never applied here.
      final fast = [
        on_(66),
        off(60),
        on_(99),
        off(66),
        on_(60),
        off(165),
        on_(132),
        off(66),
        on_(198),
        off(66),
        on_(66),
        off(66),
      ];
      fast.forEach(gate.add);

      expect(gate.isLocked, isTrue);
      expect(gate.isGating, isFalse);
      // Bypassed: everything seen so far, including the jitter, comes
      // straight through with nothing dropped.
      expect(out, fast);

      // And continues to pass through untouched afterwards.
      out.clear();
      gate.add(on_(9999));
      expect(out, [on_(9999)]);
    });

    test('flush emits the buffer even if it never locked', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 8,
        minMarksToLock: 4,
      );
      // Slow enough to gate (unit candidates >= 120ms) but never
      // settles into a clean fit within the buffer.
      final erratic = [on_(200), off(3000), on_(9000), off(150), on_(4000)];
      erratic.forEach(gate.add);
      expect(out, isEmpty);
      gate.flush();
      expect(out, erratic);
    });

    test('a long pause does not count against fitting', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 6,
        minMarksToLock: 3,
      );
      final withWordGap = [
        on_(150),
        off(1000),
        on_(150),
        off(150),
        on_(150),
        off(450),
      ];
      withWordGap.forEach(gate.add);
      expect(gate.isLocked, isTrue);
      expect(out, withWordGap);
    });

    test('passes elements straight through once locked', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 4,
        minMarksToLock: 2,
      );
      [on_(200), off(200), on_(200), off(200)].forEach(gate.add);
      expect(gate.isLocked, isTrue);
      out.clear();

      gate.add(on_(9999)); // wildly inconsistent, but already locked
      expect(out, [on_(9999)]);
    });

    test('reset clears buffer, lock, and speed classification', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 4,
        minMarksToLock: 2,
      );
      [on_(200), off(200), on_(200), off(200)].forEach(gate.add);
      expect(gate.isLocked, isTrue);

      gate.reset();
      expect(gate.isLocked, isFalse);
      expect(gate.isGating, isFalse);

      out.clear();
      gate.add(on_(200));
      expect(out, isEmpty);
    });

    group('releaseOnSignalLoss', () {
      test('emits nothing when the buffer never fit Morse timing', () {
        // Regression: a field capture with nothing transmitting at all
        // locked three times on sensor noise. The gate correctly
        // refused each one, but signal loss then flushed the rejected
        // buffer downstream anyway and the app printed "UDEA " out of
        // an empty room.
        final out = <DecodedElement>[];
        final gate = MorseLockGate(
          onElement: out.add,
          minElementsToLock: 8,
          minMarksToLock: 4,
        );
        // Durations bearing no relation to any consistent unit.
        [
          on_(307),
          off(86),
          on_(60),
          off(319),
          on_(267),
          off(760),
          on_(539),
          off(2461),
          on_(238),
          off(1043),
        ].forEach(gate.add);

        gate.releaseOnSignalLoss();

        expect(gate.isLocked, isFalse);
        expect(out, isEmpty);
      });

      test('still emits a buffer that does fit', () {
        final out = <DecodedElement>[];
        final gate = MorseLockGate(
          onElement: out.add,
          minElementsToLock: 8,
          minMarksToLock: 4,
        );
        final clean = [
          on_(200),
          off(200),
          on_(600),
          off(200),
          on_(200),
          off(600),
          on_(200),
          off(200),
          on_(200),
          off(200),
          on_(600),
          off(200),
        ];
        clean.forEach(gate.add);
        gate.releaseOnSignalLoss();

        expect(out, isNotEmpty);
      });
    });

    test('does not destroy elements it slides past', () {
      // Regression: sliding used to drop the oldest element outright,
      // so a stream that only became fittable late lost everything
      // before that point. Measured on an 8 WPM field capture, 59 of
      // 70 genuine elements were destroyed before flush ever ran.
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 8,
        minMarksToLock: 4,
      );
      // A prefix that cannot fit, then clean 200/600 ms sending. The
      // prefix stays within the mark spread Morse allows, so it is
      // not junk — just unfittable — and must not vanish silently.
      final prefix = [
        on_(210),
        off(640),
        on_(220),
        off(210),
        on_(650),
        off(215),
        on_(205),
        off(660),
      ];
      final real = [
        on_(200),
        off(200),
        on_(600),
        off(200),
        on_(200),
        off(600),
        on_(200),
        off(200),
        on_(200),
        off(200),
        on_(600),
        off(200),
      ];
      [...prefix, ...real].forEach(gate.add);
      gate.flush();

      expect(out, containsAll(real));
    });

    test('fits a dah-heavy window, where the median mark is a dah', () {
      // Regression: the unit used to be the median of all marks, which
      // is only a dit when dits outnumber dahs. On an 8 WPM field
      // capture of "HELLO, WORLD!" the decoder saw 18 dahs to 8 dits,
      // so the unit came out 3x too large, every genuine dit scored as
      // an outlier, and a textbook-clean transmission was rejected.
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 8,
        minMarksToLock: 4,
      );
      final dahHeavy = [
        on_(600),
        off(200),
        on_(600),
        off(200),
        on_(600),
        off(200),
        on_(200),
        off(200),
        on_(600),
        off(200),
        on_(600),
        off(200),
      ];
      dahHeavy.forEach(gate.add);

      expect(gate.isLocked, isTrue);
      expect(out, containsAll(dahHeavy));
    });

    test('gives up after maxPatience and passes the rest through', () {
      final out = <DecodedElement>[];
      final gate = MorseLockGate(
        onElement: out.add,
        minElementsToLock: 8,
        minMarksToLock: 4,
        maxPatience: 5,
      );
      // Slow (unit candidates >= 120ms) but never fits cleanly.
      for (var i = 0; i < 30; i++) {
        gate
          ..add(on_(200 + i * 37))
          ..add(off(150 + i * 53));
      }
      expect(gate.isLocked, isTrue);
      expect(out, isNotEmpty);
    });
  });
}
