import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';

void main() {
  group('EncodingSettings timing', () {
    test('ditMs follows PARIS standard: 1200 / WPM', () {
      const settings7wpm = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 7,
        toneHz: 700,
      );
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
      expect(settings.dahMs, 360);
    });

    test('intraGapMs equals ditMs', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 12,
        toneHz: 700,
      );
      expect(settings.intraGapMs, settings.ditMs);
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

  group('EncodingSettings lightMethod', () {
    test('defaults to flashLed', () {
      const settings = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
      );
      expect(settings.lightMethod, LightMethod.flashLed);
    });

    test('needsTorch is true for flash mode with flashLed', () {
      const settings = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.flashLed,
      );
      expect(settings.needsTorch, isTrue);
      expect(settings.needsDisplay, isFalse);
    });

    test('needsDisplay is true for flash mode with display', () {
      const settings = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.display,
      );
      expect(settings.needsTorch, isFalse);
      expect(settings.needsDisplay, isTrue);
    });

    test('both torch and display for both method', () {
      const settings = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.both,
      );
      expect(settings.needsTorch, isTrue);
      expect(settings.needsDisplay, isTrue);
    });

    test('sound mode does not need torch or display', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.display,
      );
      expect(settings.needsTorch, isFalse);
      expect(settings.needsDisplay, isFalse);
    });

    test('needsAudio is true for sound and both modes', () {
      const sound = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      const both = EncodingSettings(
        mode: EncodingMode.both,
        speedWpm: 10,
        toneHz: 700,
      );
      const flash = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
      );

      expect(sound.needsAudio, isTrue);
      expect(both.needsAudio, isTrue);
      expect(flash.needsAudio, isFalse);
    });
  });

  group('EncodingSettings initialDelaySec', () {
    test('defaults to 1.0 second', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      expect(settings.initialDelaySec, 1.0);
    });

    test('can be set to zero', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
        initialDelaySec: 0.0,
      );
      expect(settings.initialDelaySec, 0.0);
    });

    test('can be set to maximum', () {
      const settings = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
        initialDelaySec: 20.0,
      );
      expect(settings.initialDelaySec, 20.0);
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
      expect(copy.lightMethod, original.lightMethod);
      expect(copy.initialDelaySec, original.initialDelaySec);
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

    test('overrides lightMethod only', () {
      const original = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(lightMethod: LightMethod.display);

      expect(copy.lightMethod, LightMethod.display);
      expect(copy.mode, original.mode);
      expect(copy.speedWpm, original.speedWpm);
    });

    test('overrides initialDelaySec only', () {
      const original = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
      );
      final copy = original.copyWith(initialDelaySec: 10.0);

      expect(copy.initialDelaySec, 10.0);
      expect(copy.mode, original.mode);
      expect(copy.speedWpm, original.speedWpm);
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
        lightMethod: LightMethod.display,
        initialDelaySec: 5.0,
      );

      expect(copy.mode, EncodingMode.flash);
      expect(copy.speedWpm, 15);
      expect(copy.toneHz, 500);
      expect(copy.lightMethod, LightMethod.display);
      expect(copy.initialDelaySec, 5.0);
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

    test('different lightMethod is not equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.flashLed,
      );
      const b = EncodingSettings(
        mode: EncodingMode.flash,
        speedWpm: 10,
        toneHz: 700,
        lightMethod: LightMethod.display,
      );

      expect(a, isNot(equals(b)));
    });

    test('different initialDelaySec is not equal', () {
      const a = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
        initialDelaySec: 1.0,
      );
      const b = EncodingSettings(
        mode: EncodingMode.sound,
        speedWpm: 10,
        toneHz: 700,
        initialDelaySec: 5.0,
      );

      expect(a, isNot(equals(b)));
    });
  });
}
