import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Screen offering three encoding modes: Sound, Flash LED, Both.
///
/// On web, Flash LED and Both modes use screen-based LED
/// emulation instead of hardware torch.
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            alignment: WrapAlignment.center,
            runSpacing: 16,
            children: _modeButtons(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _modeButtons(BuildContext context) {
    return EncodingMode.values.map((mode) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _ModeButton(
          mode: mode,
          onTap: () => _navigateToMode(context, mode),
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
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(mode.icon, size: 24),
      label: Text(mode.label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: const StadiumBorder(),
      ),
    );
  }
}
