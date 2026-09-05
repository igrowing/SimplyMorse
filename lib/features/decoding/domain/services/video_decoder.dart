import 'dart:math';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/alpha_beta_filter.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

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

/// Receives live tracking telemetry for the See-screen debug
/// overlay on every locked frame, and `null` the moment the lock
/// is lost or the decoder resets.
typedef TrackOverlayCallback = void Function(TrackOverlayInfo? info);

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
/// 1. **Scanning**: Compute per-block temporal variance inside the
///    central target area (see [targetAreaFraction]) to find a
///    blinking source the user has aimed at. Detects both localized
///    blinks (one block) and full-frame blinks.
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
    this.backgroundMarginPx = 8,
    this.targetAreaFraction = defaultTargetAreaFraction,
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

  /// Extra pixels beyond the brightness-reading region's own radius
  /// that make up the background annulus used to cancel shared
  /// auto-exposure drift. See the background-subtraction comment in
  /// [_track].
  final int backgroundMarginPx;

  /// Side of the central target area as a fraction of the smaller
  /// frame dimension.
  ///
  /// The user aims the camera so the transmitting light sits inside
  /// the on-screen target reticle; scanning and tracking are then
  /// confined to that central square. This both cuts the per-frame
  /// search from every block to a handful and — more importantly —
  /// ignores blinking sources outside the reticle (car indicators,
  /// screens, ceiling lights) that previously competed for the lock.
  ///
  /// Must stay in sync with the reticle drawn on the See screen,
  /// which renders [defaultTargetAreaFraction] of the preview.
  final double targetAreaFraction;

  /// Default target area — see [targetAreaFraction].
  static const double defaultTargetAreaFraction = 0.4;

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
  int _lastFrameMs = 0;

  // Signal loss counter
  int _lostFrameCount = 0;

  // Output
  void Function(DecodedElement element)? onElement;

  /// See-screen debug overlay telemetry — see
  /// [TrackOverlayCallback].
  TrackOverlayCallback? onTrackOverlay;

  // Live mark timing for the debug overlay. Kept here — not in
  // the presentation layer — because the overlay label must
  // classify the mark *in progress*, which only the decoder can
  // see: the element stream lags by one transition and the lock
  // gate filters slow streams, so deriving it downstream would
  // show stale or missing marks.
  int _markStartMs = -1;
  final List<int> _markDurationsMs = [];
  double _ditEstimateMs = 0;
  static const int _maxMarkSamples = 24;
  static const int _minMarkSamples = 3;

  /// Confirms genuinely Morse-timed elements before they reach
  /// [_emit] — for slow sending only. Video's scan/confirm phase
  /// checks that a source blinks with high temporal variance, not
  /// that it blinks with *Morse* timing, so camera autoexposure
  /// settling or a sender-side countdown UI locks on and reads just
  /// as readily as a real beacon. See [MorseLockGate] for why this
  /// only filters slow sending and passes fast sending straight
  /// through untouched.
  late final MorseLockGate _lockGate = MorseLockGate(onElement: _emit);

  /// Turns on/off transitions into elements, merging glitches and
  /// holding the last element until [flush]. Shared with the audio
  /// decoder so both paths treat short segments the same way.
  late final ElementBuilder _builder = ElementBuilder(
    onElement: _lockGate.add,
  );

  void _emit(DecodedElement element) {
    onDebugTransition?.call(
      timestampMs: _lastFrameMs,
      isOn: element.isOn,
      durationMs: element.durationMs,
    );
    onElement?.call(element);
  }

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

    final range = _targetBlockRange(frame);
    for (var by = range.minBy; by <= range.maxBy; by++) {
      for (var bx = range.minBx; bx <= range.maxBx; bx++) {
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
        _builder.reset();
        _lockGate.reset();
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

      final rawBrightness = frame.regionMeanLuminance(
        cx - half,
        cy - half,
        regionSize,
        regionSize,
      );

      // Background-subtract for a localized source: camera
      // auto-exposure moves the whole scene together, so the region
      // around the beacon rises and falls with it even when the
      // beacon itself hasn't changed state — this was measured
      // corrupting BrightnessThreshold's min/max tracking on AE-heavy
      // reference recordings. Subtracting the surrounding annulus'
      // level cancels that shared drift. Skipped for a full-frame
      // blink, where the annulus flashes in phase with the region and
      // subtracting it would cancel the *signal*, not just drift.
      final brightness = _isFullFrame
          ? rawBrightness
          : rawBrightness -
                frame.annulusMeanLuminance(
                  cx,
                  cy,
                  half,
                  half + backgroundMarginPx,
                );

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
      _updateOverlayTelemetry(
        frame: frame,
        isOn: isOn,
        cx: cx,
        cy: cy,
        regionSize: regionSize,
      );

      _builder.transition(
        nowOn: isOn,
        timeMs: _threshold.effectiveTransitionMs,
      );
    } else {
      _lostFrameCount++;
      if (_lostFrameCount >= lostFrameLimit) {
        _signalLost();
      }
    }

    _lastFrameMs = frame.timestampMs;
  }

  // -- Debug overlay telemetry ------------------------------------

  /// Feeds [onTrackOverlay] with the current lock position and
  /// the live classification of the mark in progress.
  void _updateOverlayTelemetry({
    required VideoFrame frame,
    required bool isOn,
    required int cx,
    required int cy,
    required int regionSize,
  }) {
    // Track mark boundaries directly from the threshold state.
    if (isOn && _markStartMs < 0) {
      _markStartMs = frame.timestampMs;
    } else if (!isOn && _markStartMs >= 0) {
      _markDurationsMs.add(frame.timestampMs - _markStartMs);
      if (_markDurationsMs.length > _maxMarkSamples) {
        _markDurationsMs.removeAt(0);
      }
      _markStartMs = -1;
      _updateDitEstimate();
    }

    var isDash = false;
    var markClassified = false;
    if (isOn && _markStartMs >= 0 && _ditEstimateMs > 0) {
      markClassified = true;
      final runningMs = frame.timestampMs - _markStartMs;
      isDash = runningMs > 2 * _ditEstimateMs;
    }

    onTrackOverlay?.call(
      TrackOverlayInfo(
        centerX: cx / frame.width,
        centerY: cy / frame.height,
        regionSizePx: regionSize,
        signalOn: isOn,
        markClassified: markClassified,
        isDash: isDash,
      ),
    );
  }

  /// 25th-percentile mark duration — the same robust dit
  /// estimator used for the WPM readout, so the overlay's dot /
  /// dash boundary matches what the decoder will ultimately
  /// classify.
  void _updateDitEstimate() {
    if (_markDurationsMs.length < _minMarkSamples) return;
    final sorted = [..._markDurationsMs]..sort();
    final idx = (sorted.length * 0.25).floor().clamp(
      0,
      sorted.length - 1,
    );
    final dit = sorted[idx].toDouble();
    if (dit > 0) _ditEstimateMs = dit;
  }

  // -- Signal loss -----------------------------------------------

  void _signalLost() {
    _builder.flush();
    _clearOverlayTelemetry();
    _lockGate.flush();
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

    // Clamp the search window to the target area — the user
    // keeps the source inside the reticle, so anything outside
    // it is background and must not grab the lock back.
    final range = _targetBlockRange(frame);
    final minBx = max(range.minBx, predBx - searchRadius);
    final maxBx = min(range.maxBx, predBx + searchRadius);
    final minBy = max(range.minBy, predBy - searchRadius);
    final maxBy = min(range.maxBy, predBy + searchRadius);

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

  /// Block-index bounds of the central target area — the square
  /// with side [targetAreaFraction] × min(width, height), centered
  /// on the frame. Only blocks fully inside it are considered.
  ///
  /// When [targetAreaFraction] ≥ 1 this degenerates to the whole
  /// frame, preserving the pre-target search.
  _BlockRange _targetBlockRange(VideoFrame frame) {
    final blocksX = frame.width ~/ blockSize;
    final blocksY = frame.height ~/ blockSize;
    if (targetAreaFraction >= 1) {
      return _BlockRange(
        minBx: 0,
        maxBx: blocksX - 1,
        minBy: 0,
        maxBy: blocksY - 1,
      );
    }
    final side = (targetAreaFraction * min(frame.width, frame.height)).round();
    final rectX = (frame.width - side) ~/ 2;
    final rectY = (frame.height - side) ~/ 2;

    // A block counts as in-target when its CENTER pixel lies
    // inside the square. Requiring full containment would shrink
    // the effective search area below the reticle drawn on screen
    // and lose sources resting near its edge.
    final half = blockSize / 2;
    var minBx = ((rectX - half) / blockSize).ceil();
    var maxBx = ((rectX + side - half) / blockSize).floor();
    var minBy = ((rectY - half) / blockSize).ceil();
    var maxBy = ((rectY + side - half) / blockSize).floor();

    // Degenerate target (smaller than one block) — fall back to
    // the single center block so scanning still works.
    if (minBx > maxBx) {
      final c = (frame.width / 2 / blockSize).floor();
      minBx = maxBx = c;
    }
    if (minBy > maxBy) {
      final c = (frame.height / 2 / blockSize).floor();
      minBy = maxBy = c;
    }

    return _BlockRange(
      minBx: minBx.clamp(0, blocksX - 1),
      maxBx: maxBx.clamp(0, blocksX - 1),
      minBy: minBy.clamp(0, blocksY - 1),
      maxBy: maxBy.clamp(0, blocksY - 1),
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

  /// Emits any element still held back by the merge lookahead.
  ///
  /// Call when the video stream ends so the final element is not lost.
  void flush() {
    _builder.flush();
    _lockGate.flush();
  }

  /// Clears the overlay mark-timing state and tells the overlay
  /// the lock is gone.
  void _clearOverlayTelemetry() {
    _markStartMs = -1;
    _markDurationsMs.clear();
    _ditEstimateMs = 0;
    onTrackOverlay?.call(null);
  }

  /// Resets the decoder to the scanning state.
  void reset() {
    _state = VideoDecoderState.scanning;
    _history.clear();
    _threshold.reset();
    _filter.reset();
    _builder.reset();
    _lockGate.reset();
    _confirmCount = 0;
    _lostFrameCount = 0;
    _lastFrameMs = 0;
    _isFullFrame = false;
    _clearOverlayTelemetry();
  }
}

/// Block-index bounds of the target area.
@pragma('vm:prefer-inline')
class _BlockRange {
  const _BlockRange({
    required this.minBx,
    required this.maxBx,
    required this.minBy,
    required this.maxBy,
  });

  final int minBx;
  final int maxBx;
  final int minBy;
  final int maxBy;
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
