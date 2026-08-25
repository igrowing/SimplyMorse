import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';

/// Decodes on/off timing elements into text using the Morse
/// code table.
///
/// This is pure domain logic with no platform dependencies.
/// It takes a list of [DecodedElement]s (tone/gap durations)
/// and produces decoded text by:
/// 1. Estimating the dit duration from the shortest on-element.
/// 2. Classifying on-elements as dit (short) or dah (long).
/// 3. Classifying off-elements as intra-gap, char-gap, or
///    word-gap based on duration ratios.
/// 4. Grouping dits/dahs into Morse symbols and looking them up
///    in the reverse Morse table.
class MorseDecoder {
  MorseDecoder({this.ditThreshold = 2.0, this.wordGapThreshold = 5.0});

  /// Multiplier of dit duration below which an on-element is a
  /// dit, at or above which it is a dah.
  final double ditThreshold;

  /// Multiplier of dit duration at or above which an off-element
  /// is a word gap (below this but above intra-gap threshold is
  /// a character gap).
  final double wordGapThreshold;

  /// Decodes a Morse code string (e.g. ".−.") to its character.
  /// Returns `null` for unrecognized codes.
  String? decodeSymbol(String morseCode) {
    return MorseCodeTable.reverseLookup(morseCode);
  }

  /// Decodes a list of [DecodedElement]s into text.
  ///
  /// If [ditMs] is not provided, it is estimated from the
  /// shortest on-element duration.
  String decodeElements(
    List<DecodedElement> elements, {
    double? ditMs,
  }) {
    if (elements.isEmpty) return '';

    final dit = ditMs ?? _estimateDitDuration(elements);
    if (dit <= 0) return '';

    final buffer = StringBuffer();
    var morseBuilder = StringBuffer();

    for (final el in elements) {
      if (el.isOn) {
        if (el.durationMs < dit * ditThreshold) {
          morseBuilder.write('.');
        } else {
          morseBuilder.write('-');
        }
      } else {
        final ratio = el.durationMs / dit;
        if (ratio < ditThreshold) {
          continue;
        } else if (ratio < wordGapThreshold) {
          _flushSymbol(buffer, morseBuilder);
          morseBuilder.clear();
        } else {
          _flushSymbol(buffer, morseBuilder);
          morseBuilder.clear();
          buffer.write(' ');
        }
      }
    }

    _flushSymbol(buffer, morseBuilder);

    return buffer.toString();
  }

  void _flushSymbol(StringBuffer output, StringBuffer morse) {
    final code = morse.toString();
    if (code.isEmpty) return;
    final char = decodeSymbol(code);
    if (char != null) {
      output.write(char);
    }
  }

  /// Estimates the dit duration as the shortest on-element.
  double _estimateDitDuration(List<DecodedElement> elements) {
    final onDurations = elements
        .where((e) => e.isOn)
        .map((e) => e.durationMs)
        .toList();
    if (onDurations.isEmpty) return 0;
    onDurations.sort();
    return onDurations.first.toDouble();
  }
}
