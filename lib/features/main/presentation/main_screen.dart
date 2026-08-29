import 'package:flutter/material.dart';

import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/receive_screen.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Main screen with two large buttons: Send and Receive.
class MainScreen extends StatelessWidget {
  const MainScreen({
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
            children: _mainButtons(context),
          ),
        ),
      ),
    );
  }

  List<Widget> _mainButtons(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _MainButton(
          icon: Icons.send,
          label: 'Send',
          onTap: () => _navigateToSend(context),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: _MainButton(
          icon: Icons.download,
          label: 'Receive',
          onTap: () => _navigateToReceive(context),
        ),
      ),
    ];
  }

  void _navigateToSend(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          themeController: themeController,
          screenTimeoutService: screenTimeoutService,
          displayTimeout: displayTimeout,
          onDisplayTimeoutChanged: onDisplayTimeoutChanged,
        ),
      ),
    );
  }

  void _navigateToReceive(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveScreen(
          themeController: themeController,
          screenTimeoutService: screenTimeoutService,
          displayTimeout: displayTimeout,
          onDisplayTimeoutChanged: onDisplayTimeoutChanged,
        ),
      ),
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

class _MainButton extends StatelessWidget {
  const _MainButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 24),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        shape: const StadiumBorder(),
      ),
    );
  }
}
