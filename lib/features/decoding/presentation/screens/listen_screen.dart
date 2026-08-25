import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Stub screen for audio-based Morse decoding (Phase 2).
class ListenScreen extends StatelessWidget {
  const ListenScreen({
    this.themeMode,
    this.onThemeToggle,
    super.key,
  });

  final ThemeMode? themeMode;
  final VoidCallback? onThemeToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: themeMode != null && onThemeToggle != null
          ? AppTopBar(
              themeMode: themeMode!,
              onThemeToggle: onThemeToggle!,
            )
          : AppBar(title: const Text('Hear')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Audio decoding — coming soon',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Phase 2 feature',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
