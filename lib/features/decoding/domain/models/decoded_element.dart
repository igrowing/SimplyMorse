import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// A single on/off element detected from audio or video input,
/// with its duration in milliseconds.
///
/// [isOn] is `true` for a tone/light (dit or dah) and `false`
/// for a gap (intra-character, inter-character, or word gap).
@immutable
class DecodedElement extends Equatable {
  const DecodedElement({
    required this.isOn,
    required this.durationMs,
  });

  final bool isOn;
  final int durationMs;

  @override
  List<Object?> get props => [isOn, durationMs];
}
