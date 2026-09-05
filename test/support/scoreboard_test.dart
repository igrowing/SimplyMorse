@Tags(['scoreboard'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

import 'cer.dart';

/// Prints a single accuracy scoreboard over every audio and video
/// fixture. Not an assertion suite — run it to compare decoder
/// changes:  flutter test --tags scoreboard test/support/scoreboard_test.dart
void main() {
  test('decoder accuracy scoreboard', () {
    var totalErr = 0;
    var totalLen = 0;
    final lines = <String>[];

    // ── Audio ────────────────────────────────────────────────────
    final audioManifest =
        jsonDecode(
              File('test/assets/recordings/manifest.json').readAsStringSync(),
            )
            as List<dynamic>;

    for (final entry in audioManifest.cast<Map<String, dynamic>>()) {
      final bytes = File(
        'test/assets/recordings/${entry['file']}',
      ).readAsBytesSync();
      final samples = bytes.buffer
          .asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4)
          .toList();

      final sr = entry['sampleRate'] as int;
      final fftSz = sr >= 44100 ? 2048 : 256;
      final blockSz = (sr * 5 / 1000).round();
      final decoder = AudioDecoder(
        sampleRate: sr,
        fftSize: fftSz,
        blockSize: blockSz,
        bandwidth: 0,
      );
      final elements = <DecodedElement>[];
      decoder.onElement = elements.add;

      const batch = 4096;
      for (var i = 0; i < samples.length; i += batch) {
        final end = i + batch < samples.length ? i + batch : samples.length;
        decoder.processSamples(samples.sublist(i, end));
      }
      decoder.flush();

      final text = MorseDecoder().decodeElements(
        elements.skipWhile((e) => !e.isOn).toList(),
      );
      final expected = entry['expectedText'] as String;
      totalErr += editDistance(text, expected);
      totalLen += expected.length;
      lines.add(cerReport('audio ${entry['file']}', text, expected));
    }

    // ── Video ────────────────────────────────────────────────────
    final videoManifest =
        jsonDecode(
              File(
                'test/assets/recordings/video/manifest.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;

    for (final entry in videoManifest.entries) {
      final meta = entry.value as Map<String, dynamic>;
      final file = File(
        'test/assets/recordings/video/${meta['brightness_file']}',
      );
      if (!file.existsSync()) continue;
      final bytes = file.readAsBytesSync();
      final trace = bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.length ~/ 4,
      );

      final frameMs = (1000 / (meta['fps'] as num).toDouble()).round();
      final threshold = BrightnessThreshold();
      final elements = <DecodedElement>[];
      final gate = MorseLockGate(onElement: elements.add);
      final builder = ElementBuilder(onElement: gate.add);
      for (var i = 0; i < trace.length; i++) {
        final t = i * frameMs;
        final isOn = threshold.process(trace[i], timestampMs: t);
        builder.transition(
          nowOn: isOn,
          timeMs: threshold.effectiveTransitionMs,
        );
      }
      builder.flush();
      gate.flush();

      final text = MorseDecoder().decodeElements(
        elements.skipWhile((e) => !e.isOn).toList(),
      );
      final expected = meta['expected_text'] as String;
      totalErr += editDistance(text, expected);
      totalLen += expected.length;
      lines.add(cerReport('video ${entry.key}', text, expected));
    }

    // ignore_for_file: avoid_print — this test exists to print a
    // scoreboard for comparing decoder changes.
    lines.forEach(print);
    print(
      '  ══ TOTAL CER=${(totalErr / totalLen * 100).toStringAsFixed(1)}% '
      '($totalErr/$totalLen)',
    );
  });
}
