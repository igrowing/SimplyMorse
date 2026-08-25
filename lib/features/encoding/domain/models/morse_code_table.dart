/// International Morse Code lookup table.
///
/// Maps characters to their dot/dash representation.
class MorseCodeTable {
  MorseCodeTable._();

  static const Map<String, String> _table = {
    // Letters
    'A': '.-', 'B': '-...', 'C': '-.-.', 'D': '-..', 'E': '.',
    'F': '..-.', 'G': '--.', 'H': '....', 'I': '..', 'J': '.---',
    'K': '-.-', 'L': '.-..', 'M': '--', 'N': '-.', 'O': '---',
    'P': '.--.', 'Q': '--.-', 'R': '.-.', 'S': '...', 'T': '-',
    'U': '..-', 'V': '...-', 'W': '.--', 'X': '-..-', 'Y': '-.--',
    'Z': '--..',
    // Numbers
    '0': '-----', '1': '.----', '2': '..---', '3': '...--',
    '4': '....-', '5': '.....', '6': '-....', '7': '--...',
    '8': '---..', '9': '----.',
    // Punctuation
    '.': '.-.-.-', ',': '--..--', '?': '..--..', "'": '.----.',
    '!': '-.-.--', '/': '-..-.', '(': '-.--.', ')': '-.--.-',
    '&': '.-...', ':': '---...', ';': '-.-.-.', '=': '-...-',
    '+': '.-.-.', '-': '-....-', '_': '..--.-', '"': '.-..-.',
    r'$': '...-..-', '@': '.--.-.',
    // Space (word separator)
    ' ': '',
  };

  static final Map<String, String> _reverseTable = _buildReverseTable();

  static Map<String, String> _buildReverseTable() {
    final map = <String, String>{};
    for (final entry in _table.entries) {
      if (entry.value.isNotEmpty) {
        map[entry.value] = entry.key;
      }
    }
    return map;
  }

  /// Returns the Morse code for [character], or `null` if the
  /// character is not representable in Morse code.
  static String? lookup(String character) {
    final upper = character.toUpperCase();
    return _table[upper];
  }

  /// Whether [character] can be encoded in Morse code.
  static bool canEncode(String character) {
    return _table.containsKey(character.toUpperCase());
  }

  /// Reverse lookup: returns the character for [morseCode], or
  /// `null` if the Morse code is not a valid symbol.
  static String? reverseLookup(String morseCode) {
    return _reverseTable[morseCode];
  }
}
