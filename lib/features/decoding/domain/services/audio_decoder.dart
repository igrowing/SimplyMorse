import 'dart:typed_data';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';
import 'package:simply_morse/features/decoding/domain/services/iir_envelope_detector.dart';
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
/// - Detected for at least 50 ms (~2 FFT frames at 32 ms/frame)
/// - Either:
///   - A single continuous tone lasting ≥ 500 ms (a long dah
///     at stable power is sufficient evidence), OR
///   - Two or more detections (each ≥ 50 ms) of the same
///     frequency within 2000 ms (repeating tone pattern)
///
/// Pipeline:
/// 1. **Scanning** — continuously runs FFT frames over 400–1000 Hz.
///    Each frame checks if the dominant bin has SNR ≥ 4 (monotonic).
///    Runs of consecutive monotonic frames are tracked as "detection
///    events". The decoder locks when either:
///    - A single run lasts ≥ 500 ms (15 frames), OR
///    - Two detection events of the same frequency occur within 2000 ms
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
    this.blockSize = 80,
    this.signalTimeoutMs = 0,
    this.bandwidth = 0,
    this.bandwidthRatio = 0.16,
    this.envelopeCutoffHz = 40.0,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
    this.minElementMs = 30,
  }) {
    _fft = FFT(fftSize);
    _hopMs = blockSize * 1000 / sampleRate;
    _frameMs = fftSize * 1000 / sampleRate;
    // Derived scanning thresholds (computed from frame rate).
    _minToneFrames = (160 / _frameMs).ceil(); // ~5 frames = 160 ms
    _longToneFrames = (500 / _frameMs).ceil(); // ~16 frames = 500 ms
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
  final int minElementMs;

  // Derived scanning thresholds
  late final int _minToneFrames;
  late final int _longToneFrames;
  late final int _maxRepeatGapFrames;

  // Internal components
  late final FFT _fft;
  late final double _hopMs;
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
  static const int _requiredDetections = 3; // lock after 3 repeat detections
  int _frameIndex = 0; // total scanning frames processed
  final Map<int, double> _binPowerAccum = {};
  int _scanFrames = 0; // frames accumulated for parabolic interpolation

  // Tracking state
  IirEnvelopeDetector? _detector;
  double _lockedFreq = 0;
  int _lastSignalSample = 0;

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
  double _peakEnvelope = 0;
  int _transitionSample = 0;
  int _totalSamples = 0;
  bool _seenFirstOn = false;

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
  // - A "detection" = a run of ≥ _minToneFrames (50 ms).
  // - Lock when: a single run ≥ _longToneFrames (500 ms), OR
  //   two detections of the same frequency within _maxRepeatGapFrames
  //   (2000 ms).

  void _scan(List<double> samples) {
    _frameIndex++;

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

      // Accumulate power for parabolic interpolation.
      _binPowerAccum[bestBin] = (_binPowerAccum[bestBin] ?? 0) + bestPower;
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
      if (_detectionCount >= _requiredDetections) {
        // Three detections at the same frequency → lock!
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
    _isOn = false;
    _peakEnvelope = 0;
    _seenFirstOn = false;
    _lastSignalSample = _totalSamples;
    _state = DecoderState.locked;
    _transitionSample = _totalSamples;
    onLock?.call(freq);
  }

  // -- Tracking phase --------------------------------------------

  void _track(List<double> samples) {
    // Process all samples through the IIR bandpass + envelope.
    final env = _detector!.processBlock(samples);

    // Peak envelope with slow decay for adaptive thresholding.
    _peakEnvelope *= 0.999;
    if (env > _peakEnvelope) {
      _peakEnvelope = env;
    }

    // Collect noise floor only when the envelope is clearly
    // below the signal level (< 30% of peak). This prevents
    // tone-on frames (where the envelope is high but the
    // ON transition hasn't fired yet) from contaminating the
    // noise floor estimate.
    if (env < _peakEnvelope * 0.3) {
      _noiseFloor.update(env);
    }

    // Auto-unlock (only if signalTimeoutMs > 0).
    // Default: permanent lock, no unlock during listening.
    if (signalTimeoutMs > 0) {
      if (env > _peakEnvelope * 0.15) {
        _lastSignalSample = _totalSamples;
      }
      final silenceMs = (_totalSamples - _lastSignalSample) * 1000 / sampleRate;
      if (_seenFirstOn && silenceMs >= signalTimeoutMs) {
        _unlock();
        return;
      }
    }

    // Compute thresholds using noise-floor-relative strategy
    // once enough data is collected; fall back to peak-only
    // thresholds (with a higher off ratio to avoid getting
    // stuck) for the first few frames.
    final double onThreshold;
    final double offThreshold;
    final double debugNoiseFloor;

    if (_noiseFloor.isReady) {
      final minRef = _noiseFloor.noiseFloor;
      final range = _peakEnvelope - minRef;
      if (range <= 0) return;
      onThreshold = minRef + range * 0.5;
      offThreshold = minRef + range * 0.25;
      debugNoiseFloor = minRef;
    } else {
      if (_peakEnvelope <= 0) return;
      onThreshold = _peakEnvelope * 0.5;
      offThreshold = _peakEnvelope * 0.40;
      debugNoiseFloor = 0;
    }

    onDebugTracking?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      freq: _lockedFreq,
      power: env,
      envelope: env,
      noiseFloor: debugNoiseFloor,
      onThreshold: onThreshold,
      offThreshold: offThreshold,
      isOn: _isOn,
    );

    if (!_isOn && env > onThreshold) {
      // Off -> On transition
      _seenFirstOn = true;
      _emitElement(false);
      _isOn = true;
      _transitionSample = _totalSamples;
    } else if (_isOn && env < offThreshold) {
      // On -> Off transition
      _emitElement(true);
      _isOn = false;
      _transitionSample = _totalSamples;
    }
  }

  void _unlock() {
    // Emit the final off-element so the MorseDecoder sees the gap
    // as a word boundary rather than losing it entirely.
    if (!_isOn) {
      _emitElement(false);
    }
    onUnlock?.call();
    _state = DecoderState.scanning;
    _detector = null;
    _isOn = false;
    _peakEnvelope = 0;
    _seenFirstOn = false;
    _lockedFreq = 0;
    _transitionSample = 0;
    _lastSignalSample = 0;
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

  void _emitElement(bool isOn) {
    final durationSamples = _totalSamples - _transitionSample;
    final durationMs = (durationSamples * 1000 / sampleRate).round();

    if (durationMs <= 0) return;

    if (durationMs < minElementMs) return;

    onDebugTransition?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      isOn: isOn,
      durationMs: durationMs,
    );

    onElement?.call(
      DecodedElement(isOn: isOn, durationMs: durationMs),
    );
  }

  /// Resets the decoder to the scanning state.
  void reset() {
    _state = DecoderState.scanning;
    _buffer.clear();
    _detector = null;
    _isOn = false;
    _peakEnvelope = 0;
    _seenFirstOn = false;
    _totalSamples = 0;
    _transitionSample = 0;
    _lockedFreq = 0;
    _lastSignalSample = 0;
    _frameIndex = 0;
    _resetScan();
  }
}
