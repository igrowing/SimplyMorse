import 'package:flutter/material.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart'
    show LightMethod;

/// The three encoding transmission modes.
enum EncodingMode {
  sound,
  flash,
  both,
}

/// Extension providing display metadata for each mode.
extension EncodingModeX on EncodingMode {
  String get label => switch (this) {
    EncodingMode.sound => 'Sound',
    EncodingMode.flash => 'Light',
    EncodingMode.both => 'Both',
  };

  IconData get icon => switch (this) {
    EncodingMode.sound => Icons.volume_up,
    EncodingMode.flash => Icons.lightbulb,
    EncodingMode.both => Icons.graphic_eq,
  };

  /// Whether this mode produces audio (needs a tone frequency).
  bool get needsTone => switch (this) {
    EncodingMode.sound => true,
    EncodingMode.flash => false,
    EncodingMode.both => true,
  };

  /// Whether this mode produces visual output (needs a
  /// [LightMethod] sub-selector).
  bool get needsLight => switch (this) {
    EncodingMode.sound => false,
    EncodingMode.flash => true,
    EncodingMode.both => true,
  };
}
