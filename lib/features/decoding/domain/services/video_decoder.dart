import 'dart:math';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';

/// State of the video decoding pipeline.
enum VideoDecoderState {
  /// Accumulating frames and computing temporal variance.
  scanning,

  /// Candidate region found — confirming across frames.
  confirming,

  /// Locked on a blinking region — tracking brightness.
  locked,
}

/// Video decoding pipeline for visual Morse code detection.
///
/// Implements the approach described in the SimplyMorse spec:
///
/// 1. Capture in low-res, locked-exposure mode (handled by
///    the [CameraCapture] implementation).
/// 2. Preprocess: convert to grayscale luminance (done by
///    the camera capture, frames arrive as [VideoFrame]).
/// 3. Detect candidate blinking region via per-block temporal
///    variance over a rolling window.
/// 4. Confirm before locking: same region across several
///    frames.
/// 5. Lock and track: read mean brightness of the region,
///    apply hysteresis threshold for on/off detection.
/// 6. Extract on/off timing and emit [DecodedElement]s.
/// 7. Periodic re-scan if the signal is lost.
class VideoDecoder {
  VideoDecoder({
    this.blockSize = 8,
    this.confirmFrames = 3,
    this.historySize = 30,
    this.rescanIntervalMs = 2000,
    this.minVariance = 0.001,
    BrightnessThreshold? threshold,
  }) : _threshold = threshold ?? BrightnessThreshold();

  // Configuration
  final int blockSize;
  final int confirmFrames;
  final int historySize;
  final int rescanIntervalMs;
  final double minVariance;

  // Components
  final BrightnessThreshold _threshold;

  // State machine
  VideoDecoderState _state = VideoDecoderState.scanning;
  VideoDecoderState get state => _state;

  // Frame history for temporal variance
  final List<VideoFrame> _history = [];

  // Candidate / locked region
  int _regionX = 0;
  int _regionY = 0;
  int _regionW = 0;
  int _regionH = 0;
  bool _isFullFrame = false;
  int _confirmCount = 0;

  // Timing
  int _transitionMs = 0;

  // Re-scan timer
  int _lastScanMs = 0;

  // Output
  void Function(DecodedElement element)? onElement;

  /// Processes a single video frame.
  void processFrame(VideoFrame frame) {
    switch (_state) {
      case VideoDecoderState.scanning:
        _scan(frame);
      case VideoDecoderState.confirming:
        _confirm(frame);
      case VideoDecoderState.locked:
        _track(frame);
    }
  }

  // -- Scanning --------------------------------------------------

  void _scan(VideoFrame frame) {
    _addToHistory(frame);
    if (_history.length < 10) return;

    final blocksX = frame.width ~/ blockSize;
    final blocksY = frame.height ~/ blockSize;
    if (blocksX == 0 || blocksY == 0) return;

    var maxVariance = 0.0;
    var maxBx = 0;
    var maxBy = 0;
    final variances = <double>[];

    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        final v = _blockVariance(bx, by);
        variances.add(v);
        if (v > maxVariance) {
          maxVariance = v;
          maxBx = bx;
          maxBy = by;
        }
      }
    }

    if (maxVariance < minVariance) return;

    final meanVariance = variances.reduce((a, b) => a + b) / variances.length;

    if (maxVariance < meanVariance * 2) {
      // Full-frame blink — use the whole frame
      _isFullFrame = true;
      _regionX = 0;
      _regionY = 0;
      _regionW = frame.width;
      _regionH = frame.height;
    } else {
      // Localized blink — use the block
      _isFullFrame = false;
      _regionX = maxBx * blockSize;
      _regionY = maxBy * blockSize;
      _regionW = blockSize;
      _regionH = blockSize;
    }

    _confirmCount = 1;
    _state = VideoDecoderState.confirming;
  }

  // -- Confirming ------------------------------------------------

  void _confirm(VideoFrame frame) {
    _addToHistory(frame);

    final v = _regionVariance();
    final meanV = _meanVariance();

    final threshold = _isFullFrame ? minVariance : meanV * 2;

    if (v > threshold) {
      _confirmCount++;
      if (_confirmCount >= confirmFrames) {
        _state = VideoDecoderState.locked;
        _threshold.reset();
        _lastScanMs = frame.timestampMs;
        _transitionMs = frame.timestampMs;
      }
    } else {
      _state = VideoDecoderState.scanning;
      _confirmCount = 0;
    }
  }

  // -- Tracking --------------------------------------------------

  void _track(VideoFrame frame) {
    // Keep history fresh so re-scan variance reflects
    // current conditions, not stale frames from lock time.
    _addToHistory(frame);

    final brightness = frame.regionMeanLuminance(
      _regionX,
      _regionY,
      _regionW,
      _regionH,
    );

    final wasOn = _threshold.isOn;
    final isOn = _threshold.process(brightness);

    if (isOn != wasOn) {
      _emitElement(wasOn, frame.timestampMs);
    }

    // Periodic re-scan
    if (frame.timestampMs - _lastScanMs > rescanIntervalMs) {
      _checkSignal(frame);
    }
  }

  void _checkSignal(VideoFrame frame) {
    // Frame already added to history by _track.
    final v = _regionVariance();

    if (v < minVariance) {
      // Signal lost — flush and re-scan
      if (_threshold.isOn) {
        _emitElement(true, frame.timestampMs);
      }
      _threshold.reset();
      _state = VideoDecoderState.scanning;
    }

    _lastScanMs = frame.timestampMs;
  }

  // -- Helpers ---------------------------------------------------

  void _addToHistory(VideoFrame frame) {
    _history.add(frame);
    if (_history.length > historySize) {
      _history.removeAt(0);
    }
  }

  double _blockVariance(int bx, int by) {
    final startX = bx * blockSize;
    final startY = by * blockSize;

    final means = <double>[];
    for (final frame in _history) {
      means.add(
        frame.regionMeanLuminance(
          startX,
          startY,
          blockSize,
          blockSize,
        ),
      );
    }

    if (means.isEmpty) return 0;

    final avg = means.reduce((a, b) => a + b) / means.length;
    var varSum = 0.0;
    for (final m in means) {
      varSum += (m - avg) * (m - avg);
    }
    return varSum / means.length;
  }

  double _regionVariance() {
    final means = <double>[];
    for (final frame in _history) {
      means.add(
        frame.regionMeanLuminance(
          _regionX,
          _regionY,
          _regionW,
          _regionH,
        ),
      );
    }

    if (means.isEmpty) return 0;

    final avg = means.reduce((a, b) => a + b) / means.length;
    var varSum = 0.0;
    for (final m in means) {
      varSum += (m - avg) * (m - avg);
    }
    return varSum / means.length;
  }

  double _meanVariance() {
    final frame = _history.last;
    final blocksX = frame.width ~/ blockSize;
    final blocksY = frame.height ~/ blockSize;
    if (blocksX == 0 || blocksY == 0) return 0;

    var sum = 0.0;
    var count = 0;
    for (var by = 0; by < blocksY; by++) {
      for (var bx = 0; bx < blocksX; bx++) {
        sum += _blockVariance(bx, by);
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  void _emitElement(bool isOn, int timestampMs) {
    final durationMs = timestampMs - _transitionMs;
    if (durationMs <= 0) return;
    onElement?.call(
      DecodedElement(isOn: isOn, durationMs: durationMs),
    );
    _transitionMs = timestampMs;
  }

  /// Resets the decoder to the scanning state.
  void reset() {
    _state = VideoDecoderState.scanning;
    _history.clear();
    _threshold.reset();
    _confirmCount = 0;
    _transitionMs = 0;
    _lastScanMs = 0;
    _isFullFrame = false;
  }
}
