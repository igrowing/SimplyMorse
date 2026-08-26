import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';

void main() {
  late MorseEncoder encoder;
  late EncodingSettings settings;

  setUp(() {
    encoder = MorseEncoder();
    settings = const EncodingSettings(
      mode: EncodingMode.sound,
      speedWpm: 7,
      toneHz: 700,
    );
  });

  group('MorseEncoder.encode', () {
    test('encodes simple text "SOS" into three symbols', () {
      final symbols = encoder.encode('SOS', settings);

      expect(symbols, hasLength(3));
      expect(symbols[0].character, 'S');
      expect(symbols[0].morseCode, '...');
      expect(symbols[1].character, 'O');
      expect(symbols[1].morseCode, '---');
      expect(symbols[2].character, 'S');
      expect(symbols[2].morseCode, '...');
    });

    test('encodes word gap as empty morseCode', () {
      final symbols = encoder.encode('HI THERE', settings);

      final spaceSymbol = symbols.firstWhere(
        (s) => s.character == ' ',
      );
      expect(spaceSymbol.morseCode, isEmpty);
      expect(spaceSymbol.isWordGap, isTrue);
    });

    test('skips unencodable characters', () {
      final symbols = encoder.encode('A#B', settings);

      expect(symbols, hasLength(2));
      expect(symbols[0].character, 'A');
      expect(symbols[1].character, 'B');
    });

    test('returns empty list for empty text', () {
      final symbols = encoder.encode('', settings);
      expect(symbols, isEmpty);
    });

    test('returns empty list when all characters are '
        'unencodable', () {
      final symbols = encoder.encode('###', settings);
      expect(symbols, isEmpty);
    });

    test('computes correct dit duration at 7 WPM', () {
      // dit = 1200 / 7 ≈ 171.43 ms
      expect(settings.ditMs, closeTo(171.43, 0.5));
    });

    test('computes correct dah duration', () {
      // dah = 3 * dit
      expect(settings.dahMs, closeTo(3 * 1200 / 7, 0.5));
    });

    test('symbol duration for "E" equals one dit', () {
      final symbols = encoder.encode('E', settings);

      expect(symbols, hasLength(1));
      expect(symbols[0].morseCode, '.');
      expect(symbols[0].durationMs, closeTo(settings.ditMs, 0.01));
    });

    test('symbol duration for "T" equals one dah', () {
      final symbols = encoder.encode('T', settings);

      expect(symbols, hasLength(1));
      expect(symbols[0].morseCode, '-');
      expect(symbols[0].durationMs, closeTo(settings.dahMs, 0.01));
    });

    test('symbol duration for "A" (.−) equals dit + gap + '
        'dah', () {
      final symbols = encoder.encode('A', settings);

      final expected = settings.ditMs + settings.intraGapMs + settings.dahMs;
      expect(symbols[0].durationMs, closeTo(expected, 0.01));
    });

    test('start times are sequential', () {
      final symbols = encoder.encode('ABC', settings);

      for (var i = 1; i < symbols.length; i++) {
        expect(
          symbols[i].startMs,
          greaterThan(symbols[i - 1].startMs),
        );
      }
    });

    test('word gap duration equals 7 dits', () {
      final symbols = encoder.encode('A B', settings);

      final space = symbols.firstWhere(
        (s) => s.isWordGap,
      );
      expect(
        space.durationMs,
        closeTo(settings.wordGapMs, 0.01),
      );
    });
  });

  group('MorseEncoder.buildTimeline', () {
    test('builds timeline with correct on/off events for '
        '"E"', () {
      final symbols = encoder.encode('E', settings);
      final events = encoder.buildTimeline(symbols, settings);

      // E = "." → one tone event (on) for dit duration
      expect(events, hasLength(1));
      expect(events[0].isOn, isTrue);
      expect(events[0].durationMs, settings.ditMs.round());
      expect(events[0].charIndex, 0);
    });

    test('builds timeline with intra-gap for "A" (.−)', () {
      final symbols = encoder.encode('A', settings);
      final events = encoder.buildTimeline(symbols, settings);

      // Events: on(dit), off(intra-gap), on(dah)
      expect(events, hasLength(3));
      expect(events[0].isOn, isTrue);
      expect(events[0].durationMs, settings.ditMs.round());
      expect(events[1].isOn, isFalse);
      expect(events[1].durationMs, settings.intraGapMs.round());
      expect(events[2].isOn, isTrue);
      expect(events[2].durationMs, settings.dahMs.round());
    });

    test('builds timeline with inter-character gap for '
        '"AB"', () {
      final symbols = encoder.encode('AB', settings);
      final events = encoder.buildTimeline(symbols, settings);

      // Find the inter-character gap (off event with charIndex 0
      // after the last on event of A)
      final gapEvents = events.where(
        (e) => !e.isOn && e.charIndex == 0,
      );
      // A has no internal gaps after its last element, so the
      // inter-char gap should be the last off event for A
      final lastGap = gapEvents.last;
      expect(lastGap.durationMs, settings.charGapMs.round());
    });

    test('word gap produces a single off event', () {
      final symbols = encoder.encode('A B', settings);
      final events = encoder.buildTimeline(symbols, settings);

      // Find the word gap event (off event with charIndex of
      // the space symbol)
      final spaceIndex = symbols.indexWhere(
        (s) => s.isWordGap,
      );
      final wordGapEvents = events.where(
        (e) => e.charIndex == spaceIndex && !e.isOn,
      );
      expect(wordGapEvents, hasLength(1));
      expect(
        wordGapEvents.first.durationMs,
        settings.wordGapMs.round(),
      );
    });

    test('all on events have positive duration', () {
      final symbols = encoder.encode('HELLO WORLD', settings);
      final events = encoder.buildTimeline(symbols, settings);

      for (final event in events) {
        if (event.isOn) {
          expect(event.durationMs, greaterThan(0));
        }
      }
    });

    test('all events reference valid char indices', () {
      final symbols = encoder.encode('SOS', settings);
      final events = encoder.buildTimeline(symbols, settings);

      for (final event in events) {
        expect(event.charIndex, greaterThanOrEqualTo(0));
        expect(event.charIndex, lessThan(symbols.length));
      }
    });

    test('timeline for empty input is empty', () {
      final symbols = encoder.encode('', settings);
      final events = encoder.buildTimeline(symbols, settings);
      expect(events, isEmpty);
    });
  });
}
