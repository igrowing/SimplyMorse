import 'dart:math';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/alpha_beta_filter.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';

/// Debug callback for scanning frames.
typedef DebugVideoScanCallback =
    void Function({
      required int timestampMs,
      required double maxVariance,
      required double meanVariance,
      required int frameCount,
    });

/// Debug callback for confirming frames.
typedef DebugVideoConfirmCallback =
    void Function({
      required int timestampMs,
      required double variance,
      required int confirmCount,
      required double filterX,
      required double filterY,
    });

/// Debug callback for tracking frames.
typedef DebugVideoTrackCallback =
    void Function({
      required int timestampMs,
      required double variance,
      required double brightness,
      required double minBrightness,
      required double maxBrightness,
      required double range,
      required double onThreshold,
      required double offThreshold,
      required bool isOn,
      required int regionX,
      required int regionY,
      required int regionSize,
      required double innovation,
    });

/// Debug callback for video transitions.
typedef DebugVideoTransitionCallback =
    void Function({
      required int timestampMs,
      required bool isOn,
      required int durationMs,
    });

/// Debug callback for signal loss.
typedef DebugVideoSignalLostCallback =
    void Function({
      required int timestampMs,
      required int lostFrameCount,
    });

/// Debug callback for state changes.
typedef DebugVideoStateChangeCallback =
    void Function({
      required int timestampMs,
      required String newState,
      String? detail,
    });

/// State of the video decoding pipeline.
enum VideoDecoderState {
  /// Accumulating frames and computing temporal variance.
  scanning,

  /// Candidate region found — confirming across frames.
  confirming,

  /// Locked on a blinking region — tracking brightness.
  locked,
}

/// Video decoding pipeline with motion compensation.
///
/// Implements the approach described in the SimplyMorse spec:
///
/// 1. **Scanning**: Compute per-block temporal variance to
///    find a blinking source. Detects both localized blinks
///    (one block) and full-frame blinks.
///
/// 2. **Confirming**: Verify the candidate persists across
///    [confirmFrames] frames using a local search window
///    around the predicted position (via the α-β filter).
///
/// 3. **Tracking (locked)**: Continuously re-find the source
///    within a search window around the α-β filter's
///    prediction. The filter smooths hand shaking (high-
///    frequency oscillation) and tracks steady drift (slide).
///    The brightness-reading region adapts to the filter's
///    [AlphaBetaFilter.innovation] — it grows when the source
///    moves unpredictably and shrinks when stable.
///
/// 4. **Signal loss**: If the peak variance in the search
///    window drops below [minVariance] for [lostFrameLimit]
///    consecutive frames, returns to scanning.
///
/// **Motion handling:**
/// - **Hand shaking**: The α filter coefficient smooths the
///   oscillation → region stays centered on the mean →
///   brightness reading is stable.
/// - **Sliding/drift**: The β filter coefficient estimates
///   velocity → predicts next position → region follows.
/// - **Combination**: Both α and β work together to track
///   the smoothed trajectory.
class VideoDecoder {
  VideoDecoder({
    this.blockSize = 8,
    this.confirmFrames = 3,
    this.historySize = 30,
    this.historyDecay = 0.95,
    this.rescanIntervalMs = 2000,
    this.minVariance = 0.001,
    this.searchRadius = 2,
    this.lostFrameLimit = 10,
    this.minRegionSize = 8,
    this.maxRegionSize = 32,
    BrightnessThreshold? threshold,
    AlphaBetaFilter? filter,
  }) : _threshold = threshold ?? BrightnessThreshold(),
       _filter = filter ?? AlphaBetaFilter();

  // Configuration
  final int blockSize;
  final int confirmFrames;
  final int historySize;
  final double historyDecay;
  final int rescanIntervalMs;
  final double minVariance;

  /// Search radius in blocks around the predicted position.
  final int searchRadius;

  /// Consecutive low-variance frames before signal loss.
  final int lostFrameLimit;

  /// Minimum brightness-reading region size (pixels).
  final int minRegionSize;

  /// Maximum brightness-reading region size (pixels).
  final int maxRegionSize;

  // Components
  final BrightnessThreshold _threshold;
  final AlphaBetaFilter _filter;

  // State machine
  VideoDecoderState _state = VideoDecoderState.scanning;
  VideoDecoderState get state => _state;

  // Frame history for temporal variance
  final List<VideoFrame> _history = [];

  // Candidate / locked region (block coordinates)
  bool _isFullFrame = false;
  int _confirmCount = 0;

  // Timing
  int _transitionMs = 0;
  int _lastFrameMs = 0;

  // Signal loss counter
  int _lostFrameCount = 0;

  // Output
  void Function(DecodedElement element)? onElement;

  // -- Debug callbacks --
  DebugVideoScanCallback? onDebugScan;
  DebugVideoConfirmCallback? onDebugConfirm;
  DebugVideoTrackCallback? onDebugTrack;
  DebugVideoTransitionCallback? onDebugTransition;
  DebugVideoSignalLostCallback? onDebugSignalLost;
  DebugVideoStateChangeCallback? onDebugStateChange;

  /// Exposes current brightness-threshold internals for logging.
  double get _brightnessMin => _threshold.minBrightness;
  double get _brightnessMax => _threshold.maxBrightness;
  double get _brightnessRange => _threshold.range;

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

    if (maxVariance < minVariance) {
      onDebugScan?.call(
        timestampMs: frame.timestampMs,
        maxVariance: maxVariance,
        meanVariance: 0,
        frameCount: _history.length,
      );
      return;
    }

    final meanVariance = variances.reduce((a, b) => a + b) / variances.length;

    onDebugScan?.call(
      timestampMs: frame.timestampMs,
      maxVariance: maxVariance,
      meanVariance: meanVariance,
      frameCount: _history.length,
    );

    if (maxVariance < meanVariance * 2) {
      _isFullFrame = true;
    } else {
      _isFullFrame = false;
    }

    // Initialize α-β filter at the detected region center
    final centerX = _isFullFrame
        ? frame.width / 2
        : maxBx * blockSize + blockSize / 2.0;
    final centerY = _isFullFrame
        ? frame.height / 2
        : maxBy * blockSize + blockSize / 2.0;
    _filter.initialize(centerX, centerY);

    _confirmCount = 1;
    _lostFrameCount = 0;
    _lastFrameMs = frame.timestampMs;
    _state = VideoDecoderState.confirming;
  }

  // -- Confirming ------------------------------------------------

  void _confirm(VideoFrame frame) {
    _addToHistory(frame);

    final dt = _computeDt(frame.timestampMs);
    _filter.predict(dt);

    final result = _searchPeakVariance(frame);

    if (result.variance > minVariance) {
      _filter.update(result.centerX, result.centerY, dt);
      _lostFrameCount = 0;
      _confirmCount++;
      onDebugConfirm?.call(
        timestampMs: frame.timestampMs,
        variance: result.variance,
        confirmCount: _confirmCount,
        filterX: _filter.x,
        filterY: _filter.y,
      );
      if (_confirmCount >= confirmFrames) {
        _state = VideoDecoderState.locked;
        _threshold.reset();
        _transitionMs = frame.timestampMs;
        onDebugStateChange?.call(
          timestampMs: frame.timestampMs,
          newState: 'locked',
        );
      }
    } else {
      _lostFrameCount++;
      if (_lostFrameCount >= lostFrameLimit) {
        _signalLost();
      }
    }

    _lastFrameMs = frame.timestampMs;
  }

  // -- Tracking --------------------------------------------------

  void _track(VideoFrame frame) {
    _addToHistory(frame);

    final dt = _computeDt(frame.timestampMs);
    _filter.predict(dt);

    final result = _searchPeakVariance(frame);

    if (result.variance > minVariance) {
      _filter.update(result.centerX, result.centerY, dt);
      _lostFrameCount = 0;

      // Read brightness from the tracked region.
      // Region size adapts to filter innovation — grows
      // when the source moves unpredictably.
      final regionSize = (_filter.innovation * 2)
          .clamp(
            minRegionSize.toDouble(),
            maxRegionSize.toDouble(),
          )
          .round();

      final cx = _filter.x.round();
      final cy = _filter.y.round();
      final half = regionSize ~/ 2;

      final brightness = frame.regionMeanLuminance(
        cx - half,
        cy - half,
        regionSize,
        regionSize,
      );

      final wasOn = _threshold.isOn;
      final isOn = _threshold.process(
        brightness,
        timestampMs: frame.timestampMs,
      );
      onDebugTrack?.call(
        timestampMs: frame.timestampMs,
        variance: result.variance,
        brightness: brightness,
        minBrightness: _brightnessMin,
        maxBrightness: _brightnessMax,
        range: _brightnessRange,
        onThreshold: _brightnessMin + _brightnessRange * _threshold.onFactor,
        offThreshold: _brightnessMin + _brightnessRange * _threshold.offFactor,
        isOn: isOn,
        regionX: cx,
        regionY: cy,
        regionSize: regionSize,
        innovation: _filter.innovation,
      );
      if (isOn != wasOn) {
        _emitElement(wasOn, frame.timestampMs);
      }
    } else {
      _lostFrameCount++;
      if (_lostFrameCount >= lostFrameLimit) {
        _signalLost();
      }
    }

    _lastFrameMs = frame.timestampMs;
  }

  // -- Signal loss -----------------------------------------------

  void _signalLost() {
    if (_threshold.isOn) {
      _emitElement(true, _lastFrameMs);
    }
    onDebugSignalLost?.call(
      timestampMs: _lastFrameMs,
      lostFrameCount: _lostFrameCount,
    );
    onDebugStateChange?.call(
      timestampMs: _lastFrameMs,
      newState: 'scanning',
      detail: 'signal_lost',
    );
    _threshold.reset();
    _filter.reset();
    _state = VideoDecoderState.scanning;
    _confirmCount = 0;
    _lostFrameCount = 0;
  }

  // -- Search ----------------------------------------------------

  /// Result of a local variance search.
  static const _emptyResult = _SearchResult(
    variance: 0,
    centerX: 0,
    centerY: 0,
  );

  _SearchResult _searchPeakVariance(VideoFrame frame) {
    if (_isFullFrame) {
      // Full-frame blink — no need to search
      return _SearchResult(
        variance: _blockVariance(0, 0),
        centerX: frame.width / 2,
        centerY: frame.height / 2,
      );
    }

    final blocksX = frame.width ~/ blockSize;
    final blocksY = frame.height ~/ blockSize;
    if (blocksX == 0 || blocksY == 0) return _emptyResult;

    // Convert filter position to block coordinates
    final predBx = (_filter.x / blockSize).round();
    final predBy = (_filter.y / blockSize).round();

    final minBx = max(0, predBx - searchRadius);
    final maxBx = min(blocksX - 1, predBx + searchRadius);
    final minBy = max(0, predBy - searchRadius);
    final maxBy = min(blocksY - 1, predBy + searchRadius);

    var maxVariance = 0.0;
    var maxBxResult = predBx;
    var maxByResult = predBy;

    for (var by = minBy; by <= maxBy; by++) {
      for (var bx = minBx; bx <= maxBx; bx++) {
        final v = _blockVariance(bx, by);
        if (v > maxVariance) {
          maxVariance = v;
          maxBxResult = bx;
          maxByResult = by;
        }
      }
    }

    return _SearchResult(
      variance: maxVariance,
      centerX: maxBxResult * blockSize + blockSize / 2.0,
      centerY: maxByResult * blockSize + blockSize / 2.0,
    );
  }

  // -- Helpers ---------------------------------------------------

  double _computeDt(int timestampMs) {
    final dt = _lastFrameMs > 0 ? (timestampMs - _lastFrameMs) / 1000.0 : 0.033;
    return dt > 0 ? dt : 0.033;
  }

  void _addToHistory(VideoFrame frame) {
    _history.add(frame);
    if (_history.length > historySize) {
      _history.removeAt(0);
    }
  }

  /// Computes exponentially-weighted temporal variance of
  /// a block across the frame history.
  ///
  /// Recent frames contribute more (weight =
  /// [historyDecay]^age), so the variance reflects the
  /// *current* source position rather than the average over
  /// the whole window.
  double _blockVariance(int bx, int by) {
    final startX = bx * blockSize;
    final startY = by * blockSize;

    final n = _history.length;
    if (n == 0) return 0;

    var totalWeight = 0.0;
    var weightedMean = 0.0;

    for (var i = 0; i < n; i++) {
      final w = pow(historyDecay, n - 1 - i).toDouble();
      final m = _history[i].regionMeanLuminance(
        startX,
        startY,
        blockSize,
        blockSize,
      );
      totalWeight += w;
      weightedMean += w * m;
    }
    weightedMean /= totalWeight;

    var varSum = 0.0;
    for (var i = 0; i < n; i++) {
      final w = pow(historyDecay, n - 1 - i).toDouble();
      final m = _history[i].regionMeanLuminance(
        startX,
        startY,
        blockSize,
        blockSize,
      );
      varSum += w * (m - weightedMean) * (m - weightedMean);
    }
    return varSum / totalWeight;
  }

  void _emitElement(bool isOn, int timestampMs) {
    final durationMs = timestampMs - _transitionMs;
    if (durationMs <= 0) return;
    onDebugTransition?.call(
      timestampMs: timestampMs,
      isOn: isOn,
      durationMs: durationMs,
    );
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
    _filter.reset();
    _confirmCount = 0;
    _lostFrameCount = 0;
    _transitionMs = 0;
    _lastFrameMs = 0;
    _isFullFrame = false;
  }
}

/// Internal result of a local variance search.
class _SearchResult {
  const _SearchResult({
    required this.variance,
    required this.centerX,
    required this.centerY,
  });

  final double variance;
  final double centerX;
  final double centerY;
}
