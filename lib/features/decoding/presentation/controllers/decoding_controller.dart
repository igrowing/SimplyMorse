import 'package:flutter/foundation.dart';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';

/// State management for a decoding session.
///
/// In Phase 2 this manages the UI state (idle / listening /
/// paused) and holds the decoded text. The actual audio/video
/// pipeline is wired in a later phase — for now [start] just
/// flips the status.
class DecodingController extends ChangeNotifier {
  DecodingController({required MorseDecoder morseDecoder})
    : _morseDecoder = morseDecoder;

  final MorseDecoder _morseDecoder;

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
    notifyListeners();
  }

  /// Begins listening / watching.
  void start() {
    _status = DecodingStatus.listening;
    notifyListeners();
  }

  /// Pauses the current session. Decoded text is preserved.
  void pause() {
    _status = DecodingStatus.paused;
    notifyListeners();
  }

  /// Resumes from a paused state.
  void resume() {
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
  ///
  /// In a later phase the audio/video pipeline will call this
  /// with detected elements. For now it is available for
  /// testing and manual use.
  void processElements(List<DecodedElement> elements) {
    final decoded = _morseDecoder.decodeElements(elements);
    _decodedText += decoded;
    notifyListeners();
  }

  /// Clears the decoded text and resets to idle.
  void clear() {
    _decodedText = '';
    _status = DecodingStatus.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _status = DecodingStatus.idle;
    super.dispose();
  }
}
