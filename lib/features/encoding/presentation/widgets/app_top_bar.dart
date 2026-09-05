import 'package:flutter/material.dart';

import 'package:simply_morse/core/constants/app_constants.dart';

/// A reusable top app bar showing the app icon and name.
///
/// Optionally shows a settings (gear) icon that navigates to
/// the Settings screen. When [showSettingsIcon] is false,
/// no action button is shown (used on the Settings screen
/// itself).
///
/// When the current route can pop (i.e. this is not the root
/// route), a back button is shown instead of the app icon.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    this.showSettingsIcon = true,
    this.onSettingsTap,
    this.titleText,
    super.key,
  });

  final bool showSettingsIcon;
  final VoidCallback? onSettingsTap;

  /// Optional title overriding the app name — used by mode
  /// screens (e.g. the camera decoder) to label what the user
  /// is looking at.
  final String? titleText;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
              tooltip: MaterialLocalizations.of(
                context,
              ).backButtonTooltip,
            )
          : const Padding(
              padding: EdgeInsets.all(10),
              child: Image(
                image: AssetImage('assets/SimplyMorse_icon1024.png'),
                width: 28,
                height: 28,
              ),
            ),
      title: Text(
        titleText ?? AppConstants.appName,
        style: const TextStyle(
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
