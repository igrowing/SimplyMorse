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
      required int frameIndex,
      required int dtMs,
      required double maxVariance,
      required double meanVariance,
      required double minVariance,
      required int frameCount,
    });

/// Debug callback for confirming frames.
typedef DebugVideoConfirmCallback =
    void Function({
      required int timestampMs,
      required int frameIndex,
      required int dtMs,
      required double variance,
      required double minVariance,
      required int confirmCount,
      required double predictedX,
      required double predictedY,
      required double measuredX,
      required double measuredY,
    });

/// Debug callback for tracking frames — emitted on **every**
/// locked frame, including the ones where the search window found
/// no signal (`held` / signal-loss candidates), so the lead-up to
/// a lock loss is fully visible in the log.
typedef DebugVideoTrackCallback =
    void Function({
      required int timestampMs,
      required int frameIndex,
      required int dtMs,
      required double searchVariance,
      required double minVariance,
      required int lostFrameCount,
      required bool held,
      required bool isFullFrame,
      required double predictedX,
      required double predictedY,
      required double measuredX,
      required double measuredY,
      required double velocityX,
      required double velocityY,
      required double innovation,
      required int peakBx,
      required int peakBy,
      required int winMinBx,
      required int winMaxBx,
      required int winMinBy,
      required int winMaxBy,
      required int blocksAboveFloor,
      required double weightSum,
      required double rawBrightness,
      required double annulusBrightness,
      required double brightness,
      required double minBrightness,
      required double maxBrightness,
      required double onThreshold,
      required double offThreshold,
      required bool isOn,
      required int regionX,
      required int regionY,
      required int regionSize,
      required double ditEstimateMs,
      required int wpm,
    });

/// Debug callback for video transitions.
typedef DebugVideoTransitionCallback =
    void Function({
      required int timestampMs,
      required int frameIndex,
      required bool isOn,
      required int durationMs,
      required int sequence,
      required double effectiveTransitionMs,
      required double edgeMs,
      required double ditEstimateMs,
      required int wpm,
    });

/// Debug callback for signal loss.
typedef DebugVideoSignalLostCallback =
    void Function({
      required int timestampMs,
      required int frameIndex,
      required int lostFrameCount,
      required int heldForMs,
      required double lastSearchVariance,
      required double minVariance,
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
    this.signalHoldMs = 3000,
    this.minRegionSize = 8,
    this.maxRegionSize = 32,
    this.backgroundMarginPx = 8,
    this.regionSizeSmoothing = 0.25,
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

  /// Consecutive low-variance frames before signal loss — the hard
  /// fallback used when the lock was never backed by a real blink
  /// (e.g. locked onto camera-autoexposure settling). Once genuine
  /// on/off contrast has been seen, [signalHoldMs] governs instead.
  final int lostFrameLimit;

  /// How long (ms) to hold a lock through a low-variance stretch
  /// before giving it up.
  ///
  /// Temporal variance in the tracked block naturally decays to
  /// zero during any legitimately long OFF period — an inter-word
  /// gap (7 dit units), the pause between message repetitions, or a
  /// brief moment where hand motion outruns the search window.
  /// Dropping the lock the instant variance falls (the old
  /// [lostFrameLimit]-only behaviour) sent the decoder back to
  /// scanning mid-message on every word space, which showed up as
  /// the lock "disappearing and reappearing".
  ///
  /// While holding, the α-β filter is frozen at its last confident
  /// position (see [AlphaBetaFilter.freeze]) and brightness is
  /// still read there every frame, so the OFF gap is timed
  /// correctly and the lock resumes seamlessly when the source
  /// blinks again. If the hold expires with no recovery, the
  /// signal is declared lost. 3 s covers inter-word gaps down to
  /// roughly 2.5 WPM.
  final int signalHoldMs;

  /// Minimum brightness-reading region size (pixels).
  final int minRegionSize;

  /// Maximum brightness-reading region size (pixels).
  final int maxRegionSize;

  /// Extra pixels beyond the brightness-reading region's own radius
  /// that make up the background annulus used to cancel shared
  /// auto-exposure drift. See the background-subtraction comment in
  /// [_track].
  final int backgroundMarginPx;

  /// Low-pass factor applied to the brightness-reading region's
  /// size, in `(0, 1]` (higher = follows the raw target size more
  /// closely, lower = smoother). The raw target size is driven by
  /// [AlphaBetaFilter.innovation], which is itself a per-frame error
  /// signal — reading it straight into a *displayed/used* size on
  /// every frame lets ordinary single-frame noise (in particular,
  /// the reticle-relative jitter in [_searchPeakVariance]'s
  /// measurement) show up as the region visibly expanding and
  /// contracting. Smoothing it decouples "how big should the
  /// reading region be" from "how noisy was this one frame".
  final double regionSizeSmoothing;

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

  /// Low-pass-filtered brightness-reading region size — see
  /// [regionSizeSmoothing]. `null` until the first tracked frame
  /// after a (re)lock, so the very first reading snaps straight to
  /// its raw value instead of smoothing from zero.
  double? _smoothedRegionSize;

  // Timing
  int _lastFrameMs = 0;

  // Per-frame cadence tracking for the debug log — independent of
  // the state machine so scanning frames get a dt too.
  int _frameIndex = 0;
  int _prevFrameMs = 0;
  int _frameDtMs = 0;

  // Signal loss counter
  int _lostFrameCount = 0;

  /// Timestamp of the most recent frame whose search window found
  /// real signal (variance above [minVariance]); `-1` before the
  /// first such frame after a (re)lock. Drives the [signalHoldMs]
  /// hold window.
  int _lastHealthyFrameMs = -1;

  /// Timestamp the current low-variance hold started, or `-1` when
  /// not holding. See [signalHoldMs].
  int _holdStartMs = -1;

  /// Peak search-window variance seen on the last processed
  /// tracking frame — logged with the signal-loss event.
  double _lastSearchVariance = 0;

  /// Measurement (raw search result) from the last tracking frame
  /// where signal was present — logged alongside the filter's
  /// prediction so the two can be compared.
  double _lastMeasuredX = 0;
  double _lastMeasuredY = 0;

  /// Monotonic counter for emitted transitions, so the log can
  /// order the burst the [MorseLockGate] releases when the lock
  /// gate opens (every row in that burst shares a timestamp).
  int _transitionSeq = 0;

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
  late final ElementBuilder _builder = ElementBuilder(onElement: _lockGate.add);

  void _emit(DecodedElement element) {
    onDebugTransition?.call(
      timestampMs: _lastFrameMs,
      frameIndex: _frameIndex,
      isOn: element.isOn,
      durationMs: element.durationMs,
      sequence: _transitionSeq++,
      effectiveTransitionMs: _threshold.effectiveTransitionMs,
      edgeMs: _threshold.lastEdgeMs,
      ditEstimateMs: _ditEstimateMs,
      wpm: _wpm,
    );
    onElement?.call(element);
  }

  /// Current dit-based WPM estimate (`0` until enough marks seen).
  int get _wpm => _ditEstimateMs > 0 ? (1200 / _ditEstimateMs).round() : 0;

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

  /// Processes a single video frame.
  void processFrame(VideoFrame frame) {
    _frameIndex++;
    _frameDtMs = _prevFrameMs > 0 ? frame.timestampMs - _prevFrameMs : 0;
    _prevFrameMs = frame.timestampMs;
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

    // Computed before the accept/reject check, not after: the mean is
    // the scene's own noise floor, and the frames that *fail* the
    // check are exactly the ones whose noise floor is worth knowing.
    // Reporting 0 for them (the previous behaviour) blanked out 116
    // of 120 scanning rows in a no-signal field capture — the very
    // measurement needed to tell noise from signal.
    final meanVariance = variances.reduce((a, b) => a + b) / variances.length;

    // A full-frame blink is a *positive* finding: the whole target
    // area is varying strongly and uniformly. It used to be inferred
    // from the peak's failure to stand out from the mean, which is
    // also exactly what uniform sensor noise looks like — so a noisy
    // still scene was classified as a flashing screen, and then had
    // background subtraction disabled on that basis. Requiring the
    // *mean* to clear the variance floor is what separates the two:
    // in a real full-frame blink every block swings, in a still noisy
    // scene none of them does.
    final fullFrame =
        meanVariance >= minVariance && maxVariance < meanVariance * 2;

    onDebugScan?.call(
      timestampMs: frame.timestampMs,
      frameIndex: _frameIndex,
      dtMs: _frameDtMs,
      maxVariance: maxVariance,
      meanVariance: meanVariance,
      minVariance: minVariance,
      frameCount: _history.length,
    );

    if (maxVariance < minVariance) return;
    _isFullFrame = fullFrame;

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
        frameIndex: _frameIndex,
        dtMs: _frameDtMs,
        variance: result.variance,
        minVariance: minVariance,
        confirmCount: _confirmCount,
        predictedX: _filter.x,
        predictedY: _filter.y,
        measuredX: result.centerX,
        measuredY: result.centerY,
      );
      if (_confirmCount >= confirmFrames) {
        _state = VideoDecoderState.locked;
        _threshold.reset();
        _builder.reset();
        _lockGate.reset();
        _smoothedRegionSize = null;
        _lostFrameCount = 0;
        _holdStartMs = -1;
        _lastHealthyFrameMs = frame.timestampMs;
        _lastSearchVariance = result.variance;
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
    _lastSearchVariance = result.variance;
    final signalPresent = result.variance > minVariance;

    if (signalPresent) {
      _filter.update(result.centerX, result.centerY, dt);
      _lastMeasuredX = result.centerX;
      _lastMeasuredY = result.centerY;
      _lostFrameCount = 0;
      _lastHealthyFrameMs = frame.timestampMs;
      _holdStartMs = -1;
      _readAndClassify(frame: frame, search: result, held: false);
      _lastFrameMs = frame.timestampMs;
      return;
    }

    // No signal in the search window this frame. Rather than
    // dropping the lock immediately, hold it through legitimately
    // long OFF stretches (word gaps, brief tracking wobble): the
    // block's temporal variance always decays to zero during
    // silence, so an instant drop sent the decoder back to scanning
    // mid-message on every space. See [signalHoldMs].
    _lostFrameCount++;

    final sawContrast = _threshold.range >= _threshold.minRange;
    final withinHold =
        _lastHealthyFrameMs >= 0 &&
        frame.timestampMs - _lastHealthyFrameMs < signalHoldMs;
    final canHold = sawContrast && withinHold;

    if (_holdStartMs < 0) {
      _holdStartMs = frame.timestampMs;
      // Freeze the filter where it last had a confident fix so its
      // prediction stops coasting on a stale velocity while blind.
      _filter.freeze();
    }

    // Emit the per-frame telemetry either way — the run-up to a
    // loss is exactly the part that used to be invisible.
    _readAndClassify(frame: frame, search: result, held: true);
    _lastFrameMs = frame.timestampMs;

    if (!canHold && _lostFrameCount >= lostFrameLimit) {
      _signalLost();
    }
  }

  /// Reads the brightness-reading region at the filter's current
  /// position, runs it through the on/off threshold and element
  /// builder, and emits the per-frame debug telemetry and overlay
  /// update. Shared by the normal tracking path and the
  /// [signalHoldMs] hold path — [held] is `true` for the latter,
  /// where the filter is frozen and [search] found nothing.
  void _readAndClassify({
    required VideoFrame frame,
    required _SearchResult search,
    required bool held,
  }) {
    if (!held) {
      // Region size adapts to filter innovation — grows when the
      // source moves unpredictably — but innovation is a raw
      // per-frame error signal, noisy even when the source itself is
      // steady (see _searchPeakVariance), so low-pass filter it:
      // without this the target size — and so the on-screen debug
      // circle — visibly expands and contracts frame to frame
      // independent of any real change in motion.
      final targetRegionSize = (_filter.innovation * 2).clamp(
        minRegionSize.toDouble(),
        maxRegionSize.toDouble(),
      );
      _smoothedRegionSize = _smoothedRegionSize == null
          ? targetRegionSize
          : _smoothedRegionSize! +
                regionSizeSmoothing * (targetRegionSize - _smoothedRegionSize!);
    }
    _smoothedRegionSize ??= minRegionSize.toDouble();
    final regionSize = _smoothedRegionSize!.round();

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
    final annulusBrightness = _isFullFrame
        ? 0.0
        : frame.annulusMeanLuminance(cx, cy, half, half + backgroundMarginPx);
    final brightness = _isFullFrame
        ? rawBrightness
        : rawBrightness - annulusBrightness;

    final isOn = _threshold.process(brightness, timestampMs: frame.timestampMs);
    onDebugTrack?.call(
      timestampMs: frame.timestampMs,
      frameIndex: _frameIndex,
      dtMs: _frameDtMs,
      searchVariance: search.variance,
      minVariance: minVariance,
      lostFrameCount: _lostFrameCount,
      held: held,
      isFullFrame: _isFullFrame,
      predictedX: _filter.x,
      predictedY: _filter.y,
      measuredX: held ? _lastMeasuredX : search.centerX,
      measuredY: held ? _lastMeasuredY : search.centerY,
      velocityX: _filter.vx,
      velocityY: _filter.vy,
      innovation: _filter.innovation,
      peakBx: search.peakBx,
      peakBy: search.peakBy,
      winMinBx: search.minBx,
      winMaxBx: search.maxBx,
      winMinBy: search.minBy,
      winMaxBy: search.maxBy,
      blocksAboveFloor: search.blocksAboveFloor,
      weightSum: search.weightSum,
      rawBrightness: rawBrightness,
      annulusBrightness: annulusBrightness,
      brightness: brightness,
      minBrightness: _brightnessMin,
      maxBrightness: _brightnessMax,
      onThreshold: _threshold.onThreshold,
      offThreshold: _threshold.offThreshold,
      isOn: isOn,
      regionX: cx,
      regionY: cy,
      regionSize: regionSize,
      ditEstimateMs: _ditEstimateMs,
      wpm: _wpm,
    );
    _updateOverlayTelemetry(
      frame: frame,
      isOn: isOn,
      cx: cx,
      cy: cy,
      regionSize: regionSize,
      held: held,
    );

    _builder.transition(nowOn: isOn, timeMs: _threshold.effectiveTransitionMs);
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
    required bool held,
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
        holding: held,
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
    final idx = (sorted.length * 0.25).floor().clamp(0, sorted.length - 1);
    final dit = sorted[idx].toDouble();
    if (dit > 0) _ditEstimateMs = dit;
  }

  // -- Signal loss -----------------------------------------------

  void _signalLost() {
    _builder.flush();
    _clearOverlayTelemetry();
    // Losing the lock is not the end of a transmission — it is the
    // decoder concluding there was no transmission. Anything the lock
    // gate is still holding failed to prove itself as Morse, so it is
    // released only if it fits, never unconditionally. See
    // [MorseLockGate.releaseOnSignalLoss].
    _lockGate.releaseOnSignalLoss();
    onDebugSignalLost?.call(
      timestampMs: _lastFrameMs,
      frameIndex: _frameIndex,
      lostFrameCount: _lostFrameCount,
      heldForMs: _holdStartMs >= 0 ? _lastFrameMs - _holdStartMs : 0,
      lastSearchVariance: _lastSearchVariance,
      minVariance: minVariance,
    );
    onDebugStateChange?.call(
      timestampMs: _lastFrameMs,
      newState: 'scanning',
      detail: 'signal_lost',
    );
    _threshold.reset();
    _filter.reset();
    _smoothedRegionSize = null;
    _state = VideoDecoderState.scanning;
    _confirmCount = 0;
    _lostFrameCount = 0;
    _holdStartMs = -1;
    _lastHealthyFrameMs = -1;
    _lastSearchVariance = 0;
  }

  // -- Search ----------------------------------------------------

  /// Result of a local variance search.
  static const _emptyResult = _SearchResult(
    variance: 0,
    centerX: 0,
    centerY: 0,
    peakBx: 0,
    peakBy: 0,
    minBx: 0,
    maxBx: 0,
    minBy: 0,
    maxBy: 0,
    blocksAboveFloor: 0,
    weightSum: 0,
  );

  _SearchResult _searchPeakVariance(VideoFrame frame) {
    if (_isFullFrame) {
      // Full-frame blink — no need to search
      return _SearchResult(
        variance: _blockVariance(0, 0),
        centerX: frame.width / 2,
        centerY: frame.height / 2,
        peakBx: 0,
        peakBy: 0,
        minBx: 0,
        maxBx: 0,
        minBy: 0,
        maxBy: 0,
        blocksAboveFloor: 0,
        weightSum: 0,
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

    // Two things are needed from this window: the PEAK variance
    // (reported as `variance`, gating lock/loss — unchanged
    // semantics) and a POSITION. The position used to be the peak
    // block's own center, i.e. a hard argmax — but the light source
    // is a physical position that rarely aligns to an 8px block
    // boundary, so it typically splits its variance across two or
    // more neighboring blocks. Argmax then picks a winner by
    // whichever block edges out the others on pure per-frame noise,
    // and visibly SNAPS between block centers (up to blockSize px
    // apart) as that noise tips the balance a different way frame
    // to frame — the reported "sudden jump" symptom.
    //
    // A variance-weighted centroid over the blocks near the peak
    // gives sub-block precision instead: it moves continuously as
    // the true split between neighboring blocks shifts, rather than
    // snapping wholesale from one block's center to another's.
    // Computed in the same pass as the peak so the window's
    // variance isn't recomputed twice (each call re-walks up to
    // `historySize` frames of history per block).
    var maxVariance = 0.0;
    var peakBx = minBx;
    var peakBy = minBy;
    final blockVariances = <double>[];
    for (var by = minBy; by <= maxBy; by++) {
      for (var bx = minBx; bx <= maxBx; bx++) {
        final v = _blockVariance(bx, by);
        blockVariances.add(v);
        if (v > maxVariance) {
          maxVariance = v;
          peakBx = bx;
          peakBy = by;
        }
      }
    }

    if (maxVariance <= 0) {
      return _SearchResult(
        variance: 0,
        centerX: 0,
        centerY: 0,
        peakBx: peakBx,
        peakBy: peakBy,
        minBx: minBx,
        maxBx: maxBx,
        minBy: minBy,
        maxBy: maxBy,
        blocksAboveFloor: 0,
        weightSum: 0,
      );
    }

    // Only blocks close to the peak count toward the centroid —
    // otherwise a large search window would let distant, barely-lit
    // background blocks pull the estimate away from the source.
    const centroidFloorFraction = 0.5;
    final floor = maxVariance * centroidFloorFraction;

    var weightSum = 0.0;
    var xSum = 0.0;
    var ySum = 0.0;
    var blocksAboveFloor = 0;
    var i = 0;
    for (var by = minBy; by <= maxBy; by++) {
      for (var bx = minBx; bx <= maxBx; bx++) {
        final v = blockVariances[i++];
        if (v < floor) continue;
        blocksAboveFloor++;
        weightSum += v;
        xSum += v * (bx * blockSize + blockSize / 2.0);
        ySum += v * (by * blockSize + blockSize / 2.0);
      }
    }

    return _SearchResult(
      variance: maxVariance,
      centerX: xSum / weightSum,
      centerY: ySum / weightSum,
      peakBx: peakBx,
      peakBy: peakBy,
      minBx: minBx,
      maxBx: maxBx,
      minBy: minBy,
      maxBy: maxBy,
      blocksAboveFloor: blocksAboveFloor,
      weightSum: weightSum,
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
    _smoothedRegionSize = null;
    _builder.reset();
    _lockGate.reset();
    _confirmCount = 0;
    _lostFrameCount = 0;
    _lastFrameMs = 0;
    _isFullFrame = false;
    _frameIndex = 0;
    _prevFrameMs = 0;
    _frameDtMs = 0;
    _holdStartMs = -1;
    _lastHealthyFrameMs = -1;
    _lastSearchVariance = 0;
    _lastMeasuredX = 0;
    _lastMeasuredY = 0;
    _transitionSeq = 0;
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
    required this.peakBx,
    required this.peakBy,
    required this.minBx,
    required this.maxBx,
    required this.minBy,
    required this.maxBy,
    required this.blocksAboveFloor,
    required this.weightSum,
  });

  /// Peak block variance in the window (gates lock/loss).
  final double variance;

  /// Variance-weighted centroid of the near-peak blocks (pixels).
  final double centerX;
  final double centerY;

  /// Block index of the single highest-variance block.
  final int peakBx;
  final int peakBy;

  /// Search-window bounds actually walked, in block indices (after
  /// clamping to the target area).
  final int minBx;
  final int maxBx;
  final int minBy;
  final int maxBy;

  /// How many blocks cleared the centroid floor (0.5 × peak). A
  /// count of 1 means the centroid is a single block's center — no
  /// sub-block smoothing was possible this frame.
  final int blocksAboveFloor;

  /// Sum of the variances that fed the centroid — a rough
  /// signal-strength proxy independent of [variance].
  final double weightSum;
}
