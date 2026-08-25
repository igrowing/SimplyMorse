import 'package:flutter/material.dart';

/// Manages the app's theme mode with a three-state cycle:
/// system → light → dark → system.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    notifyListeners();
  }
}
