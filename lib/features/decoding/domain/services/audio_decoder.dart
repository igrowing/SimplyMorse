import 'dart:typed_data';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/envelope_detector.dart';
import 'package:simply_morse/features/decoding/domain/services/fft.dart';
import 'package:simply_morse/features/decoding/domain/services/goertzel.dart';
import 'package:simply_morse/features/decoding/domain/services/noise_floor_estimator.dart';

/// State of the audio decoding pipeline.
enum DecoderState {
  /// Wideband FFT scan looking for a candidate tone.
  scanning,

  /// Candidate found — confirming across consecutive frames.
  confirming,

  /// Locked on a frequency — tracking the on/off envelope.
  locked,
}

/// Audio decoding pipeline implementing the CW decoder
/// technique described in the SimplyMorse spec:
///
/// 1. Wideband FFT scan over 400-1000 Hz to find the tone.
/// 2. Adaptive noise floor (running median).
/// 3. Confirm the same bin across several frames before locking.
/// 4. Lock with Goertzel for efficient single-frequency tracking.
/// 5. Fast-attack / slow-release envelope with hysteresis.
/// 6. Adaptive dot-length estimation from recent on-durations.
/// 7. Periodic re-scan if the signal is lost or produces garbage.
///
/// Emits [DecodedElement]s via [onElement] as on/off transitions
/// are detected.
class AudioDecoder {
  AudioDecoder({
    this.sampleRate = 8000,
    this.minFreq = 400,
    this.maxFreq = 1000,
    this.fftSize = 256,
    this.goertzelBlockSize = 80,
    this.confirmFrames = 3,
    this.attackMs = 2,
    this.releaseMs = 50,
    this.onThresholdFactor = 4,
    this.offThresholdFactor = 2,
    this.rescanIntervalMs = 2000,
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
  final int confirmFrames;
  final double attackMs;
  final double releaseMs;
  final double onThresholdFactor;
  final double offThresholdFactor;
  final int rescanIntervalMs;

  // Internal components
  late final FFT _fft;
  late final double _hopMs;
  final _envelope = EnvelopeDetector();
  final _noiseFloor = NoiseFloorEstimator();

  // State machine
  DecoderState _state = DecoderState.scanning;
  DecoderState get state => _state;

  // Tracking state
  Goertzel? _goertzel;
  double _lockedFreq = 0;
  int _confirmCount = 0;
  double _candidateFreq = 0;
  int _candidateBin = -1;

  // Envelope / on-off state
  bool _isOn = false;
  int _transitionSample = 0;
  int _totalSamples = 0;

  // Re-scan timer
  int _lastScanSample = 0;

  // Sample buffer
  final List<double> _buffer = [];

  // Output
  void Function(DecodedElement element)? onElement;

  /// Processes a batch of audio samples.
  void processSamples(List<double> samples) {
    _buffer.addAll(samples);
    _totalSamples += samples.length;

    while (_buffer.length >= _windowSize) {
      final window = _buffer.sublist(0, _windowSize);
      _buffer.removeRange(0, _windowSize);
      _processWindow(window);
    }
  }

  int get _windowSize =>
      _state == DecoderState.locked ? goertzelBlockSize : fftSize;

  void _processWindow(List<double> samples) {
    switch (_state) {
      case DecoderState.scanning:
        _scan(samples);
      case DecoderState.confirming:
        _confirm(samples);
      case DecoderState.locked:
        _track(samples);
    }
  }

  // -- Scanning phase ---------------------------------------------

  void _scan(List<double> samples) {
    final power = _fft.powerSpectrum(Float64List.fromList(samples));

    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    double maxPower = 0;
    var peakBin = minBin;
    double bandEnergy = 0;
    var bandCount = 0;

    for (var i = minBin; i <= maxBin; i++) {
      bandEnergy += power[i];
      bandCount++;
      if (power[i] > maxPower) {
        maxPower = power[i];
        peakBin = i;
      }
    }

    final avgPower = bandCount > 0 ? bandEnergy / bandCount : 0.0;
    _noiseFloor.update(avgPower);

    if (!_noiseFloor.isReady) return;

    final floor = _noiseFloor.noiseFloor;
    if (maxPower > floor * onThresholdFactor) {
      _candidateFreq = _fft.binFrequency(peakBin, sampleRate);
      _candidateBin = peakBin;
      _confirmCount = 1;
      _state = DecoderState.confirming;
    }
  }

  // -- Confirming phase ------------------------------------------

  void _confirm(List<double> samples) {
    final power = _fft.powerSpectrum(Float64List.fromList(samples));

    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    double maxPower = 0;
    var peakBin = minBin;
    for (var i = minBin; i <= maxBin; i++) {
      if (power[i] > maxPower) {
        maxPower = power[i];
        peakBin = i;
      }
    }

    // Check if the peak is at the candidate bin (±1 tolerance)
    if ((peakBin - _candidateBin).abs() <= 1) {
      _confirmCount++;
      if (_confirmCount >= confirmFrames) {
        _lock(_candidateFreq);
      }
    } else {
      _state = DecoderState.scanning;
      _confirmCount = 0;
    }
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
    _lastScanSample = _totalSamples;
  }

  // -- Tracking phase --------------------------------------------

  void _track(List<double> samples) {
    final power = _goertzel!.process(samples);
    final env = _envelope.process(power, hopMs: _hopMs);

    final floor = _noiseFloor.noiseFloor;
    final onThreshold = floor * onThresholdFactor;
    final offThreshold = floor * offThresholdFactor;

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

    // Periodic re-scan
    if (_totalSamples - _lastScanSample >
        rescanIntervalMs * sampleRate ~/ 1000) {
      _checkSignal(samples);
    }
  }

  void _checkSignal(List<double> samples) {
    final power = _fft.powerSpectrum(Float64List.fromList(samples));
    final minBin = _fft.frequencyToBin(minFreq, sampleRate);
    final maxBin = _fft
        .frequencyToBin(maxFreq, sampleRate)
        .clamp(0, power.length - 1);

    double maxPower = 0;
    var peakBin = minBin;
    for (var i = minBin; i <= maxBin; i++) {
      if (power[i] > maxPower) {
        maxPower = power[i];
        peakBin = i;
      }
    }

    final floor = _noiseFloor.noiseFloor;
    if (maxPower < floor * offThresholdFactor) {
      // Signal lost — unlock and re-scan
      _emitElement(_isOn); // flush current state
      _isOn = false;
      _goertzel = null;
      _envelope.reset();
      _state = DecoderState.scanning;
    } else {
      // Update locked frequency if drifted
      final newFreq = _fft.binFrequency(peakBin, sampleRate);
      if ((newFreq - _lockedFreq).abs() > 30) {
        _lockedFreq = newFreq;
        _goertzel = Goertzel(
          sampleRate: sampleRate,
          targetFreq: newFreq,
          blockSize: goertzelBlockSize,
        );
      }
      _lastScanSample = _totalSamples;
    }
  }

  void _emitElement(bool isOn) {
    final durationSamples = _totalSamples - _transitionSample;
    final durationMs = (durationSamples * 1000 / sampleRate).round();

    if (durationMs <= 0) return;

    onElement?.call(
      DecodedElement(isOn: isOn, durationMs: durationMs),
    );
  }

  /// Resets the decoder to the scanning state.
  void reset() {
    _state = DecoderState.scanning;
    _buffer.clear();
    _envelope.reset();
    _noiseFloor.reset();
    _goertzel = null;
    _isOn = false;
    _confirmCount = 0;
    _totalSamples = 0;
    _transitionSample = 0;
    _lastScanSample = 0;
  }
}
