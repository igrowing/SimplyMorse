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

  @override
  List<Object?> get props => [timestampMs, width, height];
}
