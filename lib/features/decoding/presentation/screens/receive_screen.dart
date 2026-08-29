import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/listen_screen.dart';
import 'package:simply_morse/features/decoding/presentation/screens/see_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Receive screen with two entry points: Hear (audio) and
/// Watch (camera).
///
/// On web, the Watch button is disabled because camera frame
/// streaming (`startImageStream`) is not supported on the
/// web platform.
class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({
    required this.themeController,
    required this.screenTimeoutService,
    required this.displayTimeout,
    required this.onDisplayTimeoutChanged,
    super.key,
  });

  final ThemeController themeController;
  final ScreenTimeoutService screenTimeoutService;
  final DisplayTimeout displayTimeout;
  final ValueChanged<DisplayTimeout> onDisplayTimeoutChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTopBar(
        onSettingsTap: () => _navigateToSettings(context),
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
              themeController: themeController,
              screenTimeoutService: screenTimeoutService,
              displayTimeout: displayTimeout,
              onDisplayTimeoutChanged: onDisplayTimeoutChanged,
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
                    themeController: themeController,
                    screenTimeoutService: screenTimeoutService,
                    displayTimeout: displayTimeout,
                    onDisplayTimeoutChanged: onDisplayTimeoutChanged,
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

  void _navigateToSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          themeController: themeController,
          screenTimeoutService: screenTimeoutService,
          themeMode: themeController.mode,
          displayTimeout: displayTimeout,
          onDisplayTimeoutChanged: onDisplayTimeoutChanged,
        ),
      ),
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
