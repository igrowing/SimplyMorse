import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';

/// Platform implementation of [AudioCapture] using the
/// `record` package.
///
/// Captures mono 16-bit PCM audio from the microphone at
/// 8 kHz sample rate, normalized to [-1, 1] doubles.
class AudioCaptureImpl implements AudioCapture {
  AudioCaptureImpl({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  bool _isActive = false;

  @override
  DebugAudioCaptureEventCallback? onDebugEvent;

  int _wallMs() => DateTime.now().millisecondsSinceEpoch;

  @override
  bool get isActive => _isActive;

  @override
  Future<bool> hasPermission() async {
    final granted = await _recorder.hasPermission();
    onDebugEvent?.call(
      timestampMs: _wallMs(),
      event: 'permission',
      detail: 'granted=${granted ? 1 : 0}',
    );
    return granted;
  }

  @override
  Stream<List<double>> start() async* {
    _isActive = true;
    final wallStart = _wallMs();
    onDebugEvent?.call(
      timestampMs: wallStart,
      event: 'start',
      detail: 'requested_sample_rate=44100 channels=1 pcm16',
    );

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    onDebugEvent?.call(
      timestampMs: _wallMs(),
      event: 'started',
      dtMs: _wallMs() - wallStart,
    );

    var bufferCount = 0;
    var lastBufferMs = _wallMs();
    await for (final data in stream) {
      if (!_isActive) break;
      final now = _wallMs();
      bufferCount++;
      onDebugEvent?.call(
        timestampMs: now,
        event: 'buffer',
        dtMs: now - lastBufferMs,
        detail: 'n=$bufferCount bytes=${data.length}',
      );
      lastBufferMs = now;
      yield _bytesToSamples(data);
    }
    _isActive = false;
  }

  @override
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;
    onDebugEvent?.call(timestampMs: _wallMs(), event: 'stop');
    try {
      await _recorder.stop();
    } on Object {
      // Recorder already stopped or the platform threw while
      // tearing down — the stream is closed either way, which
      // wakes the sample generator's await-for loop.
    }
  }

  /// Converts little-endian 16-bit signed PCM bytes to
  /// normalized doubles in [-1, 1].
  List<double> _bytesToSamples(Uint8List data) {
    final samples = <double>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final raw = data[i] | (data[i + 1] << 8);
      final signed = raw > 32767 ? raw - 65536 : raw;
      samples.add(signed / 32768);
    }
    return samples;
  }
}
