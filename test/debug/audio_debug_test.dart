import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';

List<double> loadF32(String filename) {
  final file = File('test/assets/recordings/$filename');
  final bytes = file.readAsBytesSync();
  return bytes.buffer
      .asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4)
      .toList();
}

void main() {
  test('lock freq for all recordings', () {
    final recordings = [
      '1000Hz_2times_8wpm.f32',
      '400Hz_2times_8wpm.f32',
      '700Hz_1time_3wpm.f32',
      '700Hz_2times_8wpm.f32',
      '700Hz_3times_20wpm.f32',
    ];
    for (final name in recordings) {
      final samples = loadF32(name);
      final decoder = AudioDecoder(
        sampleRate: 8000,
        bandwidth: 80,
        envelopeCutoffHz: 40,
        minElementMs: 30,
      );
      var locked = 0.0;
      decoder.onLock = (freq) => locked = freq;
      const bs = 4096;
      for (var i = 0; i < samples.length; i += bs) {
        final end = i + bs < samples.length ? i + bs : samples.length;
        decoder.processSamples(samples.sublist(i, end));
      }
      print('$name -> locked ${locked.toStringAsFixed(1)}Hz');
    }
  });
}
