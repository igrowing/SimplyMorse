import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:simply_morse/features/decoding/data/audio_debug_logger.dart';
import 'package:simply_morse/features/decoding/data/video_debug_logger.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
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
    required this._morseDecoder,
    this._audioDecoder,
    this._audioCapture,
    this._videoDecoder,
    this._cameraCapture,
    this._debugLogger,
    this._videoDebugLogger,
  });

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

  /// Live video tracking telemetry for the See-screen debug
  /// overlay: non-`null` only while the decoder is locked on a
  /// blinking source. Exposed as a [ValueNotifier] so the
  /// overlay repaints per frame (30-120 Hz) without rebuilding
  /// the rest of the screen on every telemetry update.
  final ValueNotifier<TrackOverlayInfo?> trackOverlay =
      ValueNotifier<TrackOverlayInfo?>(null);

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

  /// Highest sending speed this capture frame rate can decode
  /// reliably, in WPM. Returns 0 for a non-positive [fps].
  ///
  /// The dit is the shortest Morse element; once it spans too few
  /// captured frames the dah and character-gap duration clusters
  /// overlap and no classifier can pull them apart. Measured across
  /// the reference recordings, decoding stays clean at ~4 frames per
  /// dit (8 WPM at 30 fps) and collapses below ~2.5 (16-20 WPM at
  /// 30 fps). This reports the speed at which a dit spans
  /// [_framesPerDitFloor] frames:
  ///
  ///     WPM = 1200 / ditMs,   ditMs = framesPerDit * 1000 / fps
  ///  => maxWpm = 1.2 * fps / framesPerDit
  ///
  /// Informational only. A faster transmission still decodes, just
  /// with more errors; the app never rejects one, and the operator
  /// cannot judge the sender's speed by eye.
  static int maxDecodableWpm(int fps) {
    if (fps <= 0) return 0;
    return (1.2 * fps / _framesPerDitFloor).floor();
  }

  /// Frames per dit below which the video decoder's duration
  /// clusters stop separating — see [maxDecodableWpm].
  static const double _framesPerDitFloor = 4;

  bool get isIdle => _status == DecodingStatus.idle;
  bool get isListening => _status == DecodingStatus.listening;
  bool get isPaused => _status == DecodingStatus.paused;

  /// Whether the camera supports high-frame-rate.
  /// Returns `true` for audio mode (no camera needed).
  bool get isHighFrameRate =>
      !(_mode == DecodingMode.video) ||
      (_cameraCapture?.isHighFrameRate ?? false);

  /// Measured capture rate of the live camera stream, in FPS.
  ///
  /// This is the rate the device actually delivers (the requested
  /// rate may be silently downgraded), measured over roughly the
  /// last second of frames. Returns 0 when not streaming.
  int get captureFps {
    if (_mode != DecodingMode.video) return 0;
    return _cameraCapture?.measuredFps.round() ?? 0;
  }

  /// Returns a human-readable description of the camera capture
  /// mode: 'High speed', 'High resolution', or 'Error: `<reason>`'.
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
    trackOverlay.value = null;
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
    unawaited(_audioSub?.cancel());
    _audioSub = null;
    unawaited(_audioCapture?.stop());
    unawaited(_cameraCapture?.stop());
    // Decoders hold the last element back by one transition so a
    // glitch can be merged with its neighbours; release it, or the
    // final character of the transmission is lost.
    _audioDecoder?.flush();
    _videoDecoder?.flush();
    trackOverlay.value = null;
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
    trackOverlay.value = null;
    _audioDecoder?.reset();
    _videoDecoder?.reset();
    notifyListeners();
  }

  void _startAudio() {
    if (_audioDecoder == null || _audioCapture == null) return;
    _audioDecoder.reset();

    // Wire debug logger if enabled. The debug callbacks mirror
    // the logger's method signatures one-to-one, so they can be
    // assigned as direct tear-offs.
    final adl = _debugLogger;
    if (adl != null && adl.enabled) {
      unawaited(adl.start());
      _audioDecoder
        ..onDebugScanning = adl.logScanning
        ..onDebugDetection = adl.logDetection
        ..onDebugLock = adl.logLock
        ..onDebugReplay = adl.logReplay
        ..onDebugTracking = adl.logTracking
        ..onDebugTransition = adl.logTransition
        ..onDebugGlitchMerge = adl.logGlitchMerge
        ..onDebugRetuneCheck = adl.logRetuneCheck
        ..onDebugToneQuality = adl.logToneQuality
        ..onDebugToneGate = adl.logToneGate
        ..onDebugGateReplay = adl.logGateReplay
        ..onDebugUnlock = adl.logUnlock;
    }

    _audioDecoder
      ..onElement = _onElement
      ..onLock = _onLock
      // The unlock debug row is emitted by the decoder itself
      // (onDebugUnlock) with the real content-time timestamp and
      // reason; this handler is UI state only.
      ..onUnlock = () {
        _lockedFrequency = 0;
        notifyListeners();
      };
    _lockedFrequency = 0;
    final stream = _audioCapture.start();
    _audioSub = stream.listen(_audioDecoder.processSamples);
  }

  void _startVideo() {
    if (_videoDecoder == null || _cameraCapture == null) return;
    _videoDecoder.reset();

    // Wire video debug logger if enabled
    final vdl = _videoDebugLogger;
    if (vdl != null && vdl.enabled) {
      unawaited(vdl.start());
      final vd = _videoDecoder;
      // cascade_invocations: receiver used in conditional block, can't cascade.
      // ignore: cascade_invocations
      vd
        ..onDebugScan = vdl.logScanning
        ..onDebugConfirm = vdl.logConfirming
        ..onDebugTrack = vdl.logTracking
        ..onDebugTransition = vdl.logTransition
        ..onDebugSignalLost = vdl.logSignalLost
        ..onDebugStateChange = vdl.logStateChange;
    }

    _videoDecoder
      ..onElement = _onElement
      ..onTrackOverlay = (info) {
        trackOverlay.value = info;
      };
    _cameraCapture.startImageStream(_videoDecoder.processFrame);
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
    unawaited(_audioSub?.cancel());
    unawaited(_audioCapture?.stop());
    unawaited(_cameraCapture?.stop());
    unawaited(_debugLogger?.stop());
    unawaited(_videoDebugLogger?.stop());
    _status = DecodingStatus.idle;
    trackOverlay.dispose();
    super.dispose();
  }
}
