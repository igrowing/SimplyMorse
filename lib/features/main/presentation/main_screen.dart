import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/listen_screen.dart';
import 'package:simply_morse/features/decoding/presentation/screens/see_screen.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

/// Main screen with Send button and a Receive group containing
/// Listen (audio) and Watch (camera) buttons.
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Wide (landscape-style) layout: the receiving
              // group stacks vertically beside Send, so the
              // two modes read as a group. Narrow layout: the
              // receiving buttons stay side by side under Send,
              // with clear vertical separation from it.
              final wide = constraints.maxWidth >= 600;
              final receiveGroup = wide
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SubButton(
                          icon: Icons.mic,
                          label: 'Listen',
                          onTap: () => _navigateToListen(context),
                        ),
                        const SizedBox(height: 12),
                        _SubButton(
                          icon: Icons.camera_alt,
                          label: 'Watch',
                          disabledOnWeb: kIsWeb,
                          onTap: kIsWeb
                              ? null
                              : () => _navigateToWatch(context),
                        ),
                      ],
                    )
                  : Wrap(
                      alignment: WrapAlignment.center,
                      runSpacing: 8,
                      children: [
                        _SubButton(
                          icon: Icons.mic,
                          label: 'Listen',
                          onTap: () => _navigateToListen(context),
                        ),
                        _SubButton(
                          icon: Icons.camera_alt,
                          label: 'Watch',
                          disabledOnWeb: kIsWeb,
                          onTap: kIsWeb
                              ? null
                              : () => _navigateToWatch(context),
                        ),
                      ],
                    );

              if (wide) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: _MainButton(
                        icon: Icons.send,
                        label: 'Send',
                        onTap: () => _navigateToSend(context),
                      ),
                    ),
                    const SizedBox(width: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      child: receiveGroup,
                    ),
                  ],
                );
              }
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: _MainButton(
                      icon: Icons.send,
                      label: 'Send',
                      onTap: () => _navigateToSend(context),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    child: receiveGroup,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _navigateToSend(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SendModeScreen(
            themeController: themeController,
            screenTimeoutService: screenTimeoutService,
            displayTimeout: displayTimeout,
            onDisplayTimeoutChanged: onDisplayTimeoutChanged,
          ),
        ),
      ),
    );
  }

  void _navigateToListen(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ListenScreen(
            themeController: themeController,
            screenTimeoutService: screenTimeoutService,
            displayTimeout: displayTimeout,
            onDisplayTimeoutChanged: onDisplayTimeoutChanged,
          ),
        ),
      ),
    );
  }

  void _navigateToWatch(BuildContext context) {
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SeeScreen(
            themeController: themeController,
            screenTimeoutService: screenTimeoutService,
            displayTimeout: displayTimeout,
            onDisplayTimeoutChanged: onDisplayTimeoutChanged,
          ),
        ),
      ),
    );
  }

  void _navigateToSettings(BuildContext context) {
    unawaited(
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

class _SubButton extends StatelessWidget {
  const _SubButton({
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
