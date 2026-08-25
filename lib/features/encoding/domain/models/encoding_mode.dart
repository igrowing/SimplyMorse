import 'package:flutter/material.dart';

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
    EncodingMode.flash => 'Flash LED',
    EncodingMode.both => 'Both',
  };

  IconData get icon => switch (this) {
    EncodingMode.sound => Icons.volume_up,
    EncodingMode.flash => Icons.flash_on,
    EncodingMode.both => Icons.graphic_eq,
  };

  bool get needsTone => switch (this) {
    EncodingMode.sound => true,
    EncodingMode.flash => false,
    EncodingMode.both => true,
  };
}
