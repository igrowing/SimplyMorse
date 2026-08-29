import 'package:flutter/material.dart';

/// Manages the app's theme mode.
///
/// Supports direct setting to any [ThemeMode] (used by the
/// Settings screen segmented button) and a [cycle] method
/// for quick toggling.
class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  /// Sets the theme mode directly.
  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }

  /// Cycles through system → light → dark → system.
  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    notifyListeners();
  }
}
