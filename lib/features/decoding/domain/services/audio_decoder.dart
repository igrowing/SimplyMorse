import 'dart:typed_data';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/envelope_detector.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';
import 'package:simply_morse/features/decoding/domain/services/goertzel.dart';
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

/// Audio decoding pipeline implementing the CW decoder
/// technique:
///
/// 1. **Calibration** — listens for [calibrationMs] (2 s by
///    default) collecting FFT frames over 400-1000 Hz to
///    find the dominant sustained tone.
/// 2. **Lock** — switches to an efficient Goertzel filter at
///    the detected frequency.
/// 3. **Track** — fast-attack / slow-release envelope with
///    hysteresis detects on/off transitions.
/// 4. **No drift** — once locked, the frequency does not
///    change until [reset] is called (user clicks Clear).
///
/// Emits [DecodedElement]s via [onElement] as on/off
/// transitions are detected.
class AudioDecoder {
  AudioDecoder({
    this.sampleRate = 8000,
    this.minFreq = 400,
    this.maxFreq = 1000,
    this.fftSize = 256,
    this.goertzelBlockSize = 80,
    this.calibrationMs = 2000,
    this.attackMs = 2,
    this.releaseMs = 50,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
  }) {
    _fft = FFT(fftSize);
    _hopMs = goertzelBlockSize * 1000 / sampleRate;
  }

  // Configuration
  final int sampleRate;
  final double minFreq;
  final double maxFreq;
  final int fftSize;
  final int goertzelBlockSize;
  final int calibrationMs;
  final double attackMs;
  final double releaseMs;
  final double onThresholdFactor;
  final double offThresholdFactor;

  // Internal components
  late final FFT _fft;
  late final double _hopMs;
  final _envelope = EnvelopeDetector();
  final _noiseFloor = NoiseFloorEstimator();

  // State machine
  DecoderState _state = DecoderState.calibrating;
  DecoderState get state => _state;

  // Calibration tracking
  final Map<int, double> _binPowerAccum = {};
  int _calibrationStartSample = 0;
  int _calibrationFrames = 0;

  // Tracking state
  Goertzel? _goertzel;
  double _lockedFreq = 0;

  /// The frequency the decoder has locked onto, in Hz.
  /// Returns 0 while calibrating.
  double get lockedFrequency => _lockedFreq;

  /// Whether the decoder is currently in the calibration phase.
  bool get isCalibrating => _state == DecoderState.calibrating;

  // Envelope / on-off state
  bool _isOn = false;
  int _transitionSample = 0;
  int _totalSamples = 0;

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

  int get _windowSize =>
      _state == DecoderState.locked ? goertzelBlockSize : fftSize;

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

    // Accumulate power per bin across all calibration frames
    for (var i = minBin; i <= maxBin; i++) {
      _binPowerAccum[i] = (_binPowerAccum[i] ?? 0) + power[i];
    }

    // Also update noise floor with band average
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

    // Check if calibration period is over
    if (elapsedMs >= calibrationMs) {
      _lockFromCalibration();
    }
  }

  void _lockFromCalibration() {
    if (_binPowerAccum.isEmpty || !_noiseFloor.isReady) {
      // Not enough data — extend calibration
      _calibrationStartSample = _totalSamples;
      return;
    }

    // Find the bin with the highest average power
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
      // No signal found — restart calibration
      _binPowerAccum.clear();
      _calibrationFrames = 0;
      _calibrationStartSample = _totalSamples;
      return;
    }

    final freq = _fft.binFrequency(bestBin, sampleRate);
    final floor = _noiseFloor.noiseFloor;

    // Verify the peak is significantly above noise floor
    if (bestAvgPower <= floor * onThresholdFactor) {
      // Signal too weak — restart calibration
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
      noiseFloor: floor,
      onThresholdFactor: onThresholdFactor,
    );

    _lock(freq);
  }

  void _lock(double freq) {
    _lockedFreq = freq;
    _goertzel = Goertzel(
      sampleRate: sampleRate,
      targetFreq: freq,
      blockSize: goertzelBlockSize,
    );
    _envelope.reset();
    _isOn = false;
    _state = DecoderState.locked;
    _transitionSample = _totalSamples;
    onLock?.call(freq);
  }

  // -- Tracking phase --------------------------------------------

  void _track(List<double> samples) {
    final power = _goertzel!.process(samples);
    final env = _envelope.process(power, hopMs: _hopMs);

    final floor = _noiseFloor.noiseFloor;
    final onThreshold = floor * onThresholdFactor;
    final offThreshold = floor * offThresholdFactor;

    onDebugTracking?.call(
      totalSamples: _totalSamples,
      sampleRate: sampleRate,
      freq: _lockedFreq,
      power: power,
      envelope: env,
      noiseFloor: floor,
      onThreshold: onThreshold,
      offThreshold: offThreshold,
      isOn: _isOn,
    );

    if (!_isOn && env > onThreshold) {
      // Off → On transition
      _emitElement(false);
      _isOn = true;
      _transitionSample = _totalSamples;
    } else if (_isOn && env < offThreshold) {
      // On → Off transition
      _emitElement(true);
      _isOn = false;
      _transitionSample = _totalSamples;
    }
  }

  void _emitElement(bool isOn) {
    final durationSamples = _totalSamples - _transitionSample;
    final durationMs = (durationSamples * 1000 / sampleRate).round();

    if (durationMs <= 0) return;

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
    _envelope.reset();
    _noiseFloor.reset();
    _goertzel = null;
    _isOn = false;
    _totalSamples = 0;
    _transitionSample = 0;
    _lockedFreq = 0;
    _binPowerAccum.clear();
    _calibrationFrames = 0;
    _calibrationStartSample = 0;
  }
}
