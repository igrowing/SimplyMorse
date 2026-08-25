import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/transmission_state.dart';

/// A dynamic label that shows the entered text and highlights
/// each character in color while it is being transmitted.
class MorseTransmissionLabel extends StatelessWidget {
  const MorseTransmissionLabel({
    required this.text,
    required this.state,
    super.key,
  });

  final String text;
  final TransmissionState state;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final spans = <TextSpan>[];

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final isCurrent = state.isTransmitting && i == state.currentCharIndex;
      final isTransmitted = state.isTransmitting && i < state.currentCharIndex;
      final isCompleted = state.isCompleted;

      Color color;
      FontWeight weight;

      if (isCurrent) {
        color = theme.colorScheme.primary;
        weight = FontWeight.bold;
      } else if (isTransmitted || isCompleted) {
        color = theme.colorScheme.primary.withValues(alpha: 0.6);
        weight = FontWeight.normal;
      } else {
        color = theme.colorScheme.onSurface.withValues(alpha: 0.4);
        weight = FontWeight.normal;
      }

      spans.add(
        TextSpan(
          text: char,
          style: TextStyle(color: color, fontWeight: weight),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyLarge,
          children: spans,
        ),
      ),
    );
  }
}
