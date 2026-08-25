import 'package:flutter/material.dart';

import 'package:simply_morse/features/decoding/presentation/screens/receive_screen.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

/// Main screen with two large buttons: Send and Receive.
class MainScreen extends StatelessWidget {
  const MainScreen({
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 500,
              ),
              child: isWide
                  ? Row(children: _mainButtons(context))
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _mainButtons(context),
                    ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _mainButtons(BuildContext context) {
    return [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _MainButton(
            icon: Icons.send,
            label: 'Send',
            onTap: () => _navigateToSend(context),
          ),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _MainButton(
            icon: Icons.download,
            label: 'Receive',
            onTap: () => _navigateToReceive(context),
          ),
        ),
      ),
    ];
  }

  void _navigateToSend(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          themeMode: themeMode,
          onThemeToggle: onThemeToggle,
        ),
      ),
    );
  }

  void _navigateToReceive(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiveScreen(
          themeMode: themeMode,
          onThemeToggle: onThemeToggle,
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
    final theme = Theme.of(context);
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 32),
      label: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          label,
          style: theme.textTheme.titleLarge,
        ),
      ),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(120),
      ),
    );
  }
}
