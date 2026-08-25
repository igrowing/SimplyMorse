import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';

/// Holds all settings for an encoding session.
@immutable
class EncodingSettings extends Equatable {
  const EncodingSettings({
    required this.mode,
    required this.speedWpm,
    required this.toneHz,
  });

  final EncodingMode mode;
  final double speedWpm;
  final double toneHz;

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

  EncodingSettings copyWith({
    EncodingMode? mode,
    double? speedWpm,
    double? toneHz,
  }) {
    return EncodingSettings(
      mode: mode ?? this.mode,
      speedWpm: speedWpm ?? this.speedWpm,
      toneHz: toneHz ?? this.toneHz,
    );
  }

  @override
  List<Object?> get props => [mode, speedWpm, toneHz];
}
