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
  bool get isActive => _isActive;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Stream<List<double>> start() async* {
    _isActive = true;
    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 8000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );

    await for (final data in stream) {
      if (!_isActive) break;
      yield _bytesToSamples(data);
    }
    _isActive = false;
  }

  @override
  Future<void> stop() async {
    _isActive = false;
    try {
      await _recorder.stop();
    } on Exception {
      // Already stopped — safe to ignore.
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
