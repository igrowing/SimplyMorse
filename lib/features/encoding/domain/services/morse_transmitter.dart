import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'package:simply_morse/core/services/torch_service.dart';
import 'package:simply_morse/core/utils/wav_generator.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart'
    show LightMethod;
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
  MorseTransmitter({required this._torchService});

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

  /// Countdown through the initial delay, shared by every
  /// output method. Non-null (seconds remaining) while the
  /// delay is running, null otherwise. The UI shows a
  /// countdown overlay from this. Living on the transmitter
  /// — the domain layer that actually applies the delay —
  /// guarantees audio, torch, and display all start only
  /// after the countdown, on one code path.
  final ValueNotifier<int?> countdownRemaining = ValueNotifier<int?>(null);

  Timer? _progressTimer;
  bool _isRunning = false;

  /// Whether the web audio pipeline has been warmed up yet. See
  /// [_primeWebAudioContext] for why this exists.
  bool _webAudioPrimed = false;

  /// Completes when the tone/flash timeline has fully played out
  /// (or when [stop] aborts it). In audio-only mode there is no
  /// blocking playback loop to await, so [transmit] waits on this
  /// instead — it is driven by the same wall-clock as the progress
  /// highlight, so the caller resumes exactly when the last element
  /// finishes, not several seconds early or late.
  Completer<void>? _timelineComplete;

  /// Transmits the given [events] using the specified [settings].
  Future<void> transmit({
    required List<ToneEvent> events,
    required EncodingSettings settings,
    required ProgressCallback onProgress,
    required CompleteCallback onComplete,
  }) async {
    if (_isRunning) await stop();

    _isRunning = true;

    // Initial delay: applied here, on the single path every
    // output method (audio, torch, display) goes through, so
    // none of them can start before the countdown finishes.
    if (settings.initialDelaySec > 0) {
      final totalMs = (settings.initialDelaySec * 1000).round();
      final wholeSeconds = totalMs ~/ 1000;
      for (var i = wholeSeconds; i >= 1; i--) {
        if (!_isRunning) {
          countdownRemaining.value = null;
          return;
        }
        countdownRemaining.value = i;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      final remainderMs = totalMs % 1000;
      if (remainderMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: remainderMs));
      }
      countdownRemaining.value = null;
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

    // Kick off audio first. AudioPlayer.play() only returns once
    // playback has actually started, so anchoring the progress clock
    // after it keeps the highlight — and the audio-only wait below —
    // aligned with the sound the listener hears.
    if (settings.needsAudio) {
      await playAudio(_generateWav(events, settings.toneHz));
      if (!_isRunning) return;
    }

    // One wall-clock for the whole timeline: it advances the progress
    // highlight, fires onComplete, and completes [_timelineComplete]
    // when the last element has been sent.
    final startTime = DateTime.now();
    final timelineComplete = Completer<void>();
    _timelineComplete = timelineComplete;
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
      if (elapsedMs >= totalDuration) {
        timer.cancel();
        if (!timelineComplete.isCompleted) timelineComplete.complete();
        onProgress(-1);
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
    });

    // The visual sequence blocks for its full duration on its own.
    // Audio-only has no such loop, so wait out the shared timeline
    // clock — otherwise transmit() resolves the instant playback
    // starts and the caller (the loop's between-repeats delay) begins
    // counting down over the still-playing tone, cutting it short.
    if (settings.needsTorch || settings.needsDisplay) {
      await _runVisualSequence(events, settings);
    } else if (settings.needsAudio) {
      await timelineComplete.future;
    }

    _timelineComplete = null;
    _isRunning = false;
  }

  /// Stops any ongoing transmission.
  Future<void> stop() async {
    _isRunning = false;
    _progressTimer?.cancel();
    _progressTimer = null;
    if (_timelineComplete?.isCompleted == false) {
      _timelineComplete!.complete();
    }
    _timelineComplete = null;
    countdownRemaining.value = null;
    await _player?.stop();
    await _torchService.disable();
    displayBlink.value = false;
  }

  /// Disposes all resources.
  void dispose() {
    _progressTimer?.cancel();
    unawaited(_player?.dispose());
    displayBlink.dispose();
    countdownRemaining.dispose();
  }

  /// Starts audio playback of the generated [wav]. Returns once
  /// playback has been kicked off — [AudioPlayer.play] does not
  /// wait for the tone to finish, which is why [transmit] waits
  /// out the timeline itself in audio-only mode.
  ///
  /// Overridable so tests can exercise the timeline logic without
  /// a platform audio backend.
  @protected
  @visibleForTesting
  Future<void> playAudio(Uint8List wav) async {
    if (kIsWeb && !_webAudioPrimed) {
      _webAudioPrimed = true;
      await _primeWebAudioContext();
    }
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.play(BytesSource(wav));
  }

  /// Browsers create the Web Audio context suspended and only resume
  /// it on the first play() call. That resume is asynchronous, and
  /// whatever audio is already queued while it spins up gets its
  /// leading samples dropped — which is why, on web only, the very
  /// first dit/dah of a fresh transmitter's first transmission was
  /// getting swallowed while every element after it played fine.
  /// Spending that one-time warm-up cost on a throwaway silent blip
  /// keeps it from eating real audio.
  Future<void> _primeWebAudioContext() async {
    final silence = WavGenerator().generate(
      const [ToneSegment(isOn: false, durationMs: 60)],
      440,
    );
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.play(BytesSource(silence));
  }

  Uint8List _generateWav(List<ToneEvent> events, double toneHz) {
    final generator = WavGenerator();
    final segments = events
        .map((e) => ToneSegment(isOn: e.isOn, durationMs: e.durationMs))
        .toList();
    return generator.generate(segments, toneHz, keepAlive: kIsWeb);
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
      await Future<void>.delayed(Duration(milliseconds: event.durationMs));
    }
    if (settings.needsTorch) {
      await _torchService.disable();
    }
    displayBlink.value = false;
  }
}
