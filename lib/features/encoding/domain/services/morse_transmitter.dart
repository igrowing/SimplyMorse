import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

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
class MorseTransmitter {
  MorseTransmitter({required TorchService torchService})
    : _torchService = torchService;

  final TorchService _torchService;
  final AudioPlayer _player = AudioPlayer();

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

    final needsAudio =
        settings.mode == EncodingMode.sound ||
        settings.mode == EncodingMode.both;
    final needsFlash =
        settings.mode == EncodingMode.flash ||
        settings.mode == EncodingMode.both;

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
          _isRunning = false;
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
    if (needsAudio) {
      final wav = _generateWav(events, settings.toneHz);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(BytesSource(wav));
    }

    // Flash transmission
    if (needsFlash) {
      await _runFlashSequence(events);
    }
  }

  /// Stops any ongoing transmission.
  Future<void> stop() async {
    _isRunning = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    await _player.stop();
    await _torchService.disable();
  }

  /// Disposes all resources.
  void dispose() {
    _progressTimer?.cancel();
    _player.dispose();
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

  Future<void> _runFlashSequence(List<ToneEvent> events) async {
    for (final event in events) {
      if (!_isRunning) break;
      if (event.isOn) {
        await _torchService.enable();
      } else {
        await _torchService.disable();
      }
      await Future<void>.delayed(
        Duration(milliseconds: event.durationMs),
      );
    }
    await _torchService.disable();
  }
}
