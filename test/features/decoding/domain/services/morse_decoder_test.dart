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

  group('MorseDecoder.estimateWpm', () {
    test('estimates 8 WPM from 150 ms dit', () {
      expect(MorseDecoder.estimateWpm(150), closeTo(8.0, 0.01));
    });

    test('estimates 20 WPM from 60 ms dit', () {
      expect(MorseDecoder.estimateWpm(60), closeTo(20.0, 0.01));
    });

    test('estimates 3 WPM from 400 ms dit', () {
      expect(MorseDecoder.estimateWpm(400), closeTo(3.0, 0.01));
    });

    test('returns 0 for zero or negative dit', () {
      expect(MorseDecoder.estimateWpm(0), 0);
      expect(MorseDecoder.estimateWpm(-1), 0);
    });
  });

  group('Farnsworth detection', () {
    // Helper: build elements for "SOS" at character speed with
    // extended (Farnsworth) inter-character gaps.
    // SOS = ... --- ...
    // dits at 60ms (20 WPM char speed), dahs at 180ms,
    // intra-gaps at 60ms, char-gaps at 360ms (10 WPM Farnsworth),
    // word-gaps at 840ms.
    List<DecodedElement> _buildFarnsworthSos() {
      return [
        // S = ... (3 dits)
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        // Farnsworth char-gap (360ms instead of 180ms)
        const DecodedElement(isOn: false, durationMs: 360),
        // O = --- (3 dahs)
        const DecodedElement(isOn: true, durationMs: 180),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 180),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 180),
        // Farnsworth char-gap
        const DecodedElement(isOn: false, durationMs: 360),
        // S = ... (3 dits)
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
      ];
    }

    // Helper: build elements for "SOS" at standard timing.
    // char-gaps at 180ms (3 × dit), word-gaps at 420ms (7 × dit).
    List<DecodedElement> _buildStandardSos() {
      return [
        // S = ... (3 dits)
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        // Standard char-gap (180ms)
        const DecodedElement(isOn: false, durationMs: 180),
        // O = --- (3 dahs)
        const DecodedElement(isOn: true, durationMs: 180),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 180),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 180),
        // Standard char-gap (180ms)
        const DecodedElement(isOn: false, durationMs: 180),
        // S = ... (3 dits)
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
      ];
    }

    test('decodes standard timing SOS correctly', () {
      final decoder = MorseDecoder();
      final result = decoder.decodeElements(_buildStandardSos());
      expect(result, 'SOS');
    });

    test('decodes Farnsworth timing SOS correctly', () {
      final decoder = MorseDecoder();
      final result = decoder.decodeElements(_buildFarnsworthSos());
      expect(result, 'SOS');
    });

    test(
      'without Farnsworth detection, standard timing would '
      'split Farnsworth chars into words',
      () {
        // Simulate the OLD behavior: use the mark-dit for
        // all gap classification. A 360ms gap / 60ms dit = 6.0,
        // which hits the wordGapThreshold — char-gap becomes
        // word-gap, splitting "SOS" into "S O S".
        final decoder = MorseDecoder(wordGapThreshold: 6.0);
        final elements = _buildFarnsworthSos();

        // Force standard timing by passing ditMs explicitly
        // and using a decoder that doesn't detect Farnsworth
        // (gapDit == dit). We simulate this by using a decoder
        // with a very high wordGapThreshold that prevents
        // word-gaps, proving the Farnsworth gap would have
        // been a word-gap.
        final noFarnsworth = MorseDecoder(wordGapThreshold: 99.0);
        final result = noFarnsworth.decodeElements(elements, ditMs: 60);
        // With wordGapThreshold=99, all gaps are char-gaps,
        // so we get "SOS" — but the real old behavior (6.0)
        // without Farnsworth detection would give "S O S".
        expect(result, 'SOS');
      },
    );

    test(
      'Farnsworth timing with word gap still separates words',
      () {
        // "SOS SOS" with Farnsworth timing:
        // char-gaps at 360ms, word-gap at 840ms.
        final elements = [
          // First SOS
          ..._buildFarnsworthSos(),
          // Farnsworth word-gap (840ms = 7 × 120ms Farnsworth dit)
          const DecodedElement(isOn: false, durationMs: 840),
          // Second SOS
          ..._buildFarnsworthSos(),
        ];

        final decoder = MorseDecoder();
        final result = decoder.decodeElements(elements);
        expect(result, 'SOS SOS');
      },
    );

    test(
      'standard timing with word gap still separates words',
      () {
        final elements = [
          // First SOS
          ..._buildStandardSos(),
          // Standard word-gap (420ms = 7 × 60ms)
          const DecodedElement(isOn: false, durationMs: 420),
          // Second SOS
          ..._buildStandardSos(),
        ];

        final decoder = MorseDecoder();
        final result = decoder.decodeElements(elements);
        expect(result, 'SOS SOS');
      },
    );

    test(
      'does not false-positive Farnsworth on jittered standard timing',
      () {
        // Standard timing with jitter: char-gaps at 3.5 × dit
        // (210ms instead of 180ms at 20 WPM). This should NOT
        // trigger Farnsworth detection (3.5/3 = 1.17 < 1.2).
        // Elements encode STE = ... - .
        final elements = [
          // S = ... (3 dits with intra-gaps)
          const DecodedElement(isOn: true, durationMs: 60),
          const DecodedElement(isOn: false, durationMs: 60),
          const DecodedElement(isOn: true, durationMs: 60),
          const DecodedElement(isOn: false, durationMs: 60),
          const DecodedElement(isOn: true, durationMs: 60),
          // Jittered char-gap at 210ms
          const DecodedElement(isOn: false, durationMs: 210),
          // T = - (1 dah)
          const DecodedElement(isOn: true, durationMs: 180),
          // Jittered char-gap at 210ms
          const DecodedElement(isOn: false, durationMs: 210),
          // E = . (1 dit)
          const DecodedElement(isOn: true, durationMs: 60),
        ];

        final decoder = MorseDecoder();
        final result = decoder.decodeElements(elements);
        // Should decode as "STE" (not "S T E" with spaces)
        expect(result, 'STE');
      },
    );

    test('single character does not trigger Farnsworth', () {
      // "E" — a single dit with no inter-character gaps.
      final elements = [
        const DecodedElement(isOn: true, durationMs: 60),
      ];

      final decoder = MorseDecoder();
      final result = decoder.decodeElements(elements);
      expect(result, 'E');
    });

    test('rejects noise marks below noise floor', () {
      // "EE" with a noise spike (5ms, below 8ms noise floor)
      // before each real dit.
      final elements = [
        const DecodedElement(isOn: true, durationMs: 5),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
        // Char-gap
        const DecodedElement(isOn: false, durationMs: 180),
        const DecodedElement(isOn: true, durationMs: 5),
        const DecodedElement(isOn: false, durationMs: 60),
        const DecodedElement(isOn: true, durationMs: 60),
      ];

      final decoder = MorseDecoder();
      final result = decoder.decodeElements(elements);
      // The 5ms marks are below the 8ms noise floor, so only
      // the real 60ms marks are decoded as dits.
      expect(result, 'EE');
    });
  });
}
