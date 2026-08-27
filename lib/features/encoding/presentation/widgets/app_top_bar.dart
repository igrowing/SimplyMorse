import 'package:flutter/material.dart';

import 'package:simply_morse/core/constants/app_constants.dart';

/// A reusable top app bar showing the app icon, name, version,
/// and a theme toggle button.
///
/// When in [ThemeMode.system], the toggle icon shows the
/// *opposite* of the current system theme — e.g. if the
/// system is light, it shows `Icons.dark_mode`.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    required this.themeMode,
    required this.onThemeToggle,
    super.key,
  });

  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      leading: const Padding(
        padding: EdgeInsets.all(10),
        child: Image(
          image: AssetImage('assets/SimplyMorse_icon1024.png'),
          width: 28,
          height: 28,
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            AppConstants.appName,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            'v${AppConstants.appVersion}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(_themeIcon(context)),
          onPressed: onThemeToggle,
          tooltip: _themeTooltip,
        ),
      ],
    );
  }

  IconData _themeIcon(BuildContext context) {
    switch (themeMode) {
      case ThemeMode.system:
        // Show the opposite of the current system theme
        final isSystemDark =
            MediaQuery.platformBrightnessOf(context) == Brightness.dark;
        return isSystemDark ? Icons.light_mode : Icons.dark_mode;
      case ThemeMode.light:
        return Icons.light_mode;
      case ThemeMode.dark:
        return Icons.dark_mode;
    }
  }

  String get _themeTooltip => switch (themeMode) {
    ThemeMode.system => 'System theme (tap to change)',
    ThemeMode.light => 'Light theme (tap to change)',
    ThemeMode.dark => 'Dark theme (tap to change)',
  };
}
