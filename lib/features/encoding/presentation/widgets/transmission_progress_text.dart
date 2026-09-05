import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/transmission_state.dart';

/// Rich text showing a message with per-character transmission
/// progress: the character currently being transmitted is
/// highlighted (color + bold), characters already transmitted are
/// dimmed, and characters still pending are faint.
///
/// Unlike a standalone progress box, this widget draws **inside**
/// the input box on the Send screen — the TextField is swapped
/// for it while a transmission is running, so the progress
/// display needs no extra screen space and the highlighting
/// appears exactly where the user typed the text.
class TransmissionProgressText extends StatelessWidget {
  const TransmissionProgressText({
    required this.text,
    required this.state,
    super.key,
  });

  final String text;
  final TransmissionState state;

  /// Builds the per-character spans. Static so the styling rules
  /// can be unit-tested without pumping a widget tree.
  static List<TextSpan> buildSpans(
    String text,
    TransmissionState state,
    ColorScheme colors,
  ) {
    final spans = <TextSpan>[];

    for (var i = 0; i < text.length; i++) {
      final isCurrent = state.isTransmitting && i == state.currentCharIndex;
      final isTransmitted = state.isTransmitting && i < state.currentCharIndex;
      final isCompleted = state.isCompleted;

      Color color;
      FontWeight weight;

      if (isCurrent) {
        color = colors.primary;
        weight = FontWeight.bold;
      } else if (isTransmitted || isCompleted) {
        color = colors.primary.withValues(alpha: 0.6);
        weight = FontWeight.normal;
      } else {
        color = colors.onSurface.withValues(alpha: 0.4);
        weight = FontWeight.normal;
      }

      spans.add(
        TextSpan(
          text: text[i],
          style: TextStyle(color: color, fontWeight: weight),
        ),
      );
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodyLarge,
        children: buildSpans(text, state, theme.colorScheme),
      ),
    );
  }
}
