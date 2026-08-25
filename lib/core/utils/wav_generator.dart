import 'dart:math';
import 'dart:typed_data';

/// A single tone segment — either a beep (on) or silence (off).
class ToneSegment {
  const ToneSegment({
    required this.isOn,
    required this.durationMs,
  });

  /// Whether this segment is a tone (true) or silence (false).
  final bool isOn;

  /// Duration in milliseconds.
  final int durationMs;
}

/// Generates WAV file data from a list of [ToneSegment]s.
class WavGenerator {
  WavGenerator({this.sampleRate = 44100});

  final int sampleRate;

  /// Builds a complete WAV byte buffer from the given segments.
  Uint8List generate(List<ToneSegment> segments, double frequency) {
    final totalSamples = segments.fold<int>(
      0,
      (sum, s) => sum + _msToSamples(s.durationMs),
    );

    final samples = Int16List(totalSamples);
    var offset = 0;

    for (final segment in segments) {
      final count = _msToSamples(segment.durationMs);
      if (segment.isOn) {
        _fillTone(samples, offset, count, frequency);
      }
      offset += count;
    }

    return _buildWavFile(samples);
  }

  void _fillTone(
    Int16List samples,
    int offset,
    int count,
    double frequency,
  ) {
    final fadeSamples = _msToSamples(2);
    for (var i = 0; i < count; i++) {
      final envelope = _envelope(i, count, fadeSamples);
      final t = i / sampleRate;
      final value = sin(2 * pi * frequency * t) * envelope * 32767;
      samples[offset + i] = value.round().clamp(-32768, 32767);
    }
  }

  double _envelope(int i, int total, int fadeSamples) {
    if (i < fadeSamples) return i / fadeSamples;
    if (i > total - fadeSamples) return (total - i) / fadeSamples;
    return 1;
  }

  int _msToSamples(num ms) => (ms * sampleRate / 1000).round();

  Uint8List _buildWavFile(Int16List samples) {
    final dataSize = samples.length * 2;
    final bytes = Uint8List(44 + dataSize);
    final view = ByteData.view(bytes.buffer);

    _writeString(view, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, Endian.little);
    _writeString(view, 8, 'WAVE');
    _writeString(view, 12, 'fmt ');
    view
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, sampleRate, Endian.little)
      ..setUint32(28, sampleRate * 2, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little);
    _writeString(view, 36, 'data');
    view.setUint32(40, dataSize, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      view.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return bytes;
  }

  void _writeString(ByteData view, int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      view.setUint8(offset + i, s.codeUnitAt(i));
    }
  }
}
