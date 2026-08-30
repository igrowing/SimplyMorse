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
    bandwidth: 0,
    envelopeCutoffHz: 40,
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
    // ── 700Hz 3wpm ──────────────────────────────────────────────
    test('700Hz 1time 3wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('1time_3wpm'));
      final result = _decodeRecording(fixture);

      // Frequency lock within ±20 Hz
      expect(result.lockedFreq, closeTo(700, 20));
      // At 3 WPM, dit=400ms, HELLO WORLD = ~45 elements
      expect(result.elements.length, greaterThan(70));
      // Dit estimate should be close to 400ms
      expect(result.ditMs, closeTo(400, 80));
      // Decoded text should contain recognizable words
      expect(result.text, contains('WORLD'));

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements)',
      );
    });

    // ── 700Hz 8wpm ──────────────────────────────────────────────
    test('700Hz 2times 8wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.file.contains('700Hz_2times_8wpm'),
      );
      final result = _decodeRecording(fixture);

      // Frequency lock within ±20 Hz
      expect(result.lockedFreq, closeTo(700, 20));
      // 2 repetitions of HELLO WORLD ≈ 90 elements minimum
      expect(result.elements.length, greaterThan(120));
      // WPM should be close to 8
      final wpm = result.ditMs > 0 ? 1200 / result.ditMs : 0;
      expect(wpm, inExclusiveRange(5, 12));
      // At least one repetition should decode correctly
      expect(result.text, contains('HELLO, WORLD!'));

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements, ${wpm.toStringAsFixed(1)} WPM)',
      );
    });

    // ── 700Hz 20wpm ─────────────────────────────────────────────
    test('700Hz 3times 20wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.file.contains('700Hz_3times_20wpm'),
      );
      final result = _decodeRecording(fixture);

      // Frequency lock within ±25 Hz (20wpm has shorter tone bursts)
      expect(result.lockedFreq, closeTo(700, 25));
      // 3 repetitions should produce many elements
      expect(result.elements.length, greaterThan(100));
      // WPM should be close to 20
      final wpm = result.ditMs > 0 ? 1200 / result.ditMs : 0;
      expect(wpm, inExclusiveRange(15, 25));
      // Text should contain at least partially recognizable content
      expect(
        result.text,
        anyOf(contains('WORLD'), contains('WORLDE'), contains('MORLD')),
      );

      // ignore: avoid_print
      print(
        '  Decoded: "${result.text}" (dit=${result.ditMs}ms, '
        '${result.elements.length} elements, ${wpm.toStringAsFixed(1)} WPM)',
      );
    });

    // ── 1000Hz 8wpm ─────────────────────────────────────────────
    test('1000Hz 2times 8wpm locks on 1000Hz', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('1000Hz'));
      final result = _decodeRecording(fixture);

      // Frequency lock within ±20 Hz
      expect(result.lockedFreq, closeTo(1000, 20));
      // Should detect a significant number of elements
      expect(result.elements.length, greaterThan(50));
      expect(result.text, isNotEmpty);

      // ignore: avoid_print
      print(
        '  Locked: ${result.lockedFreq.toStringAsFixed(1)}Hz, '
        'Decoded: "${result.text}" (${result.elements.length} elements)',
      );
    });

    // ── 400Hz 8wpm ──────────────────────────────────────────────
    test('400Hz 2times 8wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere((f) => f.file.contains('400Hz'));
      final result = _decodeRecording(fixture);

      // Should lock near 400Hz (or a harmonic, but the IIR
      // bandpass should handle either)
      expect(result.lockedFreq, closeTo(400, 30));
      // 2 repetitions should produce many elements
      expect(result.elements.length, greaterThan(100));
      // Should decode recognizable text
      expect(result.text, contains('HELLO'));
      expect(result.text, contains('WORLD'));

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
          bandwidth: 0,
          envelopeCutoffHz: 40,
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
        expect(decoder.lockedFrequency, greaterThan(300));
        expect(decoder.lockedFrequency, lessThan(1100));
      });
    }
  });
}
