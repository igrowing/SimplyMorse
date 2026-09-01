import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';

void main() {
  group('MorseCodeTable', () {
    test('lookup returns correct Morse for letters', () {
      expect(MorseCodeTable.lookup('A'), '.-');
      expect(MorseCodeTable.lookup('B'), '-...');
      expect(MorseCodeTable.lookup('S'), '...');
      expect(MorseCodeTable.lookup('O'), '---');
      expect(MorseCodeTable.lookup('Z'), '--..');
    });

    test('lookup is case-insensitive', () {
      expect(MorseCodeTable.lookup('a'), '.-');
      expect(MorseCodeTable.lookup('A'), '.-');
      expect(MorseCodeTable.lookup('s'), '...');
    });

    test('lookup returns correct Morse for numbers', () {
      expect(MorseCodeTable.lookup('0'), '-----');
      expect(MorseCodeTable.lookup('1'), '.----');
      expect(MorseCodeTable.lookup('9'), '----.');
    });

    test('lookup returns correct Morse for punctuation', () {
      expect(MorseCodeTable.lookup('.'), '.-.-.-');
      expect(MorseCodeTable.lookup(','), '--..--');
      expect(MorseCodeTable.lookup('?'), '..--..');
      expect(MorseCodeTable.lookup('@'), '.--.-.');
    });

    test('lookup returns empty string for space', () {
      expect(MorseCodeTable.lookup(' '), '');
    });

    test('lookup returns null for unencodable characters', () {
      expect(MorseCodeTable.lookup('#'), isNull);
      expect(MorseCodeTable.lookup('~'), isNull);
      expect(MorseCodeTable.lookup('`'), isNull);
    });

    test('canEncode returns true for encodable characters', () {
      expect(MorseCodeTable.canEncode('A'), isTrue);
      expect(MorseCodeTable.canEncode('5'), isTrue);
      expect(MorseCodeTable.canEncode(' '), isTrue);
      expect(MorseCodeTable.canEncode('.'), isTrue);
    });

    test('canEncode returns false for unencodable characters', () {
      expect(MorseCodeTable.canEncode('#'), isFalse);
      expect(MorseCodeTable.canEncode('~'), isFalse);
    });

    test('lookup encodes European characters', () {
      expect(MorseCodeTable.lookup('Ä'), '.-');
      expect(MorseCodeTable.lookup('Ö'), '---.');
      expect(MorseCodeTable.lookup('Ü'), '..--');
      expect(MorseCodeTable.lookup('É'), '..-..');
      expect(MorseCodeTable.lookup('Ç'), '-.-..');
      expect(MorseCodeTable.lookup('Ñ'), '--.--');
    });
  });

  group('MorseCodeTable.reverseLookup priority', () {
    test('decodes ASCII at default priority 3', () {
      expect(MorseCodeTable.reverseLookup('.-'), 'A');
      expect(MorseCodeTable.reverseLookup('...'), 'S');
      expect(MorseCodeTable.reverseLookup('---'), 'O');
      expect(MorseCodeTable.reverseLookup('-----'), '0');
      expect(MorseCodeTable.reverseLookup('--..--'), ',');
      expect(MorseCodeTable.reverseLookup('...---...'), 'SOS');
    });

    test('does NOT decode European chars at priority 3', () {
      // These codes should return null at default priority
      // because they are short codes that can be matched by
      // misclassified sequences.
      expect(MorseCodeTable.reverseLookup('..-..'), isNull); // É
      expect(MorseCodeTable.reverseLookup('-.-..'), isNull); // Ç
      expect(MorseCodeTable.reverseLookup('..--'), isNull); // Ü/Ð
      expect(MorseCodeTable.reverseLookup('---.'), isNull); // Ö
      expect(MorseCodeTable.reverseLookup('--.--'), isNull); // Ñ
    });

    test('decodes European chars at priority 4', () {
      expect(MorseCodeTable.reverseLookup('..-..', priority: 4), 'É');
      expect(MorseCodeTable.reverseLookup('-.-..', priority: 4), 'Ç');
      expect(MorseCodeTable.reverseLookup('---.', priority: 4), 'Ö');
      expect(MorseCodeTable.reverseLookup('--.--', priority: 4), 'Ñ');
    });

    test('ASCII takes precedence over European at priority 4', () {
      // Ä has the same code as A (.-). At priority 4, the ASCII
      // character should win because lower-priority sets are
      // built first and putIfAbsent prevents overwriting.
      expect(MorseCodeTable.reverseLookup('.-', priority: 4), 'A');
      expect(MorseCodeTable.reverseLookup('.-', priority: 4), isNot('Ä'));
    });

    test('priority 1 decodes letters only', () {
      expect(MorseCodeTable.reverseLookup('.-', priority: 1), 'A');
      expect(MorseCodeTable.reverseLookup('-----', priority: 1), isNull);
      expect(MorseCodeTable.reverseLookup('--..--', priority: 1), isNull);
    });

    test('priority 2 adds numbers', () {
      expect(MorseCodeTable.reverseLookup('.-', priority: 2), 'A');
      expect(MorseCodeTable.reverseLookup('-----', priority: 2), '0');
      expect(MorseCodeTable.reverseLookup('--..--', priority: 2), isNull);
    });

    test('priority 0 decodes nothing', () {
      expect(MorseCodeTable.reverseLookup('.-', priority: 0), isNull);
      expect(MorseCodeTable.reverseLookup('...', priority: 0), isNull);
    });

    test('clamps out-of-range priority', () {
      expect(MorseCodeTable.reverseLookup('.-', priority: 99), 'A');
      expect(MorseCodeTable.reverseLookup('..-..', priority: 99), 'É');
      expect(MorseCodeTable.reverseLookup('.-', priority: -1), isNull);
    });
  });
}
