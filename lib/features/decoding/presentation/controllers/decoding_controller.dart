import 'dart:async';

import 'package:flutter/foundation.dart';

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
  }) : _morseDecoder = morseDecoder,
       _audioDecoder = audioDecoder,
       _audioCapture = audioCapture,
       _videoDecoder = videoDecoder,
       _cameraCapture = cameraCapture;

  final MorseDecoder _morseDecoder;
  final AudioDecoder? _audioDecoder;
  final AudioCapture? _audioCapture;
  final VideoDecoder? _videoDecoder;
  final CameraCapture? _cameraCapture;

  StreamSubscription<List<double>>? _audioSub;
  final List<DecodedElement> _elements = [];

  DecodingMode _mode = DecodingMode.audio;
  DecodingStatus _status = DecodingStatus.idle;
  String _decodedText = '';

  DecodingMode get mode => _mode;
  DecodingStatus get status => _status;
  String get decodedText => _decodedText;

  /// Current estimated WPM based on decoded elements.
  /// Returns 0 when no elements have been decoded yet.
  int get currentWpm {
    if (_elements.isEmpty) return 0;

    // Estimate dit from shortest on-element
    final onDurations = _elements
        .where((e) => e.isOn && e.durationMs > 0)
        .map((e) => e.durationMs)
        .toList();
    if (onDurations.isEmpty) return 0;
    onDurations.sort();
    final ditMs = onDurations.first.toDouble();
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

  /// Initialises the controller for the given mode.
  void init(DecodingMode mode) {
    _mode = mode;
    _status = DecodingStatus.idle;
    _decodedText = '';
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
    _elements.clear();
    _status = DecodingStatus.idle;
    _audioDecoder?.reset();
    _videoDecoder?.reset();
    notifyListeners();
  }

  void _startAudio() {
    if (_audioDecoder == null || _audioCapture == null) return;
    _audioDecoder.reset();
    _audioDecoder.onElement = _onElement;
    final stream = _audioCapture.start();
    _audioSub = stream.listen((samples) {
      _audioDecoder.processSamples(samples);
    });
  }

  void _startVideo() {
    if (_videoDecoder == null || _cameraCapture == null) return;
    _videoDecoder.reset();
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

  @override
  void dispose() {
    _audioSub?.cancel();
    _audioCapture?.stop();
    _cameraCapture?.stop();
    _status = DecodingStatus.idle;
    super.dispose();
  }
}
