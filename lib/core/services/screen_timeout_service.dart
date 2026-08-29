import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Display lit timeout modes.
enum DisplayTimeout { system, tripleSystem, alwaysOn }

/// Controls how long the screen stays lit.
///
/// - [DisplayTimeout.system]: uses the system default timeout.
/// - [DisplayTimeout.tripleSystem]: keeps the screen on, but
///   releases the wakelock after 90 seconds of inactivity
///   (approximately 3× a typical 30-second system timeout).
/// - [DisplayTimeout.alwaysOn]: keeps the screen on permanently.
class ScreenTimeoutService {
  DisplayTimeout _mode = DisplayTimeout.system;
  Timer? _inactivityTimer;
  static const _tripleSystemTimeoutSec = 90;

  DisplayTimeout get mode => _mode;

  /// Sets the display timeout mode and applies it immediately.
  Future<void> setMode(DisplayTimeout mode) async {
    _mode = mode;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    switch (mode) {
      case DisplayTimeout.system:
        await WakelockPlus.disable();
      case DisplayTimeout.tripleSystem:
        await WakelockPlus.enable();
        _startInactivityTimer();
      case DisplayTimeout.alwaysOn:
        await WakelockPlus.enable();
    }
  }

  /// Notifies the service of user activity (tap, scroll, etc.).
  /// Resets the inactivity timer for [DisplayTimeout.tripleSystem].
  void onUserActivity() {
    if (_mode == DisplayTimeout.tripleSystem) {
      _startInactivityTimer();
    }
  }

  void _startInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(
      const Duration(seconds: _tripleSystemTimeoutSec),
      (_) async {
        await WakelockPlus.disable();
        _inactivityTimer?.cancel();
      },
    );
  }

  /// Disposes resources.
  void dispose() {
    _inactivityTimer?.cancel();
  }

  /// Parses a string mode into [DisplayTimeout].
  static DisplayTimeout fromString(String value) {
    return switch (value) {
      '3x' => DisplayTimeout.tripleSystem,
      'always' => DisplayTimeout.alwaysOn,
      _ => DisplayTimeout.system,
    };
  }

  /// Converts [DisplayTimeout] to a storage string.
  static String modeToString(DisplayTimeout mode) {
    return switch (mode) {
      DisplayTimeout.system => 'system',
      DisplayTimeout.tripleSystem => '3x',
      DisplayTimeout.alwaysOn => 'always',
    };
  }
}
