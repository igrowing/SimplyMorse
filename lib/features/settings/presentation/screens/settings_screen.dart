import 'dart:async';
import 'package:flutter/material.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';
import 'package:url_launcher/url_launcher.dart';

/// Dedicated settings screen with theme control, Farnsworth
/// timing, display timeout, and app info.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.themeController,
    required this.screenTimeoutService,
    required this.themeMode,
    required this.displayTimeout,
    required this.onDisplayTimeoutChanged,
    super.key,
  });

  final ThemeController themeController;
  final ScreenTimeoutService screenTimeoutService;
  final ThemeMode themeMode;
  final DisplayTimeout displayTimeout;
  final ValueChanged<DisplayTimeout> onDisplayTimeoutChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppTopBar(showSettingsIcon: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle(context, 'Appearance'),
              const SizedBox(height: 12),
              _buildThemeSelector(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Transmission'),
              const SizedBox(height: 12),
              _buildFarnsworthTiming(context),
              const SizedBox(height: 32),
              _buildSectionTitle(context, 'Display'),
              const SizedBox(height: 12),
              _buildDisplayTimeoutSelector(context),
              const SizedBox(height: 48),
              _buildAppInfo(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.themeController,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Theme', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.settings_brightness),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {widget.themeController.mode},
              onSelectionChanged: (selection) {
                widget.themeController.setMode(selection.first);
              },
            ),
          ],
        );
      },
    );
  }

  /// Farnsworth timing switch with an info icon that opens
  /// a dialog explaining what Farnsworth timing is.
  Widget _buildFarnsworthTiming(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: SwitchListTile(
            title: Text(
              'Farnsworth timing',
              style: theme.textTheme.bodyLarge,
            ),
            subtitle: Text(
              'Characters at full speed, extended gaps between characters',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: false, // Will be wired to controller in a follow-up
            onChanged: null, // Disabled until decoder supports it
            contentPadding: EdgeInsets.zero,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.info_outline, size: 22),
          tooltip: 'What is Farnsworth timing?',
          onPressed: () => _showFarnsworthInfoDialog(context),
        ),
      ],
    );
  }

  void _showFarnsworthInfoDialog(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Farnsworth Timing'),
            content: const SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Farnsworth timing is a method used in Morse code '
                    'training and transmission where the individual dits '
                    'and dahs (the "characters") are sent at a higher speed, '
                    'but the gaps between characters and words are extended '
                    'to a slower effective speed.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'For example, at 20/10 Farnsworth, the dits and dahs '
                    'are sent at 20 WPM (60 ms per dit), but the '
                    'inter-character and inter-word gaps are stretched to '
                    'match 10 WPM (360 ms between characters, 840 ms '
                    'between words).',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'This allows a learner to hear characters at full '
                    'speed — developing instant character recognition — '
                    'while having extra time to think between characters.',
                  ),
                  SizedBox(height: 12),
                  Text(
                    'When enabled, SimplyMorse will extend inter-character '
                    'and inter-word gaps according to the Farnsworth method.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDisplayTimeoutSelector(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display lit timeout', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(
          'Controls how long the screen stays on during use',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        // The selection is observed from the service, not from
        // the constructor parameter: pushed routes keep the
        // constructor values captured at push time, so a
        // parameter-driven selection would not refresh when the
        // mode changes while this screen is open.
        ValueListenableBuilder<DisplayTimeout>(
          valueListenable: widget.screenTimeoutService.modeListenable,
          builder: (context, mode, _) {
            return SegmentedButton<DisplayTimeout>(
              segments: const [
                ButtonSegment(
                  value: DisplayTimeout.system,
                  label: Text('System'),
                ),
                ButtonSegment(
                  value: DisplayTimeout.tripleSystem,
                  label: Text('3× System'),
                ),
                ButtonSegment(
                  value: DisplayTimeout.alwaysOn,
                  label: Text('Always on'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selection) {
                widget.onDisplayTimeoutChanged(selection.first);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppInfo(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Text(
          AppConstants.appName,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'v${AppConstants.appVersion}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        _buildCheckUpdatesButton(context),
        const SizedBox(height: 16),
        InkWell(
          onTap: () => _launchCoffeeUrl(context),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.coffee,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Buy me a coffee',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckUpdatesButton(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _checkForUpdates(context),
      icon: const Icon(Icons.system_update, size: 20),
      label: const Text('Check for updates'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: const StadiumBorder(),
      ),
    );
  }

  void _checkForUpdates(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Checking for updates…'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _launchCoffeeUrl(BuildContext context) async {
    final url = Uri.parse(AppConstants.buyMeCoffeeUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
