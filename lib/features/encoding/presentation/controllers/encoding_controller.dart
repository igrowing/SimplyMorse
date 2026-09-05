import 'package:flutter/foundation.dart';

import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';
import 'package:simply_morse/features/encoding/domain/models/output_method.dart';
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

  /// Currently selected output methods (multi-select).
  /// Maps internally to [EncodingMode] + [LightMethod] for
  /// backward compatibility with the domain layer.
  Set<OutputMethod> _outputs = const {OutputMethod.sound};

  double _speedWpm = AppConstants.defaultSpeedWpm;
  double _toneHz = AppConstants.defaultToneHz;
  double _initialDelaySec = AppConstants.defaultInitialDelaySec;
  bool _repeatLoop = AppConstants.defaultRepeatLoop;
  double _repeatDelaySec = AppConstants.defaultRepeatDelaySec;
  String _text = '';
  List<String> _history = [];
  TransmissionState _transmission = const TransmissionState();
  bool _initialized = false;
  bool _isRepeatCancelled = false;

  /// Countdown through the initial delay (seconds remaining,
  /// null when idle). Owned by the transmitter, which applies
  /// the delay on the single code path shared by audio, torch,
  /// and display — the UI overlay observes this.
  ValueListenable<int?> get countdownRemaining =>
      _transmitter.countdownRemaining;

  /// Notifier for the repeat-delay countdown.
  /// Non-null while waiting between repeats (value = seconds remaining).
  /// Null when no repeat delay is running.
  final ValueNotifier<int?> repeatCountdown = ValueNotifier<int?>(null);

  /// The selected output methods.
  Set<OutputMethod> get outputs => _outputs;

  /// Whether sound output is active.
  bool get hasSound => _outputs.contains(OutputMethod.sound);

  /// Whether LED/torch output is active.
  bool get hasLed => _outputs.contains(OutputMethod.led);

  /// Whether display blink output is active.
  bool get hasDisplay => _outputs.contains(OutputMethod.display);

  /// Whether any visual (non-audio) output is active.
  bool get hasLight => hasLed || hasDisplay;

  // ── Backward-compatible domain accessors ──────────────────
  /// Derived [EncodingMode] from the current output selection.
  EncodingMode get mode => hasSound
      ? (hasLight ? EncodingMode.both : EncodingMode.sound)
      : EncodingMode.flash;

  /// Derived [LightMethod] from the current output selection.
  LightMethod get lightMethod => hasLed && hasDisplay
      ? LightMethod.both
      : (hasLed ? LightMethod.flashLed : LightMethod.display);

  double get speedWpm => _speedWpm;
  double get toneHz => _toneHz;
  double get initialDelaySec => _initialDelaySec;
  bool get repeatLoop => _repeatLoop;
  double get repeatDelaySec => _repeatDelaySec;
  String get text => _text;
  List<String> get history => _history;
  TransmissionState get transmission => _transmission;
  bool get isTransmitting => _transmission.isTransmitting;

  /// The display blink notifier from the transmitter.
  /// The UI watches this to blink the screen/panel in sync
  /// with the Morse signal.
  ValueNotifier<bool> get displayBlink => _transmitter.displayBlink;

  /// Initializes the controller and loads persisted settings
  /// and history.
  Future<void> init() async {
    if (_initialized) return;
    _speedWpm = await _settingsRepo.getSpeed();
    _toneHz = await _settingsRepo.getTone();
    _initialDelaySec = await _settingsRepo.getInitialDelay();
    _repeatLoop = await _settingsRepo.getRepeatLoop();
    _repeatDelaySec = await _settingsRepo.getRepeatDelay();
    _history = await _historyRepo.getAll();
    _initialized = true;
    notifyListeners();
  }

  /// Updates the selected output methods.
  /// Ensures at least one method remains selected.
  void updateOutputs(Set<OutputMethod> value) {
    if (value.isEmpty) return; // prevent empty selection
    _outputs = value;
    notifyListeners();
  }

  /// Toggles a single output method on/off.
  /// Ensures at least one method remains selected.
  void toggleOutput(OutputMethod method) {
    final next = Set<OutputMethod>.from(_outputs);
    if (next.contains(method)) {
      if (next.length == 1) return; // prevent empty selection
      next.remove(method);
    } else {
      next.add(method);
    }
    _outputs = next;
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

  Future<void> updateRepeatLoop({required bool value}) async {
    _repeatLoop = value;
    await _settingsRepo.saveRepeatLoop(enabled: value);
    notifyListeners();
  }

  Future<void> updateRepeatDelay(double value) async {
    _repeatDelaySec = value;
    await _settingsRepo.saveRepeatDelay(value);
    notifyListeners();
  }

  /// Backward-compatible method — maps [LightMethod] back to
  /// output methods.
  void updateLightMethod(LightMethod value) {
    final next = Set<OutputMethod>.from(_outputs)
      ..remove(OutputMethod.led)
      ..remove(OutputMethod.display)
      ..addAll([
        if (value == LightMethod.flashLed || value == LightMethod.both)
          OutputMethod.led,
        if (value == LightMethod.display || value == LightMethod.both)
          OutputMethod.display,
      ]);
    if (next.isNotEmpty) _outputs = next;
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

    // The initial delay runs inside the transmitter (which also
    // drives the countdown notifier), so every output method —
    // sound included — starts only after it elapses.
    // Read fresh so a Farnsworth toggle made while the
    // controller is alive takes effect on the next send.
    final farnsworthEnabled = await _settingsRepo.getFarnsworthEnabled();

    final settings = EncodingSettings(
      mode: mode,
      speedWpm: _speedWpm,
      toneHz: _toneHz,
      lightMethod: lightMethod,
      initialDelaySec: _initialDelaySec,
      farnsworthEnabled: farnsworthEnabled,
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
    repeatCountdown.value = null;
    notifyListeners();
  }

  Future<void> clear() async {
    _isRepeatCancelled = true;
    await _transmitter.stop();
    _text = '';
    _transmission = const TransmissionState();
    repeatCountdown.value = null;
    notifyListeners();
  }

  @override
  void dispose() {
    repeatCountdown.dispose();
    _transmitter.dispose();
    super.dispose();
  }
}
