import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// Represents a single character's Morse representation and its
/// timing position within a transmission sequence.
@immutable
class MorseSymbol extends Equatable {
  const MorseSymbol({
    required this.character,
    required this.morseCode,
    this.startMs = 0,
    this.durationMs = 0,
  });

  /// The original source character (e.g. 'A', ' ', '0').
  final String character;

  /// Morse representation: dots and dashes (e.g. '.-').
  /// Empty string for word separator (space).
  final String morseCode;

  /// Start time of this symbol in the full transmission, in ms.
  final double startMs;

  /// Total duration of this symbol's tone + internal gaps, in ms.
  final double durationMs;

  /// Whether this symbol represents a word gap (space character).
  bool get isWordGap => character == ' ';

  @override
  List<Object?> get props => [character, morseCode, startMs, durationMs];
}
