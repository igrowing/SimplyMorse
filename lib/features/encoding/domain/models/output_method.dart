import 'package:flutter/material.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart'
    show EncodingMode;
import 'package:simply_morse/features/encoding/domain/models/light_method.dart'
    show LightMethod;

/// Output methods for Morse transmission.
///
/// Unlike the old two-level [EncodingMode] + [LightMethod]
/// selection, these three options are independently toggleable
/// in a single multi-select control. Any combination can be
/// active simultaneously.
enum OutputMethod {
  /// Audio beep through the speaker.
  sound,

  /// Hardware torch flash (or emulated LED circle on web).
  led,

  /// Screen display blink — flashes the screen white/black.
  display,
}

/// Display metadata for each [OutputMethod].
extension OutputMethodX on OutputMethod {
  String get label => switch (this) {
    OutputMethod.sound => 'Sound',
    OutputMethod.led => 'LED',
    OutputMethod.display => 'Display',
  };

  IconData get icon => switch (this) {
    OutputMethod.sound => Icons.volume_up,
    OutputMethod.led => Icons.flash_on,
    OutputMethod.display => Icons.phone_android,
  };
}
