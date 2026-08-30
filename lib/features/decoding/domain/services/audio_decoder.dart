import 'dart:typed_data';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';
import 'package:simply_morse/features/decoding/domain/services/iir_envelope_detector.dart';
import 'package:simply_morse/features/decoding/domain/services/noise_floor_estimator.dart';

/// Debug log callback for calibration frames.
typedef DebugCalibrationCallback =
    void Function({
      required int totalSamples,
      required int sampleRate,
      required double avgPower,
      required double noiseFloor,
      required int calibrationFrames,
      required double elapsedMs,
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
  /// Calibration phase — collecting FFT frames for
  /// [AudioDecoder.calibrationMs] to find the dominant
  /// tone frequency in the target band.
  calibrating,

  /// Locked on a frequency — tracking the on/off envelope.
  locked,
}

/// Audio decoding pipeline using IIR bandpass filtering.
///
/// Pipeline:
/// 1. **Calibration** — collects FFT frames over 400–1000 Hz
///    for [calibrationMs] (2 s) to find the dominant tone.
/// 2. **Lock** — creates an IIR bandpass filter (biquad)
///    centered on the detected frequency with a configurable
///    bandwidth (default 80 Hz). This replaces the Goertzel
///    single-frequency approach, which was sensitive to
///    frequency mismatch, drift, and beating.
/// 3. **Track** — processes audio sample-by-sample through the
///    bandpass filter, rectifies, and lowpass-filters to produce
///    a smooth envelope. Hysteresis thresholding detects on/off
///    transitions. The noise floor is continuously updated from
///    raw envelope values during confirmed off periods.
/// 4. **No drift** — once locked, the frequency does not change
///    until [reset] is called.
///
/// Emits [DecodedElement]s via [onElement] as transitions are
/// detected. Elements shorter than [minElementMs] are filtered.
class AudioDecoder {
  AudioDecoder({
    this.sampleRate = 8000,
    this.minFreq = 400,
    this.maxFreq = 1000,
    this.fftSize = 256,
    this.blockSize = 80,
    this.calibrationMs = 2000,
    this.bandwidth = 80.0,
    this.envelopeCutoffHz = 40.0,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
    this.minElementMs = 30,
  }) {
    _fft = FFT(fftSize);
    _hopMs = blockSize * 1000 / sampleRate;
  }

  // Configuration
  final int sampleRate;
  final double minFreq;
  final double maxFreq;
  final int fftSize;
  final int blockSize;
  final int calibrationMs;
  final double bandwidth;
  final double envelopeCutoffHz;
  final double onThresholdFactor;
  final double offThresholdFactor;
  final int minElementMs;

  // Internal components
  late final FFT _fft;
  late final double _hopMs;
  final _noiseFloor = NoiseFloorEstimator();

  // State machine
  DecoderState _state = DecoderState.calibrating;
  DecoderState get state => _state;

  // Calibration tracking
  final Map<int, double> _binPowerAccum = {};
  int _calibrationStartSample = 0;
  int _calibrationFrames = 0;

  // Tracking state
  IirEnvelopeDetector? _detector;
  double _lockedFreq = 0;

  /// The frequency the decoder has locked onto, in Hz.
  /// Returns 0 while calibrating.
  double get lockedFrequency => _lockedFreq;

  /// Whether the decoder is currently in the calibration phase.
  bool get isCalibrating => _state == DecoderState.calibrating;

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

  // -- Debug callbacks --
  DebugCalibrationCallback? onDebugCalibration;
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
      case DecoderState.calibrating:
        _calibrate(samples);
      case DecoderState.locked:
        _track(samples);
    }
  }

  // -- Calibration phase -----------------------------------------

  void _calibrate(List<double> samples) {
    final power = _fft.powerSpectrum(Float64List.fromList(samples));

    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    for (var i = minBin; i <= maxBin; i++) {
      _binPowerAccum[i] = (_binPowerAccum[i] ?? 0) + power[i];
    }

    double bandEnergy = 0;
    var bandCount = 0;
    for (var i = minBin; i <= maxBin; i++) {
      bandEnergy += power[i];
      bandCount++;
    }
    final avgPower = bandCount > 0 ? bandEnergy / bandCount : 0.0;
    _noiseFloor.update(avgPower);

    _calibrationFrames++;

    final elapsedMs =
        (_totalSamples - _calibrationStartSample) * 1000 / sampleRate;

    onDebugCalibration?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      avgPower: avgPower,
      noiseFloor: _noiseFloor.noiseFloor,
      calibrationFrames: _calibrationFrames,
      elapsedMs: elapsedMs,
    );

    if (elapsedMs >= calibrationMs) {
      _lockFromCalibration();
    }
  }

  void _lockFromCalibration() {
    if (_binPowerAccum.isEmpty || !_noiseFloor.isReady) {
      _calibrationStartSample = _totalSamples;
      return;
    }

    var bestBin = -1;
    var bestAvgPower = 0.0;
    _binPowerAccum.forEach((bin, totalPower) {
      final avg = totalPower / _calibrationFrames;
      if (avg > bestAvgPower) {
        bestAvgPower = avg;
        bestBin = bin;
      }
    });

    if (bestBin < 0) {
      _binPowerAccum.clear();
      _calibrationFrames = 0;
      _calibrationStartSample = _totalSamples;
      return;
    }

    // Noise floor from all non-peak bins
    double otherPower = 0;
    var otherCount = 0;
    _binPowerAccum.forEach((bin, totalPower) {
      if (bin != bestBin) {
        otherPower += totalPower / _calibrationFrames;
        otherCount++;
      }
    });
    final noiseAvg = otherCount > 0 ? otherPower / otherCount : 0.0;

    // Harmonic rejection: if best bin is near 2× another
    // significant bin, prefer the lower (fundamental).
    {
      final halfBin = bestBin ~/ 2;
      final minBinIdx = _fft.frequencyToBin(minFreq, sampleRate);
      if (halfBin >= minBinIdx) {
        final halfPower = _binPowerAccum[halfBin] ?? 0;
        final halfAvg = halfPower / _calibrationFrames;
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

    // Verify signal is strong enough.
    if (bestAvgPower <= noiseAvg * onThresholdFactor) {
      _binPowerAccum.clear();
      _calibrationFrames = 0;
      _calibrationStartSample = _totalSamples;
      return;
    }

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

  /// Resets the decoder to the calibration state.
  void reset() {
    _state = DecoderState.calibrating;
    _buffer.clear();
    _detector = null;
    _noiseFloor.reset();
    _isOn = false;
    _peakEnvelope = 0;
    _seenFirstOn = false;
    _totalSamples = 0;
    _transitionSample = 0;
    _lockedFreq = 0;
    _binPowerAccum.clear();
    _calibrationFrames = 0;
    _calibrationStartSample = 0;
  }
}
