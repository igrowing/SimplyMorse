import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';

/// Holds all settings for an encoding session.
@immutable
class EncodingSettings extends Equatable {
  const EncodingSettings({
    required this.mode,
    required this.speedWpm,
    required this.toneHz,
    this.lightMethod = LightMethod.flashLed,
    this.initialDelaySec = 1.0,
    this.repeatLoop = false,
    this.repeatDelaySec = 2.0,
  });

  final EncodingMode mode;
  final double speedWpm;
  final double toneHz;
  final LightMethod lightMethod;
  final double initialDelaySec;
  final bool repeatLoop;
  final double repeatDelaySec;

  /// Dit duration in milliseconds, derived from WPM.
  /// Based on the PARIS standard: 1 WPM = 1200 ms per dit.
  double get ditMs => 1200 / speedWpm;

  /// Dah duration in milliseconds.
  double get dahMs => 3 * ditMs;

  /// Intra-element gap (between dits/dahs within a character).
  double get intraGapMs => ditMs;

  /// Inter-character gap.
  double get charGapMs => 3 * ditMs;

  /// Inter-word gap.
  double get wordGapMs => 7 * ditMs;

  /// Whether this mode uses audio output.
  bool get needsAudio =>
      mode == EncodingMode.sound || mode == EncodingMode.both;

  /// Whether this mode uses the hardware torch / web LED.
  bool get needsTorch => mode.needsLight && lightMethod.needsTorch;

  /// Whether this mode uses screen display blink.
  bool get needsDisplay => mode.needsLight && lightMethod.needsDisplay;

  EncodingSettings copyWith({
    EncodingMode? mode,
    double? speedWpm,
    double? toneHz,
    LightMethod? lightMethod,
    double? initialDelaySec,
    bool? repeatLoop,
    double? repeatDelaySec,
  }) {
    return EncodingSettings(
      mode: mode ?? this.mode,
      speedWpm: speedWpm ?? this.speedWpm,
      toneHz: toneHz ?? this.toneHz,
      lightMethod: lightMethod ?? this.lightMethod,
      initialDelaySec: initialDelaySec ?? this.initialDelaySec,
      repeatLoop: repeatLoop ?? this.repeatLoop,
      repeatDelaySec: repeatDelaySec ?? this.repeatDelaySec,
    );
  }

  @override
  List<Object?> get props => [
    mode,
    speedWpm,
    toneHz,
    lightMethod,
    initialDelaySec,
    repeatLoop,
    repeatDelaySec,
  ];
}
