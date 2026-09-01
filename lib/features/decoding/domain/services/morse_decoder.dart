import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart'
    show ElementBuilder;
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';

/// Decodes on/off timing elements into text using the Morse
/// code table.
///
/// This is pure domain logic with no platform dependencies.
/// It takes a list of [DecodedElement]s (tone/gap durations)
/// and produces decoded text by:
/// 1. Estimating the dit duration from the 25th-percentile
///    on-element (robust against noise spikes).
/// 2. Detecting Farnsworth timing: if inter-character gaps
///    are significantly longer than 3 × dit, a separate
///    "gap dit" is estimated from those gaps and used for
///    char-gap / word-gap classification. This lets the
///    decoder handle both standard and Farnsworth-timed
///    signals automatically.
/// 3. Classifying on-elements as dit (short) or dah (long),
///    rejecting marks shorter than 35 % of the dit as noise.
/// 4. Classifying off-elements as intra-gap, char-gap, or
///    word-gap based on duration ratios.
/// 5. Grouping dits/dahs into Morse symbols (max 7 per
///    character) and looking them up in the reverse Morse
///    table.
class MorseDecoder {
  MorseDecoder({
    this.ditThreshold = 2.2,
    this.gapThreshold = 2.0,
    this.wordGapThreshold = 6.0,
  });

  /// Multiplier of dit duration below which an on-element is a
  /// dit, at or above which it is a dah.
  ///
  /// The ITU ratio is 3.0 (dah = 3 dits), but in practice timing
  /// jitter means a threshold of 2.0 misclassifies long dits as
  /// dahs. 2.2 is more lenient toward dahs and better tolerates
  /// quantization noise at high WPM.
  final double ditThreshold;

  /// Multiplier of dit duration below which an off-element is
  /// an intra-gap (ignored), at or above which it is a
  /// character or word gap.
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
  static const double _noiseFloorMs = 8;

  /// Farnsworth detection threshold: if the estimated gap-dit
  /// exceeds the mark-dit by more than this ratio, Farnsworth
  /// timing is assumed and the gap-dit is used for char-gap /
  /// word-gap classification.
  ///
  /// In standard timing, char-gaps = 3 × dit, so gap-dit ≈ dit
  /// and the ratio is ≈ 1.0. A 1.2 threshold gives 20 % margin
  /// for timing jitter before false-positive detection.
  static const double _farnsworthRatio = 1.2;

  /// Minimum number of inter-character gaps needed to attempt
  /// Farnsworth detection. Below this, the signal is too short
  /// to reliably distinguish Farnsworth from jitter.
  static const int _minGapsForFarnsworth = 2;

  /// Estimates words per minute from a dit duration in ms.
  ///
  /// WPM = 1200 / dit_ms (standard PARIS timing: 50 dits per
  /// word, 60 seconds per minute → 1200 / dit_ms).
  static double estimateWpm(double ditMs) {
    if (ditMs <= 0) return 0;
    return 1200.0 / ditMs;
  }

  /// Decodes a Morse code string (e.g. ".−.") to its character.
  /// Returns `null` for unrecognized codes.
  String? decodeSymbol(String morseCode) {
    return MorseCodeTable.reverseLookup(morseCode);
  }

  /// Decodes a list of [DecodedElement]s into text.
  ///
  /// If [ditMs] is not provided, it is estimated from the
  /// 25th-percentile on-element duration. The gap-dit (used
  /// for char-gap / word-gap classification) is estimated
  /// separately from inter-character gaps — if it is
  /// significantly larger than the mark-dit, Farnsworth timing
  /// is detected and used.
  String decodeElements(
    List<DecodedElement> elements, {
    double? ditMs,
  }) {
    if (elements.isEmpty) return '';

    final dit = ditMs ?? _estimateDitDuration(elements);
    if (dit <= 0) return '';

    // Estimate the gap-dit (Farnsworth dit). In standard timing
    // this equals the mark-dit; in Farnsworth timing it is
    // larger and used for char-gap / word-gap classification.
    final gapDit = _estimateGapDit(elements, dit);

    final buffer = StringBuffer();
    final morseBuilder = StringBuffer();

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
        // Intra-element gaps are at character speed, so use
        // the mark-dit for the intra/inter boundary.
        final ratio = el.durationMs / dit;
        if (ratio < gapThreshold) {
          continue;
        }
        // Inter-character and inter-word gaps may be at
        // Farnsworth speed, so use the gap-dit for the
        // char/word boundary.
        if (el.durationMs < gapDit * wordGapThreshold) {
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
        .map((e) => e.durationMs.toDouble())
        .where((d) => d >= _noiseFloorMs)
        .toList();
    if (onDurations.isEmpty) return 0;
    onDurations.sort();

    // Use 25th percentile for dit estimation
    final idx = (onDurations.length * 0.25).floor();
    return onDurations[idx.clamp(0, onDurations.length - 1)];
  }

  /// Estimates the "gap dit" — the unit duration for inter-
  /// character and inter-word gap classification.
  ///
  /// In standard Morse, char-gaps = 3 × dit and word-gaps =
  /// 7 × dit, so the gap-dit equals the mark-dit.
  ///
  /// In Farnsworth timing, marks and intra-element gaps are at
  /// character speed, but inter-character and inter-word gaps
  /// are stretched to a slower Farnsworth speed. The gap-dit is
  /// the Farnsworth unit, estimated from the typical
  /// inter-character gap duration.
  ///
  /// Algorithm:
  /// 1. Collect all off-element durations >= [gapThreshold] ×
  ///    [markDit] — these are inter-character and inter-word
  ///    gaps (not intra-element gaps).
  /// 2. Take the 25th-percentile as the typical inter-character
  ///    gap.
  /// 3. gapDit = typicalCharGap / 3.
  /// 4. If gapDit > markDit × [_farnsworthRatio], return gapDit
  ///    (Farnsworth detected). Otherwise return markDit
  ///    (standard timing).
  double _estimateGapDit(
    List<DecodedElement> elements,
    double markDit,
  ) {
    final longGaps = elements
        .where((e) => !e.isOn)
        .map((e) => e.durationMs.toDouble())
        .where((d) => d >= markDit * gapThreshold)
        .toList();

    if (longGaps.length < _minGapsForFarnsworth) return markDit;

    longGaps.sort();

    // The 25th-percentile of long gaps is the typical
    // inter-character gap (char-gaps are shorter and more
    // common than word-gaps).
    final typicalCharGap = _percentile(longGaps, 0.25);
    final gapDit = typicalCharGap / 3.0;

    // Farnsworth detected if the gap-dit is significantly
    // larger than the mark-dit.
    if (gapDit > markDit * _farnsworthRatio) {
      return gapDit;
    }

    // Standard timing — use the mark-dit for everything.
    return markDit;
  }

  /// Returns the value at the [quantile] position (0–1) of a
  /// sorted list.
  double _percentile(List<double> sorted, double quantile) {
    if (sorted.isEmpty) return 0;
    final idx = (sorted.length * quantile).floor();
    return sorted[idx.clamp(0, sorted.length - 1)];
  }
}
