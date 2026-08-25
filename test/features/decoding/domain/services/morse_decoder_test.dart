import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';

void main() {
  late MorseDecoder decoder;

  setUp(() {
    decoder = MorseDecoder();
  });

  group('MorseDecoder.decodeSymbol', () {
    test('decodes single-letter Morse codes', () {
      expect(decoder.decodeSymbol('.-'), 'A');
      expect(decoder.decodeSymbol('-...'), 'B');
      expect(decoder.decodeSymbol('...'), 'S');
      expect(decoder.decodeSymbol('---'), 'O');
      expect(decoder.decodeSymbol('-'), 'T');
      expect(decoder.decodeSymbol('.'), 'E');
    });

    test('decodes number Morse codes', () {
      expect(decoder.decodeSymbol('-----'), '0');
      expect(decoder.decodeSymbol('.----'), '1');
      expect(decoder.decodeSymbol('----.'), '9');
    });

    test('decodes punctuation Morse codes', () {
      expect(decoder.decodeSymbol('.-.-.-'), '.');
      expect(decoder.decodeSymbol('--..--'), ',');
      expect(decoder.decodeSymbol('.--.-.'), '@');
    });

    test('returns null for unrecognized codes', () {
      expect(decoder.decodeSymbol('........'), isNull);
      expect(decoder.decodeSymbol('--.--.--'), isNull);
      expect(decoder.decodeSymbol(''), isNull);
    });
  });

  group('MorseCodeTable.reverseLookup', () {
    test('is consistent with forward lookup', () {
      // For every encodable character, reverseLookup(lookup(c))
      // should return the character.
      const chars = [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
        'Z',
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '.',
        ',',
        '?',
        '!',
      ];
      for (final ch in chars) {
        final morse = MorseCodeTable.lookup(ch);
        expect(morse, isNotNull);
        expect(MorseCodeTable.reverseLookup(morse!), ch);
      }
    });
  });

  group('MorseDecoder.decodeElements', () {
    // Helper: build elements for "SOS" at 7 WPM
    // dit = 1200/7 ≈ 171 ms
    // S = ... (3 dits + 2 intra-gaps)
    // O = --- (3 dahs + 2 intra-gaps)
    // char gap = 3 dits
    List<DecodedElement> _s(
      int ditMs,
    ) {
      final gap = ditMs;
      return [
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: gap),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: gap),
        DecodedElement(isOn: true, durationMs: ditMs),
      ];
    }

    List<DecodedElement> _o(int ditMs) {
      final dahMs = ditMs * 3;
      final gap = ditMs;
      return [
        DecodedElement(isOn: true, durationMs: dahMs),
        DecodedElement(isOn: false, durationMs: gap),
        DecodedElement(isOn: true, durationMs: dahMs),
        DecodedElement(isOn: false, durationMs: gap),
        DecodedElement(isOn: true, durationMs: dahMs),
      ];
    }

    test('decodes "SOS" with explicit ditMs', () {
      const ditMs = 171;
      final charGap = ditMs * 3;
      final elements = <DecodedElement>[
        ..._s(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._o(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._s(ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'SOS');
    });

    test('decodes "SOS" with auto-estimated ditMs', () {
      const ditMs = 200;
      final charGap = ditMs * 3;
      final elements = <DecodedElement>[
        ..._s(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._o(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._s(ditMs),
      ];

      final result = decoder.decodeElements(elements);
      expect(result, 'SOS');
    });

    test('decodes word gap as space', () {
      const ditMs = 100;
      final wordGap = ditMs * 7;
      final elements = <DecodedElement>[
        ..._s(ditMs),
        DecodedElement(isOn: false, durationMs: wordGap),
        ..._o(ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'S O');
    });

    test('decodes single character "E"', () {
      const ditMs = 150;
      final elements = <DecodedElement>[
        DecodedElement(isOn: true, durationMs: ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'E');
    });

    test('decodes single character "T"', () {
      const ditMs = 150;
      final dahMs = ditMs * 3;
      final elements = <DecodedElement>[
        DecodedElement(isOn: true, durationMs: dahMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'T');
    });

    test('returns empty string for empty input', () {
      expect(decoder.decodeElements([]), isEmpty);
    });

    test('returns empty string when no on-elements', () {
      final elements = <DecodedElement>[
        DecodedElement(isOn: false, durationMs: 500),
      ];
      expect(decoder.decodeElements(elements), isEmpty);
    });

    test('handles rapid WPM (short durations)', () {
      const ditMs = 40; // 30 WPM
      final charGap = ditMs * 3;
      final elements = <DecodedElement>[
        ..._s(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._o(ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'SO');
    });

    test('handles slow WPM (long durations)', () {
      const ditMs = 1200; // 1 WPM
      final charGap = ditMs * 3;
      final elements = <DecodedElement>[
        ..._s(ditMs),
        DecodedElement(isOn: false, durationMs: charGap),
        ..._o(ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'SO');
    });

    test('flushes trailing symbol without gap', () {
      const ditMs = 100;
      final elements = <DecodedElement>[
        ..._s(ditMs),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, 'S');
    });

    test('skips unrecognized morse codes', () {
      const ditMs = 100;
      // 8 dits — not a valid Morse symbol
      final elements = <DecodedElement>[
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        DecodedElement(isOn: false, durationMs: ditMs),
        DecodedElement(isOn: true, durationMs: ditMs),
        // char gap
        DecodedElement(isOn: false, durationMs: ditMs * 3),
      ];

      final result = decoder.decodeElements(
        elements,
        ditMs: ditMs.toDouble(),
      );
      expect(result, isEmpty);
    });
  });
}
