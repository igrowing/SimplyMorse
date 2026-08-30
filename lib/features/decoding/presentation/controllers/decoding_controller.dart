import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:simply_morse/features/decoding/data/audio_debug_logger.dart';
import 'package:simply_morse/features/decoding/data/video_debug_logger.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';

/// State management for a decoding session.
///
/// Manages the UI state (idle / listening / paused) and holds
/// the decoded text. Wires the appropriate pipeline based on
/// the mode:
/// - Audio: AudioCapture → AudioDecoder → MorseDecoder
/// - Video: CameraCapture → VideoDecoder → MorseDecoder
class DecodingController extends ChangeNotifier {
  DecodingController({
    required MorseDecoder morseDecoder,
    AudioDecoder? audioDecoder,
    AudioCapture? audioCapture,
    VideoDecoder? videoDecoder,
    CameraCapture? cameraCapture,
    AudioDebugLogger? debugLogger,
    VideoDebugLogger? videoDebugLogger,
  }) : _morseDecoder = morseDecoder,
       _audioDecoder = audioDecoder,
       _audioCapture = audioCapture,
       _videoDecoder = videoDecoder,
       _cameraCapture = cameraCapture,
       _debugLogger = debugLogger,
       _videoDebugLogger = videoDebugLogger;

  final MorseDecoder _morseDecoder;
  final AudioDecoder? _audioDecoder;
  final AudioCapture? _audioCapture;
  final VideoDecoder? _videoDecoder;
  final CameraCapture? _cameraCapture;
  final AudioDebugLogger? _debugLogger;
  final VideoDebugLogger? _videoDebugLogger;

  StreamSubscription<List<double>>? _audioSub;
  final List<DecodedElement> _elements = [];

  DecodingMode _mode = DecodingMode.audio;
  DecodingStatus _status = DecodingStatus.idle;
  String _decodedText = '';
  double _lockedFrequency = 0;

  /// Whether debug logging is enabled.
  bool get isDebugLoggingEnabled => _debugLogger?.enabled ?? false;

  /// Path to the current audio debug log file, if logging is active.
  String? get debugLogPath => _debugLogger?.logFilePath;

  /// Path to the current video debug log file, if logging is active.
  String? get videoDebugLogPath => _videoDebugLogger?.logFilePath;

  /// Whether video debug logging is enabled.
  bool get isVideoDebugLoggingEnabled => _videoDebugLogger?.enabled ?? false;

  DecodingMode get mode => _mode;
  DecodingStatus get status => _status;
  String get decodedText => _decodedText;

  /// The frequency the audio decoder has locked onto (Hz).
  /// Returns 0 while scanning or in video mode.
  double get lockedFrequency => _lockedFrequency;

  /// Whether the audio decoder is in the scanning phase.
  bool get isCalibrating =>
      _mode == DecodingMode.audio &&
      _status == DecodingStatus.listening &&
      _audioDecoder?.isCalibrating == true;

  /// Minimum element duration in ms — shorter elements are
  /// likely noise/double-transitions at the camera frame rate.
  static const _minElementMs = 40;

  /// Current estimated WPM based on decoded elements.
  /// Uses the 25th-percentile on-element duration as the dit
  /// estimate (robust against spurious short noise elements).
  /// Returns 0 when no elements have been decoded yet.
  int get currentWpm {
    if (_elements.isEmpty) return 0;

    final onDurations = _elements
        .where((e) => e.isOn && e.durationMs >= _minElementMs)
        .map((e) => e.durationMs)
        .toList();
    if (onDurations.isEmpty) return 0;
    onDurations.sort();

    // Use 25th percentile instead of minimum for noise robustness
    final idx = (onDurations.length * 0.25).floor().clamp(
      0,
      onDurations.length - 1,
    );
    final ditMs = onDurations[idx].toDouble();
    if (ditMs <= 0) return 0;

    // PARIS = 50 dits per word, so WPM = 60000 / (ditMs * 50) = 1200 / ditMs
    return (1200 / ditMs).round();
  }

  bool get isIdle => _status == DecodingStatus.idle;
  bool get isListening => _status == DecodingStatus.listening;
  bool get isPaused => _status == DecodingStatus.paused;

  /// Whether the camera supports high-frame-rate.
  /// Returns `true` for audio mode (no camera needed).
  bool get isHighFrameRate => _mode == DecodingMode.video
      ? _cameraCapture?.isHighFrameRate ?? false
      : true;

  /// Returns a human-readable description of the camera capture
  /// mode: 'High speed', 'High resolution', or 'Error: <reason>'.
  String get cameraCaptureType {
    if (_mode != DecodingMode.video) return '';
    final cam = _cameraCapture;
    if (cam == null) return 'Error: no camera';
    if (!cam.isInitialized) return 'Error: not initialized';
    return cam.isHighFrameRate ? 'High speed' : 'High resolution';
  }

  /// Returns camera error reason if any.
  String? get cameraError {
    if (_mode != DecodingMode.video) return null;
    final cam = _cameraCapture;
    if (cam == null) return 'no camera available';
    if (!cam.isInitialized) return 'camera not initialized';
    return null;
  }

  /// Toggles audio debug logging on/off.
  void toggleDebugLogging() {
    final logger = _debugLogger;
    if (logger == null) return;
    logger.enabled = !logger.enabled;
    notifyListeners();
  }

  /// Toggles video debug logging on/off.
  void toggleVideoDebugLogging() {
    final logger = _videoDebugLogger;
    if (logger == null) return;
    logger.enabled = !logger.enabled;
    notifyListeners();
  }

  /// Initialises the controller for the given mode.
  void init(DecodingMode mode) {
    _mode = mode;
    _status = DecodingStatus.idle;
    _decodedText = '';
    _lockedFrequency = 0;
    _elements.clear();
    notifyListeners();
  }

  /// Checks whether the required permission is granted.
  Future<bool> checkPermission() async {
    if (_mode == DecodingMode.audio) {
      if (_audioCapture == null) return false;
      return _audioCapture.hasPermission();
    }
    if (_cameraCapture == null) return false;
    return _cameraCapture.hasPermission();
  }

  /// Begins listening / watching.
  void start() {
    if (_mode == DecodingMode.audio) {
      _startAudio();
    } else {
      _startVideo();
    }
    _status = DecodingStatus.listening;
    notifyListeners();
  }

  /// Pauses the current session. Decoded text is preserved.
  void pause() {
    _audioSub?.cancel();
    _audioSub = null;
    _audioCapture?.stop();
    _cameraCapture?.stop();
    // Decoders hold the last element back by one transition so a
    // glitch can be merged with its neighbours; release it, or the
    // final character of the transmission is lost.
    _audioDecoder?.flush();
    _videoDecoder?.flush();
    _status = DecodingStatus.paused;
    notifyListeners();
  }

  /// Resumes — restarts the pipeline from scanning but does
  /// not clear decoded text.
  void resume() {
    if (_mode == DecodingMode.audio) {
      _startAudio();
    } else {
      _startVideo();
    }
    _status = DecodingStatus.listening;
    notifyListeners();
  }

  /// Replaces the entire decoded text (user editing).
  void updateText(String text) {
    _decodedText = text;
    notifyListeners();
  }

  /// Processes raw on/off elements and appends the result.
  void processElements(List<DecodedElement> elements) {
    _elements.addAll(elements);
    _decodedText += _morseDecoder.decodeElements(elements);
    notifyListeners();
  }

  /// Clears the decoded text and resets to idle.
  void clear() {
    _decodedText = '';
    _lockedFrequency = 0;
    _elements.clear();
    _status = DecodingStatus.idle;
    _audioDecoder?.reset();
    _videoDecoder?.reset();
    notifyListeners();
  }

  void _startAudio() {
    if (_audioDecoder == null || _audioCapture == null) return;
    _audioDecoder.reset();

    // Wire debug logger if enabled
    final adl = _debugLogger;
    if (adl != null && adl.enabled) {
      adl.start();
      _audioDecoder.onDebugScanning =
          ({
            required totalSamples,
            required sampleRate,
            required dominantBin,
            required dominantPower,
            required avgOtherPower,
            required snr,
            required consecutiveFrames,
            required persistenceNeeded,
            required locked,
          }) {
            adl.logScanning(
              totalSamples: totalSamples,
              sampleRate: sampleRate,
              dominantBin: dominantBin,
              dominantPower: dominantPower,
              avgOtherPower: avgOtherPower,
              snr: snr,
              consecutiveFrames: consecutiveFrames,
              persistenceNeeded: persistenceNeeded,
            );
          };

      _audioDecoder.onDebugLock =
          ({
            required totalSamples,
            required sampleRate,
            required freq,
            required bestAvgPower,
            required noiseFloor,
            required onThresholdFactor,
          }) {
            adl.logLock(
              totalSamples: totalSamples,
              sampleRate: sampleRate,
              freq: freq,
              bestAvgPower: bestAvgPower,
              noiseFloor: noiseFloor,
              onThresholdFactor: onThresholdFactor,
            );
          };

      _audioDecoder.onDebugTracking =
          ({
            required totalSamples,
            required sampleRate,
            required freq,
            required power,
            required envelope,
            required noiseFloor,
            required onThreshold,
            required offThreshold,
            required isOn,
          }) {
            adl.logTracking(
              totalSamples: totalSamples,
              sampleRate: sampleRate,
              freq: freq,
              power: power,
              envelope: envelope,
              noiseFloor: noiseFloor,
              onThreshold: onThreshold,
              offThreshold: offThreshold,
              isOn: isOn,
            );
          };

      _audioDecoder.onDebugTransition =
          ({
            required totalSamples,
            required sampleRate,
            required isOn,
            required durationMs,
          }) {
            adl.logTransition(
              totalSamples: totalSamples,
              sampleRate: sampleRate,
              isOn: isOn,
              durationMs: durationMs,
            );
          };
    }

    _audioDecoder.onElement = _onElement;
    _audioDecoder.onLock = _onLock;
    _audioDecoder.onUnlock = () {
      adl?.logUnlock(
        totalSamples: 0,
        sampleRate: 8000,
      );
      _lockedFrequency = 0;
      notifyListeners();
    };
    _lockedFrequency = 0;
    final stream = _audioCapture.start();
    _audioSub = stream.listen((samples) {
      _audioDecoder.processSamples(samples);
    });
  }

  void _startVideo() {
    if (_videoDecoder == null || _cameraCapture == null) return;
    _videoDecoder.reset();

    // Wire video debug logger if enabled
    final vdl = _videoDebugLogger;
    if (vdl != null && vdl.enabled) {
      vdl.start();
      final vd = _videoDecoder;
      vd.onDebugScan =
          ({
            required timestampMs,
            required maxVariance,
            required meanVariance,
            required frameCount,
          }) {
            vdl.logScanning(
              timestampMs: timestampMs,
              maxVariance: maxVariance,
              meanVariance: meanVariance,
              frameCount: frameCount,
            );
          };
      vd.onDebugConfirm =
          ({
            required timestampMs,
            required variance,
            required confirmCount,
            required filterX,
            required filterY,
          }) {
            vdl.logConfirming(
              timestampMs: timestampMs,
              variance: variance,
              confirmCount: confirmCount,
              filterX: filterX,
              filterY: filterY,
            );
          };
      vd.onDebugTrack =
          ({
            required timestampMs,
            required variance,
            required brightness,
            required minBrightness,
            required maxBrightness,
            required range,
            required onThreshold,
            required offThreshold,
            required isOn,
            required regionX,
            required regionY,
            required regionSize,
            required innovation,
          }) {
            vdl.logTracking(
              timestampMs: timestampMs,
              variance: variance,
              brightness: brightness,
              minBrightness: minBrightness,
              maxBrightness: maxBrightness,
              range: range,
              onThreshold: onThreshold,
              offThreshold: offThreshold,
              isOn: isOn,
              regionX: regionX,
              regionY: regionY,
              regionSize: regionSize,
              innovation: innovation,
            );
          };
      vd.onDebugTransition =
          ({
            required timestampMs,
            required isOn,
            required durationMs,
          }) {
            vdl.logTransition(
              timestampMs: timestampMs,
              isOn: isOn,
              durationMs: durationMs,
            );
          };
      vd.onDebugSignalLost =
          ({
            required timestampMs,
            required lostFrameCount,
          }) {
            vdl.logSignalLost(
              timestampMs: timestampMs,
              lostFrameCount: lostFrameCount,
            );
          };
      vd.onDebugStateChange =
          ({
            required timestampMs,
            required newState,
            detail,
          }) {
            vdl.logStateChange(
              timestampMs: timestampMs,
              newState: newState,
              detail: detail,
            );
          };
    }

    _videoDecoder.onElement = _onElement;
    _cameraCapture.startImageStream((frame) {
      _videoDecoder.processFrame(frame);
    });
  }

  void _onElement(DecodedElement element) {
    _elements.add(element);
    _decodedText = _morseDecoder.decodeElements(_elements);
    notifyListeners();
  }

  void _onLock(double freq) {
    _lockedFrequency = freq;
    notifyListeners();
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    _audioCapture?.stop();
    _cameraCapture?.stop();
    _debugLogger?.stop();
    _videoDebugLogger?.stop();
    _status = DecodingStatus.idle;
    super.dispose();
  }
}
