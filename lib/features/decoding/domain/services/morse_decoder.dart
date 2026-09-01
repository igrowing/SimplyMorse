import 'dart:math';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';

/// Decodes on/off timing elements into text using the Morse
/// code table.
///
/// This is pure domain logic with no platform dependencies.
/// It takes a list of [DecodedElement]s (tone/gap durations)
/// and produces decoded text by:
/// 1. Estimating the dit duration from the 25th-percentile
///    on-element (robust against noise spikes).
/// 2. Classifying on-elements as dit (short) or dah (long),
///    rejecting marks shorter than 35 % of the dit as noise.
/// 3. Classifying off-elements as intra-gap, char-gap, or
///    word-gap based on duration ratios.
/// 4. Grouping dits/dahs into Morse symbols (max 7 per
///    character) and looking them up in the reverse Morse
///    table.
class MorseDecoder {
  MorseDecoder({
    this.ditThreshold = 2.2,
    this.gapThreshold = 2.0,
    this.wordGapThreshold = 6.0,
    this.priority = 3,
  });

  /// Multiplier of dit duration below which an on-element is a
  /// dit, at or above which it is a dah.
  ///
  /// The ITU ratio is 3.0 (dah = 3 dits), but in practice timing
  /// jitter means a threshold of 2.0 misclassifies long dits as
  /// dahs. 2.2 is more lenient toward dahs and better tolerates
  /// quantization noise at high WPM.
  final double ditThreshold;

  /// Multiplier of dit duration below which an off-element is an
  /// intra-gap (ignored), at or above which it is a character or
  /// word gap.
  ///
  /// Kept at 2.0 (ITU standard: char gap = 3 dits, intra-gap =
  /// 1 dit) because raising it to match [ditThreshold] would
  /// merge characters that should be separated — a short
  /// character gap jittered to 2.1 × dit would become an
  /// intra-gap, merging two characters into an invalid code.
  final double gapThreshold;

  /// Multiplier of dit duration at or above which an off-element
  /// is a word gap (below this but above [gapThreshold] is a
  /// character gap). The ITU standard word gap is 7 dits;
  /// 6.0 is the practical sweet spot that tolerates timing
  /// jitter without splitting words prematurely.
  final double wordGapThreshold;

  /// Character set priority for decoding.
  ///
  /// * 3 (default): ASCII only — letters, numbers, punctuation.
  /// * 4: Adds Latin Extended (European characters: Ä, Ö, Ü, É,
  ///   etc.). These have short Morse codes that can match
  ///   misclassified sequences, so they are opt-in only.
  ///
  /// See [MorseCodeTable.reverseLookup] for details.
  final int priority;

  /// Maximum dits/dahs per character before the buffer is
  /// discarded as a timing error. The longest standard Morse
  /// symbol is 6 elements; anything beyond 7 is garbage.
  static const int _maxSymbolsPerChar = 7;

  /// Marks shorter than this fraction of the dit duration are
  /// rejected as noise. The [ElementBuilder] already merges
  /// glitches at 0.25 × dit, but a short mark that survives
  /// merging can still be misclassified as a dit. A 0.35 floor
  /// rejects it instead.
  static const double _minMarkRatio = 0.35;

  /// Hard noise floor — marks below this absolute duration are
  /// ignored during both dit estimation and decoding.
  static const double _noiseFloorMs = 8.0;

  /// Decodes a Morse code string (e.g. ".−.") to its character.
  /// Returns `null` for unrecognized codes.
  String? decodeSymbol(String morseCode) {
    return MorseCodeTable.reverseLookup(morseCode, priority: priority);
  }

  /// Decodes a list of [DecodedElement]s into text.
  ///
  /// If [ditMs] is not provided, it is estimated from the
  /// 25th-percentile on-element duration.
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
        // Reject marks below the hard noise floor.
        if (el.durationMs < _noiseFloorMs) continue;
        // Reject marks shorter than 35 % of dit as noise.
        if (el.durationMs < dit * _minMarkRatio) continue;

        if (el.durationMs < dit * ditThreshold) {
          morseBuilder.write('.');
        } else {
          morseBuilder.write('-');
        }

        // Max symbols per character — discard timing garbage.
        if (morseBuilder.length > _maxSymbolsPerChar) {
          morseBuilder.clear();
        }
      } else {
        final ratio = el.durationMs / dit;
        if (ratio < gapThreshold) {
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

  /// Estimates the dit duration as the 25th-percentile
  /// on-element duration, which is more robust against noise
  /// spikes than using the minimum. Marks below the hard noise
  /// floor are excluded from the sample.
  double _estimateDitDuration(List<DecodedElement> elements) {
    final onDurations = elements
        .where((e) => e.isOn)
        .map((e) => e.durationMs)
        .where((d) => d >= _noiseFloorMs)
        .toList();
    if (onDurations.isEmpty) return 0;
    onDurations.sort();

    // Use 25th percentile for dit estimation
    final idx = (onDurations.length * 0.25).floor();
    return onDurations[idx.clamp(0, onDurations.length - 1)].toDouble();
  }

  /// Estimates WPM from a dit duration using the PARIS method.
  ///
  /// The word PARIS is exactly 50 dit-lengths, so
  /// `WPM = 60000 / (ditMs × 50) = 1200 / ditMs`.
  ///
  /// Example: ditMs = 150 → WPM = 8; ditMs = 60 → WPM = 20.
  static double estimateWpm(double ditMs) {
    if (ditMs <= 0) return 0;
    return 1200 / ditMs;
  }
}
