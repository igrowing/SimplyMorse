import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Screen offering three encoding modes: Sound, Flash LED, Both.
///
/// On web, Flash LED and Both modes are disabled because
/// the torch is a hardware-only feature.
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
      final supportsTorch =
          mode == EncodingMode.flash || mode == EncodingMode.both;
      final disabled = kIsWeb && supportsTorch;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _ModeButton(
            mode: mode,
            onTap: disabled ? null : () => _navigateToMode(context, mode),
            disabledOnWeb: disabled,
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
  const _ModeButton({
    required this.mode,
    required this.onTap,
    this.disabledOnWeb = false,
  });

  final EncodingMode mode;
  final VoidCallback? onTap;
  final bool disabledOnWeb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(mode.icon, size: 32),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mode.label,
              style: theme.textTheme.titleMedium,
            ),
            if (disabledOnWeb)
              Text(
                'Not available on web',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(100),
      ),
    );
  }
}
