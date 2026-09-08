import 'package:flutter_test/flutter_test.dart';
import 'cer.dart';

void main() {
  group('editDistance', () {
    test('identical strings have distance 0', () {
      expect(editDistance('HELLO', 'HELLO'), 0);
    });

    test('empty strings', () {
      expect(editDistance('', ''), 0);
      expect(editDistance('ABC', ''), 3);
      expect(editDistance('', 'ABC'), 3);
    });

    test('single substitution', () {
      expect(editDistance('SELLO', 'HELLO'), 1);
    });

    test('insertion and deletion', () {
      expect(editDistance('HELO', 'HELLO'), 1);
      expect(editDistance('HELLLO', 'HELLO'), 1);
    });

    test('is symmetric', () {
      expect(editDistance('kitten', 'sitting'), 3);
      expect(editDistance('sitting', 'kitten'), 3);
    });
  });

  group('characterErrorRate', () {
    test('perfect decode is 0', () {
      expect(characterErrorRate('HELLO', 'HELLO'), 0);
    });

    test('one wrong char in five is 0.2', () {
      expect(characterErrorRate('SELLO', 'HELLO'), closeTo(0.2, 1e-9));
    });

    test('empty decode is 1.0', () {
      expect(characterErrorRate('', 'HELLO'), 1.0);
    });

    test('empty expectation', () {
      expect(characterErrorRate('', ''), 0);
      expect(characterErrorRate('X', ''), 1);
    });
  });
}
