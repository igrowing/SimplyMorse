import 'package:flutter/material.dart';

import 'package:simply_morse/core/constants/app_constants.dart';

/// A reusable top app bar showing the app icon, name, version,
/// and a theme toggle button.
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
        child: Icon(Icons.graphic_eq, size: 28),
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
          icon: Icon(_themeIcon),
          onPressed: onThemeToggle,
          tooltip: _themeTooltip,
        ),
      ],
    );
  }

  IconData get _themeIcon => switch (themeMode) {
    ThemeMode.system => Icons.brightness_auto,
    ThemeMode.light => Icons.light_mode,
    ThemeMode.dark => Icons.dark_mode,
  };

  String get _themeTooltip => switch (themeMode) {
    ThemeMode.system => 'System theme (tap to change)',
    ThemeMode.light => 'Light theme (tap to change)',
    ThemeMode.dark => 'Dark theme (tap to change)',
  };
}
