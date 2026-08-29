import 'package:flutter/material.dart';

/// How visual (non-audio) Morse output is produced
/// when the encoding mode includes light.
enum LightMethod {
  /// Hardware torch flash (or emulated LED circle on web).
  flashLed,

  /// Screen display blink — flashes the screen white/black.
  display,

  /// Both hardware torch and screen display blink simultaneously.
  both,
}

/// Display metadata for each [LightMethod].
extension LightMethodX on LightMethod {
  String get label => switch (this) {
    LightMethod.flashLed => 'Flash LED',
    LightMethod.display => 'Display',
    LightMethod.both => 'Both',
  };

  IconData get icon => switch (this) {
    LightMethod.flashLed => Icons.flash_on,
    LightMethod.display => Icons.phone_android,
    LightMethod.both => Icons.lightbulb,
  };

  /// Whether the hardware torch (or web LED emulation) should fire.
  bool get needsTorch => switch (this) {
    LightMethod.flashLed => true,
    LightMethod.display => false,
    LightMethod.both => true,
  };

  /// Whether the screen display should blink.
  bool get needsDisplay => switch (this) {
    LightMethod.flashLed => false,
    LightMethod.display => true,
    LightMethod.both => true,
  };
}
