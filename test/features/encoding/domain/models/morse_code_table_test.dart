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
  });
}
