import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Screen offering three encoding modes: Sound, Flash LED, Both.
class SendScreen extends StatelessWidget {
  const SendScreen({
    required this.themeMode,
    required this.onThemeToggle,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        themeMode: themeMode,
        onThemeToggle: onThemeToggle,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 500,
              ),
              child: isWide
                  ? Row(children: _modeButtons(context))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _modeButtons(context),
                    ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _modeButtons(BuildContext context) {
    return EncodingMode.values.map((mode) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _ModeButton(
            mode: mode,
            onTap: () => _navigateToMode(context, mode),
          ),
        ),
      );
    }).toList();
  }

  void _navigateToMode(
    BuildContext context,
    EncodingMode mode,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendModeScreen(
          mode: mode,
          themeMode: themeMode,
          onThemeToggle: onThemeToggle,
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({required this.mode, required this.onTap});

  final EncodingMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(mode.icon, size: 32),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          mode.label,
          style: theme.textTheme.titleMedium,
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(100),
      ),
    );
  }
}
