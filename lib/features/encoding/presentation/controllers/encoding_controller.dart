import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';
import 'package:simply_morse/features/encoding/domain/models/transmission_state.dart';
import 'package:simply_morse/features/encoding/domain/repositories/settings_repository.dart';
import 'package:simply_morse/features/encoding/domain/repositories/text_history_repository.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_transmitter.dart';

/// Manages the encoding feature's state as a [ChangeNotifier].
class EncodingController extends ChangeNotifier {
  EncodingController({
    required SettingsRepository settingsRepository,
    required TextHistoryRepository textHistoryRepository,
    required MorseEncoder morseEncoder,
    required MorseTransmitter morseTransmitter,
  }) : _settingsRepo = settingsRepository,
       _historyRepo = textHistoryRepository,
       _encoder = morseEncoder,
       _transmitter = morseTransmitter;

  final SettingsRepository _settingsRepo;
  final TextHistoryRepository _historyRepo;
  final MorseEncoder _encoder;
  final MorseTransmitter _transmitter;

  EncodingMode _mode = EncodingMode.sound;
  double _speedWpm = AppConstants.defaultSpeedWpm;
  double _toneHz = AppConstants.defaultToneHz;
  double _initialDelaySec = AppConstants.defaultInitialDelaySec;
  LightMethod _lightMethod = LightMethod.flashLed;
  String _text = '';
  List<String> _history = [];
  TransmissionState _transmission = const TransmissionState();
  bool _initialized = false;

  EncodingMode get mode => _mode;
  double get speedWpm => _speedWpm;
  double get toneHz => _toneHz;
  double get initialDelaySec => _initialDelaySec;
  LightMethod get lightMethod => _lightMethod;
  String get text => _text;
  List<String> get history => _history;
  TransmissionState get transmission => _transmission;
  bool get isTransmitting => _transmission.isTransmitting;

  /// The display blink notifier from the transmitter.
  /// The UI watches this to blink the screen/panel in sync
  /// with the Morse signal.
  ValueNotifier<bool> get displayBlink => _transmitter.displayBlink;

  /// Initializes the controller with the given [mode] and loads
  /// persisted settings and history.
  Future<void> init(EncodingMode mode) async {
    if (_initialized) return;
    _mode = mode;
    _speedWpm = await _settingsRepo.getSpeed();
    _toneHz = await _settingsRepo.getTone();
    _initialDelaySec = await _settingsRepo.getInitialDelay();
    _history = await _historyRepo.getAll();
    _initialized = true;
    notifyListeners();
  }

  void updateText(String value) {
    _text = value;
    notifyListeners();
  }

  void selectFromHistory(String value) {
    _text = value;
    notifyListeners();
  }

  Future<void> updateSpeed(double value) async {
    _speedWpm = value;
    await _settingsRepo.saveSpeed(value);
    notifyListeners();
  }

  Future<void> updateTone(double value) async {
    _toneHz = value;
    await _settingsRepo.saveTone(value);
    notifyListeners();
  }

  Future<void> updateInitialDelay(double value) async {
    _initialDelaySec = value;
    await _settingsRepo.saveInitialDelay(value);
    notifyListeners();
  }

  void updateLightMethod(LightMethod value) {
    _lightMethod = value;
    notifyListeners();
  }

  Future<void> send() async {
    if (_text.isEmpty || isTransmitting) return;

    final settings = EncodingSettings(
      mode: _mode,
      speedWpm: _speedWpm,
      toneHz: _toneHz,
      lightMethod: _lightMethod,
      initialDelaySec: _initialDelaySec,
    );

    final symbols = _encoder.encode(_text, settings);
    final events = _encoder.buildTimeline(symbols, settings);

    _transmission = _transmission.copyWith(
      status: TransmissionStatus.transmitting,
      currentCharIndex: -1,
    );
    notifyListeners();

    await _historyRepo.save(_text);
    _history = await _historyRepo.getAll();

    await _transmitter.transmit(
      events: events,
      settings: settings,
      onProgress: (charIndex) {
        _transmission = _transmission.copyWith(
          currentCharIndex: charIndex,
        );
        notifyListeners();
      },
      onComplete: () {
        _transmission = _transmission.copyWith(
          status: TransmissionStatus.completed,
          currentCharIndex: -1,
        );
        notifyListeners();
      },
    );
  }

  Future<void> pause() async {
    await _transmitter.stop();
    _transmission = _transmission.copyWith(
      status: TransmissionStatus.idle,
    );
    notifyListeners();
  }

  Future<void> clear() async {
    await _transmitter.stop();
    _text = '';
    _transmission = const TransmissionState();
    notifyListeners();
  }

  @override
  void dispose() {
    _transmitter.dispose();
    super.dispose();
  }
}
