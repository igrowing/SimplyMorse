import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_code_table.dart';
import 'package:simply_morse/features/encoding/domain/models/morse_symbol.dart';

/// Converts text into a list of [MorseSymbol]s with timing
/// information and builds transmission timelines.
class MorseEncoder {
  /// Encodes [text] into Morse symbols, computing timing based on
  /// the provided [settings].
  List<MorseSymbol> encode(String text, EncodingSettings settings) {
    final symbols = <MorseSymbol>[];
    var currentTime = 0.0;

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final morse = MorseCodeTable.lookup(char);

      // Skip unencodable characters
      if (morse == null) continue;

      final symbolStart = currentTime;
      var symbolDuration = 0.0;

      if (morse.isEmpty) {
        // Word gap (space)
        symbolDuration = settings.wordGapMs;
      } else {
        for (var j = 0; j < morse.length; j++) {
          final isDit = morse[j] == '.';
          symbolDuration += isDit ? settings.ditMs : settings.dahMs;
          if (j < morse.length - 1) {
            symbolDuration += settings.intraGapMs;
          }
        }
      }

      symbols.add(
        MorseSymbol(
          character: char,
          morseCode: morse,
          startMs: symbolStart,
          durationMs: symbolDuration,
        ),
      );

      currentTime += symbolDuration;

      // Add inter-character or inter-word gap
      if (i < text.length - 1) {
        final nextChar = text[i + 1];
        final nextMorse = MorseCodeTable.lookup(nextChar);
        if (nextMorse == null) continue;

        if (nextMorse.isEmpty || morse.isEmpty) {
          currentTime += settings.wordGapMs;
        } else {
          currentTime += settings.charGapMs;
        }
      }
    }

    return symbols;
  }

  /// Builds the timeline of tone events for audio/flash playback.
  List<ToneEvent> buildTimeline(
    List<MorseSymbol> symbols,
    EncodingSettings settings,
  ) {
    final events = <ToneEvent>[];

    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];

      if (symbol.morseCode.isEmpty) {
        events.add(
          ToneEvent(
            isOn: false,
            durationMs: settings.wordGapMs.round(),
            charIndex: i,
          ),
        );
        continue;
      }

      for (var j = 0; j < symbol.morseCode.length; j++) {
        final isDit = symbol.morseCode[j] == '.';
        final duration = isDit
            ? settings.ditMs.round()
            : settings.dahMs.round();

        events.add(
          ToneEvent(
            isOn: true,
            durationMs: duration,
            charIndex: i,
          ),
        );

        if (j < symbol.morseCode.length - 1) {
          events.add(
            ToneEvent(
              isOn: false,
              durationMs: settings.intraGapMs.round(),
              charIndex: i,
            ),
          );
        }
      }

      // Inter-character gap. Around a word-gap symbol no extra
      // gap is added: the word symbol's own event above IS the
      // word gap. Emitting adjacent gaps too stretched every
      // word gap to 21 units instead of the standard 7 (caught
      // by the encoder/decoder roundtrip test).
      if (i < symbols.length - 1) {
        final next = symbols[i + 1];
        if (!next.isWordGap && !symbol.isWordGap) {
          events.add(
            ToneEvent(
              isOn: false,
              durationMs: settings.charGapMs.round(),
              charIndex: i,
            ),
          );
        }
      }
    }

    return events;
  }
}

/// A single tone event in the transmission timeline.
class ToneEvent {
  const ToneEvent({
    required this.isOn,
    required this.durationMs,
    required this.charIndex,
  });

  final bool isOn;
  final int durationMs;
  final int charIndex;
}
