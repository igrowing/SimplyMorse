import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:simply_morse/features/decoding/presentation/screens/listen_screen.dart';
import 'package:simply_morse/features/decoding/presentation/screens/see_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Receive screen with two entry points: Hear (audio) and
/// Watch (camera).
///
/// On web, the Watch button is disabled because camera frame
/// streaming (`startImageStream`) is not supported on the
/// web platform.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({
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
            children: _entryButtons(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _entryButtons(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _EntryButton(
          icon: Icons.mic,
          label: 'Hear',
          onTap: () => _navigate(
            context,
            ListenScreen(
              themeMode: themeMode,
              onThemeToggle: onThemeToggle,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _EntryButton(
          icon: Icons.camera_alt,
          label: 'Watch',
          disabledOnWeb: kIsWeb,
          onTap: kIsWeb
              ? null
              : () => _navigate(
                  context,
                  SeeScreen(
                    themeMode: themeMode,
                    onThemeToggle: onThemeToggle,
                  ),
                ),
        ),
      ),
    ];
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

class _EntryButton extends StatelessWidget {
  const _EntryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabledOnWeb = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool disabledOnWeb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon, size: 24),
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (disabledOnWeb)
            Text(
              'Not available on web',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: const StadiumBorder(),
      ),
    );
  }
}
