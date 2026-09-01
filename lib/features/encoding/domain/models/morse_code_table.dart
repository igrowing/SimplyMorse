/// International Morse Code lookup table.
///
/// Maps characters to their dot/dash representation.
/// Includes the full ITU standard: letters, digits, punctuation,
/// common prosigns, and Latin Extended (European) characters.
///
/// Decoding uses a priority system to control which character
/// sets are active. By default (priority 3), only ASCII characters
/// (letters, digits, punctuation) are decoded. Setting priority to
/// 4 or higher enables Latin Extended (Ä, Ö, Ü, É, etc.), which
/// have short Morse codes that can be matched by misclassified
/// sequences — so they are opt-in only.
class MorseCodeTable {
  MorseCodeTable._();

  // ── Priority 1: Latin letters ──────────────────────────────
  static const Map<String, String> _latin = {
    'A': '.-',
    'B': '-...',
    'C': '-.-.',
    'D': '-..',
    'E': '.',
    'F': '..-.',
    'G': '--.',
    'H': '....',
    'I': '..',
    'J': '.---',
    'K': '-.-',
    'L': '.-..',
    'M': '--',
    'N': '-.',
    'O': '---',
    'P': '.--.',
    'Q': '--.-',
    'R': '.-.',
    'S': '...',
    'T': '-',
    'U': '..-',
    'V': '...-',
    'W': '.--',
    'X': '-..-',
    'Y': '-.--',
    'Z': '--..',
  };

  // ── Priority 2: Numbers ────────────────────────────────────
  static const Map<String, String> _numbers = {
    '0': '-----',
    '1': '.----',
    '2': '..---',
    '3': '...--',
    '4': '....-',
    '5': '.....',
    '6': '-....',
    '7': '--...',
    '8': '---..',
    '9': '----.',
  };

  // ── Priority 3: Punctuation ────────────────────────────────
  static const Map<String, String> _punctuation = {
    '.': '.-.-.-',
    ',': '--..--',
    '?': '..--..',
    "'": '.----.',
    '!': '-.-.--',
    '/': '-..-.',
    '(': '-.--.',
    ')': '-.--.-',
    '&': '.-...',
    ':': '---...',
    ';': '-.-.-.',
    '=': '-...-',
    '+': '.-.-.',
    '-': '-....-',
    '_': '..--.-',
    '"': '.-..-.',
    r'$': '...-..-',
    '@': '.--.-.',
  };

  // ── Priority 3: Prosigns ───────────────────────────────────
  // Prosigns are long enough (≥ 6 elements) to not be confused
  // with misclassified sequences from timing errors.
  static const Map<String, String> _prosigns = {
    'SOS': '...---...', // Distress signal (9 elements)
  };

  // ── Priority 4: Latin Extended (European) ──────────────────
  // These have short codes that can match misclassified sequences.
  // Only active when the user explicitly opts in via priority ≥ 4.
  static const Map<String, String> _latinExtended = {
    'Ä': '.-',
    'À': '.--.-',
    'Á': '.--.-',
    'Å': '.--.-',
    'È': '.-..-',
    'É': '..-..',
    'Ê': '-..-.',
    'Ç': '-.-..',
    'Ñ': '--.--',
    'Ö': '---.',
    'Ü': '..--',
    'Š': '----',
    'Ð': '..--',
    'Þ': '.--..',
    'Æ': '.-...',
    'Œ': '---.',
  };

  // ── Space (word separator) ─────────────────────────────────

  // ── Full encode table (all priorities) ────────────────────
  static const Map<String, String> _table = {
    ..._latin,
    ..._numbers,
    ..._punctuation,
    ..._prosigns,
    ..._latinExtended,
    ' ': '',
  };

  // ── Reverse tables by priority level ───────────────────────
  // Pre-built reverse lookup maps for each priority level.
  // [_reverseByPriority[3]] = ASCII only (letters + numbers +
  // punctuation + prosigns).
  // [_reverseByPriority[4]] = adds Latin Extended.
  static final List<Map<String, String>> _reverseByPriority =
      _buildReverseTables();

  static Map<String, String> _buildReverseTable(Map<String, String> table) {
    final map = <String, String>{};
    for (final entry in table.entries) {
      if (entry.value.isNotEmpty) {
        // First definition wins — lower-priority sets take
        // precedence so a European code that collides with an
        // ASCII code (e.g. Ä='.-' = 'A') keeps decoding as the
        // ASCII character.
        map.putIfAbsent(entry.value, () => entry.key);
      }
    }
    return map;
  }

  static List<Map<String, String>> _buildReverseTables() {
    final ascii = {
      ..._latin,
      ..._numbers,
      ..._punctuation,
      ..._prosigns,
    };
    final extended = {
      ...ascii,
      ..._latinExtended,
    };
    // Index by priority: [0]=empty, [1]=latin, [2]=+numbers,
    // [3]=+punctuation+prosigns, [4]=+latinExtended
    return [
      {},
      _buildReverseTable(_latin),
      _buildReverseTable({..._latin, ..._numbers}),
      _buildReverseTable(ascii),
      _buildReverseTable(extended),
    ];
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
  ///
  /// [priority] controls which character sets are searched:
  /// * 1: Latin letters only
  /// * 2: + Numbers
  /// * 3: + Punctuation and prosigns (default — ASCII only)
  /// * 4: + Latin Extended (European characters: Ä, Ö, Ü, etc.)
  ///
  /// At the default priority 3, short European codes like
  /// É=`..-..` or Ç=`-.-..` return `null` — they are not matched.
  /// This prevents misclassified sequences from producing false
  /// European characters. Set priority to 4 to enable them.
  static String? reverseLookup(String morseCode, {int priority = 3}) {
    final level = priority.clamp(0, _reverseByPriority.length - 1);
    return _reverseByPriority[level][morseCode];
  }
}
