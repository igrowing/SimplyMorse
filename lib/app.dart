import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/app_theme.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/domain/repositories/settings_repository.dart';
import 'package:simply_morse/features/main/presentation/main_screen.dart';

/// Root widget for the SimplyMorse application.
class SimplyMorseApp extends StatefulWidget {
  const SimplyMorseApp({super.key});

  @override
  State<SimplyMorseApp> createState() => _SimplyMorseAppState();
}

class _SimplyMorseAppState extends State<SimplyMorseApp> {
  late final ThemeController _themeController;
  late final ScreenTimeoutService _screenTimeoutService;
  DisplayTimeout _displayTimeout = DisplayTimeout.system;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _themeController = GetIt.instance<ThemeController>();
    _screenTimeoutService = GetIt.instance<ScreenTimeoutService>();
    unawaited(_loadDisplayTimeout());
  }

  Future<void> _loadDisplayTimeout() async {
    final repo = GetIt.instance<SettingsRepository>();
    final stored = await repo.getDisplayTimeout();
    _displayTimeout = ScreenTimeoutService.fromString(stored);
    await _screenTimeoutService.setMode(_displayTimeout);
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  Future<void> _onDisplayTimeoutChanged(DisplayTimeout mode) async {
    _displayTimeout = mode;
    await _screenTimeoutService.setMode(mode);
    final repo = GetIt.instance<SettingsRepository>();
    await repo.saveDisplayTimeout(ScreenTimeoutService.modeToString(mode));
    if (mounted) setState(() {});
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
          home: _initialized
              ? MainScreen(
                  themeController: _themeController,
                  screenTimeoutService: _screenTimeoutService,
                  displayTimeout: _displayTimeout,
                  onDisplayTimeoutChanged: _onDisplayTimeoutChanged,
                )
              : const _SplashScreen(),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Image(
              image: AssetImage('assets/SimplyMorse_icon1024.png'),
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 16),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
      ),
    );
  }
}
