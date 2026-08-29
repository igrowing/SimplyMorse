import 'package:flutter/material.dart';

import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Screen offering three encoding modes: Sound, Flash LED, Both.
///
/// On web, Flash LED and Both modes use screen-based LED
/// emulation instead of hardware torch.
class SendScreen extends StatelessWidget {
  const SendScreen({
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
