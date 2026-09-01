import 'package:simply_morse/core/services/torch_service.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/repositories/settings_repository.dart';
import 'package:simply_morse/features/encoding/domain/repositories/text_history_repository.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_transmitter.dart';

/// Fake torch service that records all enable/disable calls.
class FakeTorchService implements TorchService {
  final List<bool> _calls = [];

  List<bool> get calls => List.unmodifiable(_calls);

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<void> enable() async {
    _calls.add(true);
  }

  @override
  Future<void> disable() async {
    _calls.add(false);
  }

  void reset() => _calls.clear();
}

/// Fake settings repository with in-memory storage.
class FakeSettingsRepository implements SettingsRepository {
  double speed = 7.0;
  double tone = 700.0;
  double initialDelay = 1.0;
  bool repeatLoop = false;
  double repeatDelay = 2.0;
  bool farnsworthEnabled = false;
  String displayTimeout = 'system';
  int saveSpeedCount = 0;
  int saveToneCount = 0;
  int saveInitialDelayCount = 0;
  int saveRepeatLoopCount = 0;
  int saveRepeatDelayCount = 0;
  int saveFarnsworthCount = 0;
  int saveDisplayTimeoutCount = 0;

  @override
  Future<double> getSpeed() async => speed;

  @override
  Future<void> saveSpeed(double wpm) async {
    speed = wpm;
    saveSpeedCount++;
  }

  @override
  Future<double> getTone() async => tone;

  @override
  Future<void> saveTone(double hz) async {
    tone = hz;
    saveToneCount++;
  }

  @override
  Future<double> getInitialDelay() async => initialDelay;

  @override
  Future<void> saveInitialDelay(double seconds) async {
    initialDelay = seconds;
    saveInitialDelayCount++;
  }

  @override
  Future<bool> getRepeatLoop() async => repeatLoop;

  @override
  Future<void> saveRepeatLoop(bool enabled) async {
    repeatLoop = enabled;
    saveRepeatLoopCount++;
  }

  @override
  Future<double> getRepeatDelay() async => repeatDelay;

  @override
  Future<void> saveRepeatDelay(double seconds) async {
    repeatDelay = seconds;
    saveRepeatDelayCount++;
  }

  @override
  Future<bool> getFarnsworthEnabled() async => farnsworthEnabled;

  @override
  Future<void> saveFarnsworthEnabled(bool enabled) async {
    farnsworthEnabled = enabled;
    saveFarnsworthCount++;
  }

  @override
  Future<String> getDisplayTimeout() async => displayTimeout;

  @override
  Future<void> saveDisplayTimeout(String mode) async {
    displayTimeout = mode;
    saveDisplayTimeoutCount++;
  }
}

/// Fake text history repository with in-memory storage.
class FakeTextHistoryRepository implements TextHistoryRepository {
  final List<String> _entries = [];
  int saveCount = 0;

  @override
  Future<List<String>> getAll() async => List.unmodifiable(_entries);

  @override
  Future<void> save(String text) async {
    _entries.remove(text);
    _entries.insert(0, text);
    saveCount++;
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }

  void seed(List<String> entries) {
    _entries
      ..clear()
      ..addAll(entries);
  }
}

/// A fake transmitter that records calls without using
/// platform services.
///
/// Extends [MorseTransmitter] so it can be used wherever the
/// real type is expected, but overrides all platform-
/// dependent methods.
class FakeMorseTransmitter extends MorseTransmitter {
  FakeMorseTransmitter() : super(torchService: FakeTorchService());

  int transmitCount = 0;
  List<ToneEvent>? lastEvents;
  EncodingSettings? lastSettings;
  ProgressCallback? lastProgressCallback;
  CompleteCallback? lastCompleteCallback;
  int stopCount = 0;
  int disposeCount = 0;

  /// When true (default), [transmit] calls [onComplete] immediately.
  /// Set to false to keep the transmission in the "transmitting" state.
  bool autoComplete = true;

  @override
  Future<void> transmit({
    required List<ToneEvent> events,
    required EncodingSettings settings,
    required ProgressCallback onProgress,
    required CompleteCallback onComplete,
  }) async {
    transmitCount++;
    lastEvents = events;
    lastSettings = settings;
    lastProgressCallback = onProgress;
    lastCompleteCallback = onComplete;
    if (autoComplete) {
      onComplete();
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  void dispose() {
    disposeCount++;
  }
}
