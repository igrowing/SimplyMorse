import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';

List<double> loadF32(String filename) {
  final file = File('test/assets/recordings/$filename');
  final bytes = file.readAsBytesSync();
  return bytes.buffer
      .asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4)
      .toList();
}

void main() {
  test('debug 1000Hz', () {
    final samples = loadF32('1000Hz_2times_8wpm.f32');
    final decoder = AudioDecoder(
      sampleRate: 8000,
      releaseMs: 20,
      minElementMs: 30,
    );
    final elements = <DecodedElement>[];
    decoder.onElement = (el) => elements.add(el);
    decoder.onLock = (freq) => print('LOCKED ${freq.toStringAsFixed(1)}Hz');

    var frame = 0;
    decoder.onDebugTracking =
        ({
          required totalSamples,
          required sampleRate,
          required freq,
          required power,
          required envelope,
          required noiseFloor,
          required onThreshold,
          required offThreshold,
          required isOn,
        }) {
          frame++;
          if (frame <= 30) {
            print(
              'f=$frame p=${power.toStringAsFixed(3)} env=${envelope.toStringAsFixed(3)} nf=${noiseFloor.toStringAsFixed(3)} onT=${onThreshold.toStringAsFixed(3)} offT=${offThreshold.toStringAsFixed(3)} isOn=$isOn',
            );
          }
        };

    const bs = 4096;
    for (var i = 0; i < samples.length; i += bs) {
      final end = i + bs < samples.length ? i + bs : samples.length;
      decoder.processSamples(samples.sublist(i, end));
    }

    print('Elements: ${elements.length}');
    for (var i = 0; i < elements.length && i < 20; i++) {
      print(
        '  el[$i] ${elements[i].isOn ? "ON" : "OFF"} ${elements[i].durationMs}ms',
      );
    }
    final onD = elements.where((e) => e.isOn).map((e) => e.durationMs).toList()
      ..sort();
    final offD =
        elements.where((e) => !e.isOn).map((e) => e.durationMs).toList()
          ..sort();
    print(
      'On: ${onD.sublist(0, onD.length > 10 ? 10 : onD.length)} p25=${onD.isNotEmpty ? onD[onD.length ~/ 4] : 0}',
    );
    print('Off: ${offD.sublist(0, offD.length > 10 ? 10 : offD.length)}');
  });
}
