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
  bool _repeatLoop = AppConstants.defaultRepeatLoop;
  double _repeatDelaySec = AppConstants.defaultRepeatDelaySec;
  LightMethod _lightMethod = LightMethod.flashLed;
  String _text = '';
  List<String> _history = [];
  TransmissionState _transmission = const TransmissionState();
  bool _initialized = false;
  bool _isRepeatCancelled = false;

  /// Notifier for the initial-delay countdown.
  /// Non-null while the countdown is active (value = seconds remaining).
  /// Null when no countdown is running.
  final ValueNotifier<int?> countdownRemaining = ValueNotifier<int?>(null);

  /// Notifier for the repeat-delay countdown.
  /// Non-null while waiting between repeats (value = seconds remaining).
  /// Null when no repeat delay is running.
  final ValueNotifier<int?> repeatCountdown = ValueNotifier<int?>(null);

  EncodingMode get mode => _mode;
  double get speedWpm => _speedWpm;
  double get toneHz => _toneHz;
  double get initialDelaySec => _initialDelaySec;
  bool get repeatLoop => _repeatLoop;
  double get repeatDelaySec => _repeatDelaySec;
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
    _repeatLoop = await _settingsRepo.getRepeatLoop();
    _repeatDelaySec = await _settingsRepo.getRepeatDelay();
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

  Future<void> updateRepeatLoop(bool value) async {
    _repeatLoop = value;
    await _settingsRepo.saveRepeatLoop(value);
    notifyListeners();
  }

  Future<void> updateRepeatDelay(double value) async {
    _repeatDelaySec = value;
    await _settingsRepo.saveRepeatDelay(value);
    notifyListeners();
  }

  void updateLightMethod(LightMethod value) {
    _lightMethod = value;
    notifyListeners();
  }

  Future<void> send() async {
    if (_text.isEmpty || isTransmitting) return;
    _isRepeatCancelled = false;
    await _sendOnce();
    while (_repeatLoop && !_isRepeatCancelled) {
      // Wait between repeats
      if (_isRepeatCancelled) break;

      final seconds = _repeatDelaySec.round();
      for (var i = seconds; i >= 1; i--) {
        if (_isRepeatCancelled) {
          repeatCountdown.value = null;
          return;
        }
        repeatCountdown.value = i;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      repeatCountdown.value = null;

      if (_isRepeatCancelled) break;
      await _sendOnce();
    }
  }

  Future<void> _sendOnce() async {
    _transmission = _transmission.copyWith(
      status: TransmissionStatus.transmitting,
      currentCharIndex: -1,
    );
    notifyListeners();

    await _historyRepo.save(_text);
    _history = await _historyRepo.getAll();

    // Run initial-delay countdown in the controller so the UI
    // can show a countdown overlay. The transmitter receives
    // settings with initialDelaySec = 0 (delay already consumed).
    if (_initialDelaySec > 0) {
      final seconds = _initialDelaySec.round();
      for (var i = seconds; i >= 1; i--) {
        if (!_transmission.isTransmitting) {
          countdownRemaining.value = null;
          return;
        }
        countdownRemaining.value = i;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      countdownRemaining.value = null;
      if (!_transmission.isTransmitting) return;
    }

    final settings = EncodingSettings(
      mode: _mode,
      speedWpm: _speedWpm,
      toneHz: _toneHz,
      lightMethod: _lightMethod,
      initialDelaySec: 0,
    );

    final symbols = _encoder.encode(_text, settings);
    final events = _encoder.buildTimeline(symbols, settings);

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
    _isRepeatCancelled = true;
    await _transmitter.stop();
    _transmission = _transmission.copyWith(
      status: TransmissionStatus.idle,
    );
    countdownRemaining.value = null;
    repeatCountdown.value = null;
    notifyListeners();
  }

  Future<void> clear() async {
    _isRepeatCancelled = true;
    await _transmitter.stop();
    _text = '';
    _transmission = const TransmissionState();
    countdownRemaining.value = null;
    repeatCountdown.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    countdownRemaining.dispose();
    repeatCountdown.dispose();
    _transmitter.dispose();
    super.dispose();
  }
}
