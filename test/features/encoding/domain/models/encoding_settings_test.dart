import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';

void main() {
  group('EncodingSettings timing', () {
    test('ditMs follows PARIS standard: 1200 / WPM', () {
      const settings7wpm = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 7,
        toneHz: 700,
      );
      // 1200 / 7 ≈ 171.4286
      expect(settings7wpm.ditMs, closeTo(171.4286, 0.001));

      const settings1wpm = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 1,
        toneHz: 700,
      );
      expect(settings1wpm.ditMs, 1200);

      const settings20wpm = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 20,
        toneHz: 700,
      );
      expect(settings20wpm.ditMs, 60);
    });

    test('dahMs equals 3 * ditMs', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      expect(settings.dahMs, 3 * settings.ditMs);
      // 3 * (1200/10) = 360
      expect(settings.dahMs, 360);
    });

    test('intraGapMs equals ditMs', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 12,
        toneHz: 700,
      );
      expect(settings.intraGapMs, settings.ditMs);
      // 1200 / 12 = 100
      expect(settings.intraGapMs, 100);
    });

    test('charGapMs equals 3 * ditMs', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 12,
        toneHz: 700,
      );
      expect(settings.charGapMs, 3 * settings.ditMs);
      expect(settings.charGapMs, 300);
    });

    test('wordGapMs equals 7 * ditMs', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 12,
        toneHz: 700,
      );
      expect(settings.wordGapMs, 7 * settings.ditMs);
      expect(settings.wordGapMs, 700);
    });

    test('all timing ratios are correct at 7 WPM', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 7,
        toneHz: 700,
      );
      final dit = settings.ditMs;

      expect(settings.dahMs, closeTo(3 * dit, 0.001));
      expect(settings.intraGapMs, closeTo(dit, 0.001));
      expect(settings.charGapMs, closeTo(3 * dit, 0.001));
      expect(settings.wordGapMs, closeTo(7 * dit, 0.001));
    });

    test('higher WPM produces shorter durations', () {
      const slow = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 5,
        toneHz: 700,
      );
      const fast = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 30,
        toneHz: 700,
      );

      expect(fast.ditMs, lessThan(slow.ditMs));
      expect(fast.dahMs, lessThan(slow.dahMs));
      expect(fast.charGapMs, lessThan(slow.charGapMs));
      expect(fast.wordGapMs, lessThan(slow.wordGapMs));
    });
  });

  group('EncodingSettings.copyWith', () {
    test('preserves unchanged values', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith();

      expect(copy.mode, original.mode);
      expect(copy.speedWpm, original.speedWpm);
      expect(copy.toneHz, original.toneHz);
    });

    test('overrides mode only', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(mode: EncodingMode.both);

      expect(copy.mode, EncodingMode.both);
      expect(copy.speedWpm, original.speedWpm);
      expect(copy.toneHz, original.toneHz);
    });

    test('overrides speedWpm only', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(speedWpm: 25);

      expect(copy.mode, original.mode);
      expect(copy.speedWpm, 25);
      expect(copy.toneHz, original.toneHz);
    });

    test('overrides toneHz only', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(toneHz: 850);

      expect(copy.mode, original.mode);
      expect(copy.speedWpm, original.speedWpm);
      expect(copy.toneHz, 850);
    });

    test('overrides all fields', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(
        mode: EncodingMode.flash,
        speedWpm: 15,
        toneHz: 500,
      );

      expect(copy.mode, EncodingMode.flash);
      expect(copy.speedWpm, 15);
      expect(copy.toneHz, 500);
    });
  });

  group('EncodingSettings equality', () {
    test('identical values are equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      const b = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different mode is not equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      const b = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
      );

      expect(a, isNot(equals(b)));
    });

    test('different speedWpm is not equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      const b = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 11,
        toneHz: 700,
      );

      expect(a, isNot(equals(b)));
    });

    test('different toneHz is not equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      const b = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 701,
      );

      expect(a, isNot(equals(b)));
    });
  });
}
