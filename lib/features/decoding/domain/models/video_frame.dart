import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// A downsampled grayscale video frame.
///
/// [luminance] contains normalized [0, 1] values in row-major
/// order with dimensions [width] × [height].
@immutable
class VideoFrame extends Equatable {
  const VideoFrame({
    required this.luminance,
    required this.width,
    required this.height,
    required this.timestampMs,
  });

  final List<double> luminance;
  final int width;
  final int height;
  final int timestampMs;

  /// Mean luminance of the entire frame.
  double meanLuminance() {
    if (luminance.isEmpty) return 0;
    var sum = 0.0;
    for (final v in luminance) {
      sum += v;
    }
    return sum / luminance.length;
  }

  /// Mean luminance of a rectangular sub-region.
  double regionMeanLuminance(
    int x,
    int y,
    int w,
    int h,
  ) {
    var sum = 0.0;
    var count = 0;
    final yMax = min(y + h, height);
    final xMax = min(x + w, width);
    for (var row = max(y, 0); row < yMax; row++) {
      for (var col = max(x, 0); col < xMax; col++) {
        final idx = row * width + col;
        if (idx < luminance.length) {
          sum += luminance[idx];
          count++;
        }
      }
    }
    return count > 0 ? sum / count : 0;
  }

  /// Mean luminance of the square annulus between an inner
  /// half-width [innerHalf] and outer half-width [outerHalf],
  /// centered at ([cx], [cy]) — excludes the inner box.
  ///
  /// Used to estimate the ambient level around a tracked source so
  /// its brightness reading can be background-subtracted: camera
  /// auto-exposure/auto-gain moves the whole scene together, so a
  /// beacon region and its immediate surroundings rise and fall in
  /// step even when the beacon itself hasn't changed state.
  /// Subtracting the annulus level cancels that shared drift and
  /// leaves mostly the beacon's own on/off contrast. Returns 0 if the
  /// annulus has no pixels in frame (e.g. a region already touching
  /// the frame edge), so callers get a safe brightness-only fallback.
  double annulusMeanLuminance(
    int cx,
    int cy,
    int innerHalf,
    int outerHalf,
  ) {
    var sum = 0.0;
    var count = 0;
    final yMin = max(cy - outerHalf, 0);
    final yMax = min(cy + outerHalf, height);
    final xMin = max(cx - outerHalf, 0);
    final xMax = min(cx + outerHalf, width);
    for (var row = yMin; row < yMax; row++) {
      final inRowBand = row >= cy - innerHalf && row < cy + innerHalf;
      for (var col = xMin; col < xMax; col++) {
        if (inRowBand && col >= cx - innerHalf && col < cx + innerHalf) {
          continue;
        }
        final idx = row * width + col;
        if (idx < luminance.length) {
          sum += luminance[idx];
          count++;
        }
      }
    }
    return count > 0 ? sum / count : 0;
  }

  @override
  List<Object?> get props => [timestampMs, width, height];
}
