import 'package:flutter/material.dart';
import 'package:simply_morse/core/theme/app_theme.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/main/presentation/main_screen.dart';

/// Root widget for the SimplyMorse application.
class SimplyMorseApp extends StatefulWidget {
  const SimplyMorseApp({super.key});

  @override
  State<SimplyMorseApp> createState() => _SimplyMorseAppState();
}

class _SimplyMorseAppState extends State<SimplyMorseApp> {
  final _themeController = ThemeController();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'SimplyMorse',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: _themeController.mode,
          home: MainScreen(
            themeMode: _themeController.mode,
            onThemeToggle: _themeController.cycle,
          ),
        );
      },
    );
  }
}
