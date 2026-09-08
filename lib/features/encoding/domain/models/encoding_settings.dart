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
    this.farnsworthEnabled = false,
    this.farnsworthEffectiveWpm = 10,
  });

  final EncodingMode mode;
  final double speedWpm;
  final double toneHz;
  final LightMethod lightMethod;
  final double initialDelaySec;
  final bool repeatLoop;
  final double repeatDelaySec;

  /// When true, inter-character and inter-word gaps are
  /// stretched Farnsworth-style while marks stay at
  /// [speedWpm] — see [farnsworthEffectiveWpm].
  final bool farnsworthEnabled;

  /// Effective (overall) speed in WPM used while
  /// [farnsworthEnabled] is on. Characters are sent at
  /// [speedWpm]; inter-character and inter-word gaps stretch
  /// so the standard PARIS word lasts 60 / effective WPM
  /// seconds. A value >= [speedWpm] degenerates to standard
  /// ITU timing (no stretching).
  final double farnsworthEffectiveWpm;

  /// Dit duration in milliseconds, derived from WPM.
  /// Based on the PARIS standard: 1 WPM = 1200 ms per dit.
  double get ditMs => 1200 / speedWpm;

  /// Dah duration in milliseconds.
  double get dahMs => 3 * ditMs;

  /// Intra-element gap (between dits/dahs within a character).
  double get intraGapMs => ditMs;

  /// Gap unit in milliseconds under Farnsworth timing, or null
  /// when Farnsworth is off (or degenerate) and standard ITU
  /// timing applies.
  ///
  /// ARRL Farnsworth formula: a PARIS word carries 31 units at
  /// character speed (marks + intra-element gaps) plus 19 gap
  /// units (4 char gaps of 3 + 1 word gap of 7). The gap unit
  /// stretches so the whole word lasts 60 / effective WPM
  /// seconds, while marks and intra-gaps stay at character
  /// speed.
  double? get _farnsworthGapUnitMs {
    if (!farnsworthEnabled || farnsworthEffectiveWpm >= speedWpm) {
      return null;
    }
    final wordSec = 60 / farnsworthEffectiveWpm;
    final charUnitsSec = 31 * ditMs / 1000;
    return (wordSec - charUnitsSec) / 19 * 1000;
  }

  /// Inter-character gap.
  double get charGapMs {
    final unit = _farnsworthGapUnitMs;
    return unit == null ? 3 * ditMs : 3 * unit;
  }

  /// Inter-word gap.
  double get wordGapMs {
    final unit = _farnsworthGapUnitMs;
    return unit == null ? 7 * ditMs : 7 * unit;
  }

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
    bool? farnsworthEnabled,
    double? farnsworthEffectiveWpm,
  }) {
    return EncodingSettings(
      mode: mode ?? this.mode,
      speedWpm: speedWpm ?? this.speedWpm,
      toneHz: toneHz ?? this.toneHz,
      lightMethod: lightMethod ?? this.lightMethod,
      initialDelaySec: initialDelaySec ?? this.initialDelaySec,
      repeatLoop: repeatLoop ?? this.repeatLoop,
      repeatDelaySec: repeatDelaySec ?? this.repeatDelaySec,
      farnsworthEnabled: farnsworthEnabled ?? this.farnsworthEnabled,
      farnsworthEffectiveWpm:
          farnsworthEffectiveWpm ?? this.farnsworthEffectiveWpm,
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
    farnsworthEnabled,
    farnsworthEffectiveWpm,
  ];
}
