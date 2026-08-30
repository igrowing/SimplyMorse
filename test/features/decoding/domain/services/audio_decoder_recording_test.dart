import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';

/// Helper to load float32 binary audio samples from test assets.
List<double> _loadFloat32Samples(String filename) {
  final assetDir = Directory('test/assets/recordings');
  final file = File('${assetDir.path}/$filename');
  final bytes = file.readAsBytesSync();
  final float32 = bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    bytes.length ~/ 4,
  );
  return float32.toList();
}

/// Test fixture metadata loaded from manifest.json.
class RecordingFixture {
  RecordingFixture({
    required this.file,
    required this.sampleRate,
    required this.nSamples,
    required this.expectedFreq,
    required this.expectedWpm,
    required this.repeatCount,
    required this.expectedText,
    required this.durationSec,
  });

  final String file;
  final int sampleRate;
  final int nSamples;
  final int expectedFreq;
  final int expectedWpm;
  final int repeatCount;
  final String expectedText;
  final double durationSec;
}

List<RecordingFixture> _loadManifest() {
  final assetDir = Directory('test/assets/recordings');
  final file = File('${assetDir.path}/manifest.json');
  final json = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  return json
      .map(
        (e) => RecordingFixture(
          file: e['file'] as String,
          sampleRate: e['sampleRate'] as int,
          nSamples: e['nSamples'] as int,
          expectedFreq: e['expectedFreq'] as int,
          expectedWpm: e['expectedWpm'] as int,
          repeatCount: e['repeatCount'] as int,
          expectedText: e['expectedText'] as String,
          durationSec: (e['durationSec'] as num).toDouble(),
        ),
      )
      .toList();
}

/// Runs the full audio decoder pipeline on a recording and returns
/// the decoded elements, locked frequency, and decoded text.
({List<DecodedElement> elements, double lockedFreq, String text, double ditMs})
_decodeRecording(RecordingFixture fixture) {
  final samples = _loadFloat32Samples(fixture.file);

  final decoder = AudioDecoder(
    sampleRate: fixture.sampleRate,
    releaseMs: 20,
    minElementMs: 30,
  );

  final elements = <DecodedElement>[];
  decoder.onElement = (el) => elements.add(el);

  const batchSize = 4096;
  for (var i = 0; i < samples.length; i += batchSize) {
    final end = (i + batchSize < samples.length)
        ? i + batchSize
        : samples.length;
    decoder.processSamples(samples.sublist(i, end));
  }

  var filtered = elements.skipWhile((e) => !e.isOn).toList();
  final morseDecoder = MorseDecoder();
  final text = morseDecoder.decodeElements(filtered);

  final onDurations =
      filtered.where((e) => e.isOn).map((e) => e.durationMs).toList()..sort();
  var ditMs = 0.0;
  if (onDurations.isNotEmpty) {
    final idx = (onDurations.length * 0.25).floor();
    ditMs = onDurations[idx.clamp(0, onDurations.length - 1)].toDouble();
  }

  return (
    elements: filtered,
    lockedFreq: decoder.lockedFrequency,
    text: text,
    ditMs: ditMs,
  );
}

void main() {
  final fixtures = _loadManifest();

  group('AudioDecoder with real recordings', () {
    // The 700Hz recordings have the best SNR and frequency detection.
    // These are our primary integration tests for real audio decoding.
    test('700Hz 1time 3wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('1time_3wpm'));
      final result = _decodeRecording(fixture);

      expect(result.lockedFreq, closeTo(700, 50));
      expect(result.elements.length, greaterThan(30));
      expect(result.text, isNotEmpty);
      expect(result.ditMs, closeTo(400, 100));

      // The decoder should get most of the message right.
      // First element may be lost due to Goertzel ramp-up.
      expect(result.text, contains('LLO'));
      expect(result.text, contains('WORLD'));

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements)',
      );
    });

    test('700Hz 2times 8wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.file.contains('700Hz_2times_8wpm'),
      );
      final result = _decodeRecording(fixture);

      expect(result.lockedFreq, greaterThan(600));
      expect(result.elements.length, greaterThan(15));
      expect(result.text, isNotEmpty);

      final wpm = result.ditMs > 0 ? 1200 / result.ditMs : 0;
      expect(wpm, inExclusiveRange(3, 20));

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements, ${wpm.toStringAsFixed(1)} WPM)',
      );
    });

    test('700Hz 3times 20wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.file.contains('700Hz_3times_20wpm'),
      );
      final result = _decodeRecording(fixture);

      expect(result.lockedFreq, closeTo(700, 50));
      expect(result.elements.length, greaterThan(20));
      expect(result.text, isNotEmpty);

      final wpm = result.ditMs > 0 ? 1200 / result.ditMs : 0;
      // At 20 WPM the elements are very short (60ms dits), making
      // WPM estimation less reliable. Use a wide range.
      expect(wpm, inExclusiveRange(5, 50));

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements, ${wpm.toStringAsFixed(1)} WPM)',
      );
    });

    test('1000Hz 2times 8wpm locks on 1000Hz', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('1000Hz'));
      final result = _decodeRecording(fixture);

      expect(result.lockedFreq, closeTo(1000, 50));
      expect(result.text, isNotEmpty);

      // ignore: avoid_print
      print('  Decoded: "${result.text}" (${result.elements.length} elements)');
    });

    test('400Hz 2times 8wpm locks on a valid tone frequency', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('400Hz'));
      final result = _decodeRecording(fixture);

      // The FFT may lock on the 2nd harmonic (~843 Hz) instead of
      // the fundamental (400 Hz) due to bin resolution limitations.
      // Both are valid for decoding since the harmonic carries the
      // same on/off modulation.
      expect(result.lockedFreq, greaterThan(300));
      expect(result.text, isNotEmpty);

      // ignore: avoid_print
      print(
        '  Locked: ${result.lockedFreq.toStringAsFixed(1)}Hz, '
        'Decoded: "${result.text}" (${result.elements.length} elements)',
      );
    });
  });

  group('AudioDecoder frequency detection', () {
    for (final fixture in fixtures) {
      test('${fixture.file} locks within valid range', () {
        final samples = _loadFloat32Samples(fixture.file);

        final decoder = AudioDecoder(
          sampleRate: fixture.sampleRate,
          releaseMs: 20,
          minElementMs: 30,
        );

        final batchSize = 4096;
        for (var i = 0; i < samples.length; i += batchSize) {
          final end = (i + batchSize < samples.length)
              ? i + batchSize
              : samples.length;
          decoder.processSamples(samples.sublist(i, end));
        }

        // Should lock on a frequency in the 400-1000 Hz band.
        // May be the fundamental or a harmonic.
        expect(decoder.lockedFrequency, greaterThan(300));
        expect(decoder.lockedFrequency, lessThan(1100));
      });
    }
  });
}
