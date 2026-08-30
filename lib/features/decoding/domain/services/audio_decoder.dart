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
  /// find a sustained monotonic tone. Locks when the same
  /// frequency bin has been dominant and above the noise floor
  /// for enough consecutive frames.
  scanning,

  /// Locked on a frequency — tracking the on/off envelope.
  locked,
}

/// Audio decoding pipeline using IIR bandpass filtering.
///
/// Pipeline:
/// 1. **Scanning** — continuously runs FFT frames over 400–1000 Hz.
///    Each frame, the dominant bin is identified. When the same bin
///    (±1 tolerance) has been dominant and at least
///    [onThresholdFactor]x above the noise floor for
///    [scanPersistenceFrames] consecutive frames (~320 ms), the
///    decoder locks. This rejects voice, music, and brief noise
///    spikes that jump between frequency bins. There is no fixed
///    timeout — the decoder scans indefinitely until a clear
///    monotonic tone appears.
/// 2. **Lock** — creates an IIR bandpass filter (biquad) centered on
///    the detected frequency with a configurable bandwidth (default
///    80 Hz). Parabolic interpolation gives sub-bin frequency accuracy.
/// 3. **Track** — processes audio sample-by-sample through the bandpass
///    filter, rectifies, and lowpass-filters to produce a smooth
///    envelope. Hysteresis thresholding detects on/off transitions.
///    The noise floor is continuously updated during confirmed off
///    periods. If the envelope stays at the noise floor for more than
///    [signalTimeoutMs], the decoder unlocks and returns to scanning.
/// 4. **No drift** — once locked, the frequency does not change until
///    the signal disappears or [reset] is called.
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
    this.scanPersistenceFrames = 10,
    this.signalTimeoutMs = 30000,
    this.bandwidth = 80.0,
    this.envelopeCutoffHz = 40.0,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
    this.minElementMs = 30,
  }) {
    _fft = FFT(fftSize);
    _hopMs = blockSize * 1000 / sampleRate;
    _frameMs = fftSize * 1000 / sampleRate;
  }

  // Configuration
  final int sampleRate;
  final double minFreq;
  final double maxFreq;
  final int fftSize;
  final int blockSize;

  /// Number of consecutive FFT frames where the same frequency bin
  /// must be dominant (and above the noise floor) before locking.
  /// At 8 kHz / 256-sample FFT, each frame is 32 ms, so 10 frames
  /// is about 320 ms. Higher values reject voice/music better but
  /// delay locking.
  final int scanPersistenceFrames;

  /// If the envelope stays at the noise floor for this many
  /// milliseconds during tracking, the decoder unlocks and returns
  /// to scanning. Default 30 seconds — long enough for normal
  /// Morse word gaps even at 3 WPM (2.8 s) plus thinking time.
  final int signalTimeoutMs;

  final double bandwidth;
  final double envelopeCutoffHz;
  final double onThresholdFactor;
  final double offThresholdFactor;
  final int minElementMs;

  // Internal components
  late final FFT _fft;
  late final double _hopMs;
  late final double _frameMs;
  final _noiseFloor = NoiseFloorEstimator();

  // State machine
  DecoderState _state = DecoderState.scanning;
  DecoderState get state => _state;

  // Scanning state
  int _consecutiveFrames = 0;
  int _lastDominantBin = -1;
  final Map<int, double> _binPowerAccum = {};
  int _scanFrames = 0;

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
  /// to scanning (signal timeout).
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

  void _scan(List<double> samples) {
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

    // Update noise floor estimator with band average (always,
    // even during silence — this helps establish a baseline).
    _noiseFloor.update(avgOther);

    // Persistence check: the same bin (+/-1) must be dominant for
    // N consecutive frames AND above the noise floor.
    final snr = avgOther > 0 ? bestPower / avgOther : 999.0;
    final isStrongEnough = snr >= onThresholdFactor;

    if (isStrongEnough) {
      if (_lastDominantBin >= 0 && (bestBin - _lastDominantBin).abs() <= 1) {
        _consecutiveFrames++;
      } else {
        // New streak — clear accumulation from any previous streak.
        _binPowerAccum.clear();
        _scanFrames = 0;
        _consecutiveFrames = 1;
      }
      _lastDominantBin = bestBin;

      // Accumulate power ONLY during the persistence streak so
      // parabolic interpolation uses only tone frames, not noise.
      _binPowerAccum[bestBin] = (_binPowerAccum[bestBin] ?? 0) + bestPower;
      _scanFrames++;
    } else {
      _consecutiveFrames = 0;
      _lastDominantBin = -1;
    }

    onDebugScanning?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      dominantBin: bestBin,
      dominantPower: bestPower,
      avgOtherPower: avgOther,
      snr: snr,
      consecutiveFrames: _consecutiveFrames,
      persistenceNeeded: scanPersistenceFrames,
      locked: false,
    );

    if (_consecutiveFrames >= scanPersistenceFrames && isStrongEnough) {
      _lockFromScan();
    }
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
    _detector = IirEnvelopeDetector(
      sampleRate: sampleRate,
      centerFreq: freq,
      bandwidth: bandwidth,
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

    // Track when we last saw a signal above the noise floor.
    // If we've been in silence for too long, unlock and return
    // to scanning.
    if (env > _peakEnvelope * 0.15) {
      _lastSignalSample = _totalSamples;
    }

    final silenceMs = (_totalSamples - _lastSignalSample) * 1000 / sampleRate;
    if (_seenFirstOn && silenceMs >= signalTimeoutMs) {
      _unlock();
      return;
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
    _consecutiveFrames = 0;
    _lastDominantBin = -1;
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
    _resetScan();
  }
}
