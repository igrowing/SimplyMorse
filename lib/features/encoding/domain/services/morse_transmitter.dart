import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:simply_morse/core/services/torch_service.dart';
import 'package:simply_morse/core/utils/wav_generator.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';

/// Callback for transmission progress updates.
typedef ProgressCallback = void Function(int charIndex);

/// Callback for transmission completion.
typedef CompleteCallback = void Function();

/// Handles audio, flash, and combined Morse transmission.
///
/// Exposes [displayBlink] as a [ValueNotifier<bool>] so the UI
/// can blink the screen in sync with the Morse signal when the
/// selected [LightMethod] includes display output.
class MorseTransmitter {
  MorseTransmitter({required TorchService torchService})
    : _torchService = torchService;

  final TorchService _torchService;

  /// Lazily created audio player — only instantiated when
  /// audio transmission is actually needed. This avoids
  /// requiring platform audio services in flash-only mode
  /// or in tests.
  AudioPlayer? _player;
  AudioPlayer get _audioPlayer => _player ??= AudioPlayer();

  /// Whether the audio player has been created.
  /// Used in tests to verify lazy initialization.
  bool get hasAudioPlayer => _player != null;

  /// Notifier that flips true/false in sync with the Morse
  /// signal when the display blink method is active.
  /// The UI watches this to blink the screen/panel.
  final ValueNotifier<bool> displayBlink = ValueNotifier<bool>(false);

  Timer? _progressTimer;
  bool _isRunning = false;

  /// Transmits the given [events] using the specified [settings].
  Future<void> transmit({
    required List<ToneEvent> events,
    required EncodingSettings settings,
    required ProgressCallback onProgress,
    required CompleteCallback onComplete,
  }) async {
    if (_isRunning) await stop();

    _isRunning = true;

    // Apply initial delay before starting anything.
    if (settings.initialDelaySec > 0) {
      await Future<void>.delayed(
        Duration(
          milliseconds: (settings.initialDelaySec * 1000).round(),
        ),
      );
      if (!_isRunning) return;
    }

    // Calculate cumulative time for progress tracking
    var elapsed = 0;
    final charStartTimes = <int, int>{};
    for (final event in events) {
      if (!charStartTimes.containsKey(event.charIndex)) {
        charStartTimes[event.charIndex] = elapsed;
      }
      elapsed += event.durationMs;
    }
    final totalDuration = elapsed;

    // Start progress timer
    final startTime = DateTime.now();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (timer) {
        final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
        if (elapsedMs >= totalDuration) {
          timer.cancel();
          onComplete();
          return;
        }
        var currentChar = -1;
        for (final entry in charStartTimes.entries) {
          if (entry.value <= elapsedMs) {
            currentChar = entry.key;
          }
        }
        onProgress(currentChar);
      },
    );

    // Audio transmission
    if (settings.needsAudio) {
      final wav = _generateWav(events, settings.toneHz);
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(BytesSource(wav));
    }

    // Visual transmission (torch and/or display)
    if (settings.needsTorch || settings.needsDisplay) {
      await _runVisualSequence(events, settings);
    }

    _isRunning = false;
  }

  /// Stops any ongoing transmission.
  Future<void> stop() async {
    _isRunning = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    await _player?.stop();
    await _torchService.disable();
    displayBlink.value = false;
  }

  /// Disposes all resources.
  void dispose() {
    _progressTimer?.cancel();
    _player?.dispose();
    displayBlink.dispose();
  }

  Uint8List _generateWav(
    List<ToneEvent> events,
    double toneHz,
  ) {
    final generator = WavGenerator();
    final segments = events
        .map(
          (e) => ToneSegment(
            isOn: e.isOn,
            durationMs: e.durationMs,
          ),
        )
        .toList();
    return generator.generate(segments, toneHz);
  }

  /// Runs the visual flash sequence, toggling both the
  /// hardware torch and the display blink notifier as
  /// needed based on [EncodingSettings.needsTorch] and
  /// [EncodingSettings.needsDisplay].
  Future<void> _runVisualSequence(
    List<ToneEvent> events,
    EncodingSettings settings,
  ) async {
    for (final event in events) {
      if (!_isRunning) break;
      if (event.isOn) {
        if (settings.needsTorch) {
          await _torchService.enable();
        }
        if (settings.needsDisplay) {
          displayBlink.value = true;
        }
      } else {
        if (settings.needsTorch) {
          await _torchService.disable();
        }
        if (settings.needsDisplay) {
          displayBlink.value = false;
        }
      }
      await Future<void>.delayed(
        Duration(milliseconds: event.durationMs),
      );
    }
    if (settings.needsTorch) {
      await _torchService.disable();
    }
    displayBlink.value = false;
  }
}
