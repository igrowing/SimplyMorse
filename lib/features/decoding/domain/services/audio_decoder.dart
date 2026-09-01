import 'dart:typed_data';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';
import 'package:simply_morse/features/decoding/domain/services/iir_envelope_detector.dart';
import 'package:simply_morse/features/decoding/domain/services/level_tracker.dart';
import 'package:simply_morse/features/decoding/domain/services/noise_floor_estimator.dart';

/// Debug log callback for scanning frames.
typedef DebugScanningCallback =
    void Function({
      required int totalSamples,
      required int sampleRate,
      required int dominantBin,
      required double dominantPower,
      required double avgOtherPower,
      required double snr,
      required int consecutiveFrames,
      required int persistenceNeeded,
      required bool locked,
    });

/// Debug log callback for lock events.
typedef DebugLockCallback =
    void Function({
      required int totalSamples,
      required int sampleRate,
      required double freq,
      required double bestAvgPower,
      required double noiseFloor,
      required double onThresholdFactor,
    });

/// Debug log callback for tracking frames.
typedef DebugTrackingCallback =
    void Function({
      required int totalSamples,
      required int sampleRate,
      required double freq,
      required double power,
      required double envelope,
      required double noiseFloor,
      required double onThreshold,
      required double offThreshold,
      required bool isOn,
    });

/// Debug log callback for transitions.
typedef DebugTransitionCallback =
    void Function({
      required int totalSamples,
      required int sampleRate,
      required bool isOn,
      required int durationMs,
    });

/// State of the audio decoding pipeline.
enum DecoderState {
  /// Scanning phase — continuously analyzing FFT frames to
  /// find a monotonic tone. Locks when the criteria for a
  /// monotonic tone are met (see class docs).
  scanning,

  /// Locked on a frequency — tracking the on/off envelope.
  locked,
}

/// Audio decoding pipeline using IIR bandpass filtering.
///
/// **Monotonic tone definition** (the lock criteria):
/// - One sharp tone: spectral peak-to-average ratio ≥
///   [onThresholdFactor] (single dominant frequency)
/// - Detected for at least [minToneMs] (160 ms, ~5 FFT frames at
///   32 ms/frame — see that field for why the 50 ms in the spec is
///   not attainable)
/// - Either:
///   - A single continuous tone lasting ≥ [longToneMs] (500 ms — a
///     long dah at stable power is sufficient evidence on its own,
///     which is what makes the repeat criterion conditional), OR
///   - [requiredDetections] detections of the same frequency within
///     2000 ms (repeating tone pattern)
///
/// Pipeline:
/// 1. **Scanning** — continuously runs FFT frames over 400–1000 Hz.
///    Each frame checks if the dominant bin has SNR ≥ 4 (monotonic).
///    Runs of consecutive monotonic frames are tracked as "detection
///    events". The decoder locks when either:
///    - A single run lasts ≥ [longToneMs], OR
///    - [requiredDetections] detection events of the same frequency
///      occur within 2000 ms
///    This rejects voice (frequencies jump between bins, can't sustain
///    a run), broadband noise (low SNR), and brief noise spikes
///    (can't produce two detections at the same frequency).
/// 2. **Lock** — creates an IIR bandpass filter (biquad) centered on
///    the detected frequency. Bandwidth is relative: ±8% of the
///    locked frequency (e.g. ±56 Hz at 700 Hz, ±80 Hz at 1000 Hz),
///    giving a constant Q of 6.25 at all frequencies. This eliminates
///    frequency-dependent ringing. Parabolic interpolation gives
///    sub-bin frequency accuracy.
/// 3. **Track** — processes audio sample-by-sample through the bandpass
///    filter, rectifies, and lowpass-filters to produce a smooth
///    envelope. Hysteresis thresholding detects on/off transitions.
///    The noise floor is continuously updated during confirmed off
///    periods.
/// 4. **Permanent lock** — once locked, the frequency does not change
///    until [reset] is called. The decoder does not unlock on silence;
///    it simply produces long off-elements. This preserves word gaps
///    and avoids re-locking artifacts. Set [signalTimeoutMs] > 0 to
///    enable auto-unlock (legacy behavior).
///
/// Emits [DecodedElement]s via [onElement] as transitions are detected.
/// Elements shorter than [minElementMs] are filtered.
class AudioDecoder {
  AudioDecoder({
    this.sampleRate = 8000,
    this.minFreq = 400,
    this.maxFreq = 1000,
    this.fftSize = 256,
    this.blockSize = 40,
    this.signalTimeoutMs = 0,
    this.bandwidth = 0,
    this.bandwidthRatio = 0.16,
    this.envelopeCutoffHz = kDefaultEnvelopeCutoffHz,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
    this.minElementMs = 10,
    this.glitchRatio = 0.25,
    this.minToneMs = 160,
    this.longToneMs = 500,
    this.requiredDetections = 3,
    this.hysteresisDb = 2.5,
    this.minSeparationDb = 6.0,
    this.thresholdOffsetDb = 3.0,
    this.noiseMarginDb = 10.0,
    this.levelAttackMs = 120,
    this.levelReleaseMs = 150,
    this.maxSpaceDropDb = 8.0,
    this.fastDitThresholdMs = 85,
    this.normalLevelAttackMs = 120,
    this.normalLevelReleaseMs = 150,
    this.normalThresholdOffsetDb = 4.0,
    this.fastLevelAttackMs = 30,
    this.fastLevelReleaseMs = 220,
    this.fastThresholdOffsetDb = 3.0,
    this.preLockBufferMs = 1200,
    this.reTuneIntervalBlocks = 0,
  }) {
    _fft = FFT(fftSize);
    _frameMs = fftSize * 1000 / sampleRate;
    // Derived scanning thresholds (computed from frame rate).
    _minToneFrames = (minToneMs / _frameMs).ceil();
    _longToneFrames = (longToneMs / _frameMs).ceil();
    _maxRepeatGapFrames = (2000 / _frameMs).round(); // ~62 frames = 2000 ms
  }

  // Configuration
  final int sampleRate;
  final double minFreq;
  final double maxFreq;
  final int fftSize;
  final int blockSize;

  /// If > 0 and the envelope stays at the noise floor for this many
  /// milliseconds during tracking, the decoder unlocks and returns
  /// to scanning. Default 0 = permanent lock (never auto-unlock).
  /// Set to a positive value for legacy auto-unlock behavior.
  final int signalTimeoutMs;

  /// Fixed IIR bandwidth in Hz. If > 0, used directly.
  /// If 0 (default), [bandwidthRatio] is used instead.
  final double bandwidth;

  /// IIR bandwidth as a fraction of the locked frequency (default
  /// 0.16 = ±8%). Used when [bandwidth] == 0. This gives a constant
  /// Q factor at all frequencies, eliminating frequency-dependent
  /// ringing. Example: 700 Hz → 112 Hz wide, 1000 Hz → 160 Hz wide.
  final double bandwidthRatio;

  final double envelopeCutoffHz;
  final double onThresholdFactor;
  final double offThresholdFactor;

  /// Absolute floor for the glitch-merge threshold, in ms.
  final int minElementMs;

  /// Shortest run of monotonic frames that counts as a detection.
  ///
  /// The spec calls for 50 ms (~2 frames at 32 ms per frame), but that
  /// is not attainable at the SNRs in the reference recordings:
  /// measured over them, 50 ms locks onto the wrong frequency
  /// (700 Hz material locking at 413–568 Hz) and roughly triples the
  /// character error rate. Two frames of agreement is simply not
  /// enough evidence to reject a noise peak. 160 ms — five frames —
  /// is the shortest value that still locks correctly on all five.
  final int minToneMs;

  /// A single continuous tone this long is on its own sufficient
  /// evidence to lock, which makes the repeat criterion conditional:
  /// one steady dah is enough.
  final int longToneMs;

  /// How many detections of the same frequency within
  /// [_maxRepeatGapFrames] are needed to lock when no single run is
  /// long enough.
  ///
  /// The spec says "repeats", i.e. two. Measured, two is not enough to
  /// reject a false frequency: it costs a correct lock on two of the
  /// five reference recordings. Three is used instead.
  final int requiredDetections;

  /// Glitch-merge threshold as a fraction of the estimated dit, once
  /// enough elements have been seen to estimate one.
  ///
  /// A fixed threshold cannot serve the whole speed range: 30 ms is a
  /// fifth of a dit at 8 WPM, where it usefully swallows noise
  /// transitions, but half a dit at 20 WPM, where it merges genuine
  /// dits into dahs. Scaling with the observed element rate keeps its
  /// meaning constant.
  final double glitchRatio;

  /// Half-width in dB of the symmetric hysteresis band used when
  /// tracking. Symmetric thresholds remove the mark/space duration
  /// bias of the old 50 % / 25 % linear thresholds.
  final double hysteresisDb;

  /// Minimum mark-to-space separation in dB below which the tracker
  /// squelches instead of emitting elements from noise.
  final double minSeparationDb;

  /// How far below the tracked mark level the on/off threshold sits.
  final double thresholdOffsetDb;

  /// How far above the tracked space level the threshold is kept.
  final double noiseMarginDb;

  /// Attack time constant of the two level estimates, in ms, used
  /// until a keying speed has been estimated (see [fastDitThresholdMs]).
  /// Also the permanent fallback if a speed estimate never becomes
  /// available — e.g. [preLockBufferMs] disabled.
  final double levelAttackMs;

  /// Release time constant of the two level estimates, in ms. See
  /// [levelAttackMs].
  final double levelReleaseMs;

  /// Bound, in dB, on how far the tracked space (background) level is
  /// allowed to fall below its value at the start of a single
  /// uninterrupted gap.
  ///
  /// Without this, a long silence (the 2.4–2.9 s gaps between
  /// repetitions in the reference recordings) lets the space level
  /// drift down to whatever the background happens to measure during
  /// that particular quiet stretch. If the background then rises once
  /// keying resumes — which the 1000 Hz reference recording's
  /// documented 14 dB rise shows really happens — the stale, too-low
  /// space level drags the threshold down with it, and genuine
  /// intra-word gaps stop crossing back below threshold, merging
  /// characters together. Clamping the fall bounds the damage without
  /// preventing the space level from tracking real drift during
  /// normal (short) inter-element gaps.
  final double maxSpaceDropDb;

  /// Estimated dit duration, in ms, below which the tracker switches
  /// to [fastLevelAttackMs]/[fastLevelReleaseMs]/[fastThresholdOffsetDb]
  /// instead of the [normalLevelAttackMs]/[normalLevelReleaseMs]/
  /// [normalThresholdOffsetDb] profile.
  ///
  /// Default 85 ms ≈ 14 WPM (1200 / 14 ≈ 85.7 ms). Below this speed
  /// [levelAttackMs]'s 120 ms default attack time is comparable to or
  /// longer than a single dit, so the mark level never converges
  /// within it — measured on the 20 WPM reference recording (60 ms
  /// dit), the first repetition decodes as "EM DO," garbage before
  /// the tracker catches up.
  final double fastDitThresholdMs;

  /// Attack time constant used once the keying speed is known to be
  /// at or above [fastDitThresholdMs]'s boundary. Same value as
  /// [levelAttackMs]'s default — listed separately because the two
  /// are tuned independently.
  final double normalLevelAttackMs;

  /// Release time constant paired with [normalLevelAttackMs].
  final double normalLevelReleaseMs;

  /// [LevelTracker.thresholdOffsetDb] used at normal speed. Measured
  /// 4.0 dB (vs. the class's un-gated 3.0 dB default) trims the 8 WPM
  /// / 700 Hz CER from 11.1 % to 7.4 %; the same value costs the
  /// 20 WPM recording badly (29.3 % → 73.2 %), which is why it's only
  /// applied once the tracker knows the speed isn't fast.
  final double normalThresholdOffsetDb;

  /// Attack time constant used once the estimated dit falls below
  /// [fastDitThresholdMs] — short enough to converge within a single
  /// dit at 20 WPM.
  final double fastLevelAttackMs;

  /// Release time constant paired with [fastLevelAttackMs]. Longer
  /// than the attack (asymmetric) so the level doesn't relax away
  /// from a genuine mark/space before the next element arrives, given
  /// how little time there is between them at this speed.
  final double fastLevelReleaseMs;

  /// [LevelTracker.thresholdOffsetDb] used once fast keying is
  /// detected — equal to the class's un-gated default; see
  /// [normalThresholdOffsetDb] for why the normal-speed profile uses
  /// a different value instead of sharing this one.
  final double fastThresholdOffsetDb;

  /// How much audio to retain during scanning so that, on lock, the
  /// acquisition window can be re-decoded with converged levels
  /// instead of being lost. Set to 0 to disable.
  ///
  /// Measured on the reference recordings, 1200 ms beats the original
  /// 3000 ms (23 vs 26 total errors) and is stable across roughly
  /// 800-1600 ms — anything much larger starts including audio from
  /// well before the message began, and seeding the level tracker
  /// from that (mostly background, occasionally a stray transient)
  /// percentile sample can leave the very first character worse off
  /// than a shorter, more tightly-targeted replay window would.
  final int preLockBufferMs;

  /// How often (in tracking blocks) to re-check the FFT for a
  /// frequency change during tracking. Default 0 = disabled
  /// (permanent lock, never re-tune).
  ///
  /// When > 0, every [reTuneIntervalBlocks] tracking blocks the
  /// decoder runs a quick FFT scan on the recent audio. If the
  /// dominant frequency has shifted significantly (> 50 Hz) AND
  /// the current locked frequency's power has dropped below the
  /// noise floor, the decoder unlocks and re-scans — effectively
  /// following the operator to a new frequency (QSY) without
  /// manual intervention.
  ///
  /// This does not re-tune while a valid signal is present at
  /// the locked frequency — it only triggers when the signal at
  /// the locked frequency is gone and a new, stronger one has
  /// appeared elsewhere.
  final int reTuneIntervalBlocks;

  // Derived scanning thresholds
  late final int _minToneFrames;
  late final int _longToneFrames;
  late final int _maxRepeatGapFrames;

  // Internal components
  late final FFT _fft;
  late final double _frameMs;
  final _noiseFloor = NoiseFloorEstimator();

  // State machine
  DecoderState _state = DecoderState.scanning;
  DecoderState get state => _state;

  // Scanning state — run-based monotonic detection
  int? _runBin; // dominant bin of the current run
  int _runLen = 0; // consecutive monotonic frames in this run
  int? _lastDetectionBin; // bin of the last completed detection
  int _lastDetectionEndFrame = 0; // frame index when last detection ended
  int _detectionCount = 0; // number of detections at this frequency
  int _frameIndex = 0; // total scanning frames processed
  final Map<int, double> _binPowerAccum = {};
  int _scanFrames = 0; // frames accumulated for parabolic interpolation

  // Tracking state
  IirEnvelopeDetector? _detector;
  late final LevelTracker _levels = LevelTracker(
    attackMs: levelAttackMs,
    releaseMs: levelReleaseMs,
    hysteresisDb: hysteresisDb,
    minSeparationDb: minSeparationDb,
    thresholdOffsetDb: thresholdOffsetDb,
    noiseMarginDb: noiseMarginDb,
    maxSpaceDropDb: maxSpaceDropDb,
  );

  /// Raw samples retained during scanning, replayed on lock.
  final List<double> _preLock = [];
  int get _preLockCapacity => (preLockBufferMs * sampleRate / 1000).round();
  double _lockedFreq = 0;
  int _lastSignalSample = 0;

  // Re-tune state
  final List<double> _reTuneBuffer = [];
  int _reTuneCounter = 0;

  /// The frequency the decoder has locked onto, in Hz.
  /// Returns 0 while scanning.
  double get lockedFrequency => _lockedFreq;

  /// Whether the decoder is currently in the scanning phase.
  bool get isScanning => _state == DecoderState.scanning;

  /// Whether the decoder is currently in the scanning phase.
  /// Alias for [isScanning] for backward compatibility.
  bool get isCalibrating => isScanning;

  // Envelope / on-off state
  bool _isOn = false;
  int _totalSamples = 0;
  bool _seenFirstOn = false;

  /// Turns on/off transitions into elements, merging glitches.
  late final ElementBuilder _elements = ElementBuilder(
    onElement: _emit,
    minElementMs: minElementMs,
    glitchRatio: glitchRatio,
  );

  // Sample buffer
  final List<double> _buffer = [];

  // Output
  void Function(DecodedElement element)? onElement;

  /// Optional callback invoked when the frequency is locked.
  void Function(double freq)? onLock;

  /// Optional callback invoked when the decoder unlocks and returns
  /// to scanning (only fires if [signalTimeoutMs] > 0).
  void Function()? onUnlock;

  // -- Debug callbacks --
  DebugScanningCallback? onDebugScanning;
  DebugLockCallback? onDebugLock;
  DebugTrackingCallback? onDebugTracking;
  DebugTransitionCallback? onDebugTransition;

  /// Processes a batch of audio samples.
  void processSamples(List<double> samples) {
    _buffer.addAll(samples);

    while (_buffer.length >= _windowSize) {
      final window = _buffer.sublist(0, _windowSize);
      _buffer.removeRange(0, _windowSize);
      _totalSamples += _windowSize;
      _processWindow(window);
    }
  }

  int get _windowSize => _state == DecoderState.locked ? blockSize : fftSize;

  void _processWindow(List<double> samples) {
    switch (_state) {
      case DecoderState.scanning:
        _scan(samples);
      case DecoderState.locked:
        _track(samples);
    }
  }

  // -- Scanning phase --------------------------------------------
  //
  // Monotonic tone detection:
  // - A "run" = consecutive FFT frames where the same bin (±1) is
  //   dominant with SNR ≥ onThresholdFactor.
  // - A "detection" = a run of ≥ _minToneFrames ([minToneMs]).
  // - Lock when: a single run ≥ _longToneFrames (500 ms), OR
  //   two detections of the same frequency within _maxRepeatGapFrames
  //   (2000 ms).

  void _scan(List<double> samples) {
    _frameIndex++;

    if (preLockBufferMs > 0) {
      _preLock.addAll(samples);
      final overflow = _preLock.length - _preLockCapacity;
      if (overflow > 0) _preLock.removeRange(0, overflow);
    }

    final power = _fft.powerSpectrum(Float64List.fromList(samples));

    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    // Find the dominant bin and compute noise floor (avg of all
    // other bins in the band).
    var bestBin = -1;
    var bestPower = 0.0;
    double otherPower = 0;
    var otherCount = 0;

    for (var i = minBin; i <= maxBin; i++) {
      if (power[i] > bestPower) {
        if (bestBin >= 0) {
          otherPower += bestPower;
          otherCount++;
        }
        bestPower = power[i];
        bestBin = i;
      } else {
        otherPower += power[i];
        otherCount++;
      }
    }

    final avgOther = otherCount > 0 ? otherPower / otherCount : 0.0;

    // Update noise floor estimator with band average.
    _noiseFloor.update(avgOther);

    // Monotonic check: is this frame a single dominant tone?
    final snr = avgOther > 0 ? bestPower / avgOther : 999.0;
    // A frame is monotonic only if there's a real signal (bestBin >= 0)
    // with sufficient peak-to-average ratio. Pure silence has
    // avgOther=0 which makes snr default to 999 — reject it.
    final isMonotonic = bestBin >= 0 && snr >= onThresholdFactor;

    if (isMonotonic) {
      if (_runBin != null && (bestBin - _runBin!).abs() <= 1) {
        // Continue current run at the same frequency.
        _runLen++;
      } else {
        // Frequency changed (or first run). End previous run —
        // this may trigger a lock via the repeat criterion.
        _endRun();
        if (_state == DecoderState.locked) return;

        // Start new run.
        _runBin = bestBin;
        _runLen = 1;
        // Fresh accumulation for this frequency.
        _binPowerAccum.clear();
        _scanFrames = 0;
      }

      // Accumulate power for parabolic interpolation — the peak bin
      // and both its neighbours, every frame, not just whichever bin
      // happened to win. Recording only the winner left the neighbour
      // entries empty whenever one bin consistently dominated (the
      // common case), which silently zeroed the interpolation below
      // and left every lock snapped to the 31.25 Hz FFT bin grid
      // instead of the true frequency (e.g. 700 Hz landing at
      // 687.5 Hz, bin 22 — confirmed against reference recordings).
      for (final b in [bestBin - 1, bestBin, bestBin + 1]) {
        if (b >= 0 && b < power.length) {
          _binPowerAccum[b] = (_binPowerAccum[b] ?? 0) + power[b];
        }
      }
      _scanFrames++;

      // Check for immediate lock: single long stable tone (≥ 500 ms).
      if (_runLen >= _longToneFrames) {
        _lockFromScan();
        return;
      }
    } else {
      // Signal not monotonic — end current run.
      _endRun();
      if (_state == DecoderState.locked) return;
      _runBin = null;
      _runLen = 0;
    }

    onDebugScanning?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      dominantBin: bestBin,
      dominantPower: bestPower,
      avgOtherPower: avgOther,
      snr: snr,
      consecutiveFrames: _runLen,
      persistenceNeeded: _minToneFrames,
      locked: _state == DecoderState.locked,
    );
  }

  /// Ends the current run. If the run was long enough (≥ _minToneFrames)
  /// it counts as a "detection". If this detection matches a previous
  /// one (same bin ±1, within _maxRepeatGapFrames), the decoder locks.
  void _endRun() {
    if (_runBin == null || _runLen < _minToneFrames) return;

    // Check repeat criterion: same frequency, within 2000 ms.
    if (_lastDetectionBin != null &&
        (_runBin! - _lastDetectionBin!).abs() <= 1 &&
        _frameIndex - _lastDetectionEndFrame <= _maxRepeatGapFrames) {
      // Same frequency again → increment detection count.
      _detectionCount++;
      if (_detectionCount >= requiredDetections) {
        // Enough detections at the same frequency → lock.
        _lockFromScan();
        return;
      }
    } else {
      // Different frequency or too long since last detection.
      _detectionCount = 1;
    }

    // Record this detection for future repeat checks.
    _lastDetectionBin = _runBin;
    _lastDetectionEndFrame = _frameIndex;
  }

  void _lockFromScan() {
    if (_binPowerAccum.isEmpty || _scanFrames == 0) return;

    // Find the best accumulated bin.
    var bestBin = -1;
    var bestAvgPower = 0.0;
    _binPowerAccum.forEach((bin, totalPower) {
      final avg = totalPower / _scanFrames;
      if (avg > bestAvgPower) {
        bestAvgPower = avg;
        bestBin = bin;
      }
    });

    if (bestBin < 0) {
      _resetScan();
      return;
    }

    // Harmonic rejection: if best bin is near 2x another
    // significant bin, prefer the lower (fundamental).
    {
      final halfBin = bestBin ~/ 2;
      final minBinIdx = _fft.frequencyToBin(minFreq, sampleRate);
      if (halfBin >= minBinIdx) {
        final halfPower = _binPowerAccum[halfBin] ?? 0;
        final halfAvg = halfPower / _scanFrames;
        if (halfAvg > bestAvgPower * 0.25) {
          bestBin = halfBin;
          bestAvgPower = halfAvg;
        }
      }
    }

    // Parabolic interpolation for sub-bin frequency accuracy.
    final leftPower = _binPowerAccum[bestBin - 1] ?? 0;
    final centerPower = _binPowerAccum[bestBin] ?? 0;
    final rightPower = _binPowerAccum[bestBin + 1] ?? 0;
    final denom = leftPower - 2 * centerPower + rightPower;
    double subBinOffset = 0;
    if (denom.abs() > 1e-10) {
      subBinOffset = 0.5 * (leftPower - rightPower) / denom;
    }
    final freq = (bestBin + subBinOffset) * sampleRate / fftSize;

    onDebugLock?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      freq: freq,
      bestAvgPower: bestAvgPower,
      noiseFloor: 0,
      onThresholdFactor: onThresholdFactor,
    );

    _lock(freq);
  }

  void _lock(double freq) {
    _lockedFreq = freq;
    // Compute bandwidth: fixed value if bandwidth > 0, otherwise
    // relative (±8% of frequency → 16% total width → Q = 6.25).
    final bw = bandwidth > 0 ? bandwidth : freq * bandwidthRatio;
    _detector = IirEnvelopeDetector(
      sampleRate: sampleRate,
      centerFreq: freq,
      bandwidth: bw,
      envelopeCutoffHz: envelopeCutoffHz,
    );
    _noiseFloor.reset();
    _levels.reset();
    _elements.reset();
    _isOn = false;
    _seenFirstOn = false;
    _lastSignalSample = _totalSamples;
    _state = DecoderState.locked;
    onLock?.call(freq);

    _replayPreLock();
  }

  /// Re-decodes the audio captured while the decoder was still
  /// scanning.
  ///
  /// Locking takes a few hundred milliseconds, and until the level
  /// tracker converges the first thresholds are wrong — which is why
  /// the leading character of a transmission was previously lost in
  /// every reference recording (`HELLO` decoding as `SELLO`, `IELLO`,
  /// `EELLO`). The retained audio is filtered once to measure the
  /// mark and space levels, the tracker is seeded with them, and the
  /// same audio is then decoded with converged levels, so the
  /// acquisition window produces real elements instead of fragments.
  void _replayPreLock() {
    if (preLockBufferMs <= 0 || _preLock.length < blockSize * 4) {
      _preLock.clear();
      return;
    }

    final blocks = _preLock.length ~/ blockSize;

    // Pass 1 — filter the retained audio to obtain its envelope. This
    // also leaves the biquad primed with real signal history.
    final envelopes = <double>[];
    for (var i = 0; i < blocks; i++) {
      envelopes.add(
        _detector!.processBlock(
          _preLock.sublist(i * blockSize, (i + 1) * blockSize),
        ),
      );
    }
    _levels.seedFromEnvelopes(envelopes);

    // Pick the level-tracking profile from the keying speed found in
    // this same buffer, before spending it on the real decode. See
    // [fastDitThresholdMs] for why a single fixed profile can't serve
    // both ends of the WPM range.
    final ditEstimateMs = _estimateDitMs(envelopes);
    if (ditEstimateMs != null) {
      final fast = ditEstimateMs < fastDitThresholdMs;
      _levels.reconfigure(
        attackMs: fast ? fastLevelAttackMs : normalLevelAttackMs,
        releaseMs: fast ? fastLevelReleaseMs : normalLevelReleaseMs,
        thresholdOffsetDb: fast
            ? fastThresholdOffsetDb
            : normalThresholdOffsetDb,
      );
    }
    // If no estimate could be made (too few elements in the buffer),
    // _levels keeps running with levelAttackMs/levelReleaseMs/
    // thresholdOffsetDb — the un-gated constructor defaults.

    // Pass 2 — rewind the clock and decode those envelopes with the
    // seeded levels, emitting the elements that were missed.
    _totalSamples -= blocks * blockSize;
    _preLock.clear();

    for (final env in envelopes) {
      _totalSamples += blockSize;
      _trackEnvelope(env);
    }
  }

  /// Rough dit-duration estimate from a batch of already-filtered
  /// envelope values, used only to pick a level-tracking profile.
  ///
  /// Thresholds each sample against a single fixed snapshot of
  /// [LevelTracker.thresholdDb] (no hysteresis, no adaptation) rather
  /// than feeding them through [LevelTracker.process] — that would
  /// perturb the freshly seeded mark/space levels before the real
  /// pass 2 decode gets to use them. A coarse estimate is all a
  /// fast/normal decision needs.
  ///
  /// Returns the 25th-percentile on-run duration in ms, or null if
  /// there aren't at least 3 on-runs to estimate from.
  int? _estimateDitMs(List<double> envelopes) {
    if (!_levels.isReady) return null;
    final threshold = _levels.thresholdDb;
    final blockMs = blockSize * 1000 / sampleRate;

    final onRunsMs = <double>[];
    var isOnLocal = false;
    var runStartBlock = 0;
    for (var i = 0; i < envelopes.length; i++) {
      final wantOn = LevelTracker.toDb(envelopes[i]) > threshold;
      if (wantOn != isOnLocal) {
        if (isOnLocal) onRunsMs.add((i - runStartBlock) * blockMs);
        isOnLocal = wantOn;
        runStartBlock = i;
      }
    }
    if (isOnLocal) onRunsMs.add((envelopes.length - runStartBlock) * blockMs);

    if (onRunsMs.length < 3) return null;
    onRunsMs.sort();
    return onRunsMs[(onRunsMs.length * 0.25).floor()].round();
  }

  // -- Tracking phase --------------------------------------------

  void _track(List<double> samples) {
    // Periodic frequency re-tuning check.
    if (reTuneIntervalBlocks > 0) {
      _reTuneBuffer.addAll(samples);
      if (_reTuneBuffer.length > fftSize) {
        _reTuneBuffer.removeRange(0, _reTuneBuffer.length - fftSize);
      }
      _reTuneCounter++;
      if (_reTuneCounter >= reTuneIntervalBlocks &&
          _reTuneBuffer.length >= fftSize) {
        _reTuneCounter = 0;
        _checkReTune();
        if (_state == DecoderState.scanning) return;
      }
    }

    // Process all samples through the IIR bandpass + envelope.
    _trackEnvelope(_detector!.processBlock(samples));
  }

  /// Runs a quick FFT scan on the recent audio to check whether the
  /// tone frequency has shifted. If the current locked frequency's
  /// power has dropped and a new, significantly different frequency
  /// is dominant, the decoder unlocks and returns to scanning.
  void _checkReTune() {
    if (_reTuneBuffer.length < fftSize) return;

    final power = _fft.powerSpectrum(
      Float64List.fromList(_reTuneBuffer),
    );

    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    // Find the dominant bin in the search band.
    var bestBin = -1;
    var bestPower = 0.0;
    double otherPower = 0;
    var otherCount = 0;
    for (var i = minBin; i <= maxBin; i++) {
      if (power[i] > bestPower) {
        if (bestBin >= 0) {
          otherPower += bestPower;
          otherCount++;
        }
        bestPower = power[i];
        bestBin = i;
      } else {
        otherPower += power[i];
        otherCount++;
      }
    }
    if (bestBin < 0) return;

    final avgOther = otherCount > 0 ? otherPower / otherCount : 0.0;
    final dominantFreq = bestBin * sampleRate / fftSize;

    // Only re-tune if:
    // 1. The dominant frequency is significantly different (> 50 Hz)
    // 2. The new frequency is a real tone (SNR >= onThresholdFactor)
    // 3. The current locked frequency's power is below the average
    //    (the signal at the locked freq is gone)
    if ((dominantFreq - _lockedFreq).abs() > 50 &&
        avgOther > 0 &&
        bestPower / avgOther >= onThresholdFactor) {
      final lockedBin = _fft
          .frequencyToBin(_lockedFreq, sampleRate)
          .clamp(0, power.length - 1);
      final lockedPower = power[lockedBin];

      if (lockedPower < avgOther * 2) {
        // Signal at the locked frequency is gone, and a new tone
        // has appeared — unlock and re-scan.
        _unlock();
      }
    }
  }

  /// Thresholds one envelope value and records any transition.
  void _trackEnvelope(double env) {
    final blockMs = blockSize * 1000 / sampleRate;
    final wantOn = _levels.process(env, blockMs);

    // Auto-unlock (only if signalTimeoutMs > 0).
    // Default: permanent lock, no unlock during listening.
    if (signalTimeoutMs > 0) {
      if (wantOn) _lastSignalSample = _totalSamples;
      final silenceMs = (_totalSamples - _lastSignalSample) * 1000 / sampleRate;
      if (_seenFirstOn && silenceMs >= signalTimeoutMs) {
        _unlock();
        return;
      }
    }

    if (!_levels.isReady) return;

    onDebugTracking?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      freq: _lockedFreq,
      power: env,
      envelope: env,
      noiseFloor: _levels.markDb ?? 0,
      onThreshold: _levels.thresholdDb + hysteresisDb,
      offThreshold: _levels.thresholdDb - hysteresisDb,
      isOn: _isOn,
    );

    if (wantOn != _isOn) {
      _isOn = wantOn;
      if (wantOn) _seenFirstOn = true;
      _onTransition();
    }
  }

  void _unlock() {
    // Emit the final off-element so the MorseDecoder sees the gap
    // as a word boundary rather than losing it entirely.
    _elements.flush();
    onUnlock?.call();
    _state = DecoderState.scanning;
    _detector = null;
    _isOn = false;
    _seenFirstOn = false;
    _lockedFreq = 0;
    _lastSignalSample = 0;
    _levels.reset();
    _elements.reset();
    _reTuneBuffer.clear();
    _reTuneCounter = 0;
    _resetScan();
  }

  void _resetScan() {
    _runBin = null;
    _runLen = 0;
    _lastDetectionBin = null;
    _lastDetectionEndFrame = 0;
    _detectionCount = 0;
    _binPowerAccum.clear();
    _scanFrames = 0;
    _noiseFloor.reset();
  }

  void _onTransition() {
    _elements.transition(
      nowOn: _isOn,
      timeMs: _totalSamples * 1000 / sampleRate,
    );
  }

  void _emit(DecodedElement element) {
    onDebugTransition?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      isOn: element.isOn,
      durationMs: element.durationMs,
    );
    onElement?.call(element);
  }

  /// Emits any element still held back by the merge lookahead.
  ///
  /// Call when the audio stream ends so the final element is not lost.
  /// Safe to call repeatedly.
  void flush() => _elements.flush();

  /// Resets the decoder to the scanning state.
  void reset() {
    _state = DecoderState.scanning;
    _buffer.clear();
    _detector = null;
    _isOn = false;
    _seenFirstOn = false;
    _levels.reset();
    _elements.reset();
    _preLock.clear();
    _reTuneBuffer.clear();
    _reTuneCounter = 0;
    _totalSamples = 0;
    _lockedFreq = 0;
    _lastSignalSample = 0;
    _frameIndex = 0;
    _resetScan();
  }
}
