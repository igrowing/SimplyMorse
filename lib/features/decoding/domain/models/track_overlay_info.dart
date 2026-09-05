import 'package:equatable/equatable.dart';

/// Live tracking telemetry for the See-screen debug overlay.
///
/// Emitted by the video decoder on every processed frame while it
/// is locked on a blinking source — and emitted as `null` the
/// moment the lock is lost or the decoder is reset — so the UI can
/// draw exactly where the brightness-reading region is and what
/// the decoder thinks the current mark is.
///
/// Coordinates are expressed as fractions of the frame (0..1), not
/// pixels, so the presentation layer can map them onto any preview
/// size without knowing the processing resolution.
class TrackOverlayInfo extends Equatable {
  const TrackOverlayInfo({
    required this.centerX,
    required this.centerY,
    required this.regionSizePx,
    required this.signalOn,
    required this.markClassified,
    required this.isDash,
  });

  /// Tracked region center as a fraction of the frame width.
  final double centerX;

  /// Tracked region center as a fraction of the frame height.
  final double centerY;

  /// Side of the brightness-reading region, in processing-frame
  /// pixels (see `VideoDecoder.minRegionSize`).
  final int regionSizePx;

  /// Whether the tracked source is currently ON — a mark is in
  /// progress.
  final bool signalOn;

  /// Whether the live mark classification is available yet. It
  /// needs a dit estimate, which in turn needs a few completed
  /// marks to be robust — until then the UI should show no label
  /// rather than guess.
  final bool markClassified;

  /// Live classification of the mark in progress: `true` once the
  /// running mark duration exceeds twice the dit estimate (the
  /// mark can no longer end as a dit), `false` while it still can.
  /// Only meaningful when [signalOn] and [markClassified] are both
  /// `true`.
  final bool isDash;

  @override
  List<Object?> get props => [
    centerX,
    centerY,
    regionSizePx,
    signalOn,
    markClassified,
    isDash,
  ];
}
