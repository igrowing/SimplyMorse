import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';

/// State management for a decoding session.
///
/// Manages the UI state (idle / listening / paused) and holds
/// the decoded text. When in audio mode, wires the
/// [AudioCapture] → [AudioDecoder] → [MorseDecoder] pipeline.
class DecodingController extends ChangeNotifier {
  DecodingController({
    required MorseDecoder morseDecoder,
    AudioDecoder? audioDecoder,
    AudioCapture? audioCapture,
  }) : _morseDecoder = morseDecoder,
       _audioDecoder = audioDecoder,
       _audioCapture = audioCapture;

  final MorseDecoder _morseDecoder;
  final AudioDecoder? _audioDecoder;
  final AudioCapture? _audioCapture;

  StreamSubscription<List<double>>? _audioSub;
  final List<DecodedElement> _elements = [];

  DecodingMode _mode = DecodingMode.audio;
  DecodingStatus _status = DecodingStatus.idle;
  String _decodedText = '';

  DecodingMode get mode => _mode;
  DecodingStatus get status => _status;
  String get decodedText => _decodedText;

  bool get isIdle => _status == DecodingStatus.idle;
  bool get isListening => _status == DecodingStatus.listening;
  bool get isPaused => _status == DecodingStatus.paused;

  /// Initialises the controller for the given mode. Called
  /// from the screen's [initState].
  void init(DecodingMode mode) {
    _mode = mode;
    _status = DecodingStatus.idle;
    _decodedText = '';
    _elements.clear();
    notifyListeners();
  }

  /// Checks whether the microphone permission is granted.
  /// Returns `true` if audio mode is not active (no check
  /// needed) or if permission is granted.
  Future<bool> checkPermission() async {
    if (_mode != DecodingMode.audio) return true;
    if (_audioCapture == null) return false;
    return _audioCapture!.hasPermission();
  }

  /// Begins listening / watching.
  void start() {
    if (_mode == DecodingMode.audio) {
      _startAudio();
    }
    _status = DecodingStatus.listening;
    notifyListeners();
  }

  /// Pauses the current session. Decoded text is preserved.
  void pause() {
    _audioSub?.cancel();
    _audioSub = null;
    _audioCapture?.stop();
    _status = DecodingStatus.paused;
    notifyListeners();
  }

  /// Resumes from a paused state — restarts the pipeline from
  /// scanning but does not clear decoded text.
  void resume() {
    _startAudio();
    _status = DecodingStatus.listening;
    notifyListeners();
  }

  /// Appends a decoded character to the text.
  void appendChar(String char) {
    _decodedText += char;
    notifyListeners();
  }

  /// Replaces the entire decoded text (used by the editable
  /// text field when the user corrects mistakes).
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
    notifyListeners();
  }

  void _startAudio() {
    if (_audioDecoder == null || _audioCapture == null) return;

    _audioDecoder!.reset();
    _audioDecoder!.onElement = _onElement;

    final stream = _audioCapture!.start();
    _audioSub = stream.listen((samples) {
      _audioDecoder!.processSamples(samples);
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
    _status = DecodingStatus.idle;
    super.dispose();
  }
}
