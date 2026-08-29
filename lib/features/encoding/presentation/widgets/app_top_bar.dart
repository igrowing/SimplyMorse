import 'package:flutter/material.dart';

import 'package:simply_morse/core/constants/app_constants.dart';

/// A reusable top app bar showing the app icon and name.
///
/// Optionally shows a settings (gear) icon that navigates to
/// the Settings screen. When [showSettingsIcon] is false,
/// no action button is shown (used on the Settings screen
/// itself).
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    this.showSettingsIcon = true,
    this.onSettingsTap,
    super.key,
  });

  final bool showSettingsIcon;
  final VoidCallback? onSettingsTap;

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
      title: const Text(
        AppConstants.appName,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        if (showSettingsIcon)
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: onSettingsTap,
            tooltip: 'Settings',
          ),
      ],
    );
  }
}
