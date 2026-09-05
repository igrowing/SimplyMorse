@Tags(['video-recording'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

import '../../../../support/cer.dart';

/// Helper to load a float32 brightness trace from test assets.
///
/// Returns null if the file is not present (e.g. on CI or when the
/// user has not extracted the trace from the video locally).
List<double>? _loadBrightnessTrace(String filename) {
  final file = File('test/assets/recordings/video/$filename');
  if (!file.existsSync()) return null;
  final bytes = file.readAsBytesSync();
  final float32 = bytes.buffer.asFloat32List(
    bytes.offsetInBytes,
    bytes.length ~/ 4,
  );
  return float32.toList();
}

/// Video recording fixture metadata.
class VideoRecordingFixture {
  VideoRecordingFixture({
    required this.name,
    required this.brightnessFile,
    required this.fps,
    required this.expectedWpm,
    required this.expectedText,
    required this.maxCer,
  });

  factory VideoRecordingFixture.fromManifestEntry(
    String name,
    Map<String, dynamic> meta,
  ) {
    // CER tolerance: explicit per-fixture `max_cer` wins; otherwise
    // fall back to the tuned thresholds of the original 30 fps
    // recordings (see git history) and a generic default for new
    // fixtures.
    final byWpm = <int, double>{4: 0.75, 8: 0.40, 20: 0.35};
    return VideoRecordingFixture(
      name: name,
      brightnessFile: meta['brightness_file'] as String,
      fps: (meta['fps'] as num).toDouble(),
      expectedWpm: meta['expected_wpm'] as int,
      expectedText: meta['expected_text'] as String,
      maxCer:
          (meta['max_cer'] as num?)?.toDouble() ??
          byWpm[meta['expected_wpm'] as int] ??
          0.40,
    );
  }

  final String name;
  final String brightnessFile;
  final double fps;
  final int expectedWpm;
  final String expectedText;
  final double maxCer;

  bool get isHighFps => fps > 45;
}

List<VideoRecordingFixture> _loadVideoManifest() {
  final file = File('test/assets/recordings/video/manifest.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json.entries
      .map(
        (e) => VideoRecordingFixture.fromManifestEntry(
          e.key,
          e.value as Map<String, dynamic>,
        ),
      )
      .toList();
}

/// Runs the brightness trace through BrightnessThreshold to detect
/// on/off transitions, through [MorseLockGate] to confirm genuine
/// Morse timing (for slow sending only — see that class), then
/// decodes via MorseDecoder. Matches VideoDecoder's own pipeline.
({List<DecodedElement> elements, String text, double ditMs}) _decodeBrightness(
  VideoRecordingFixture fixture, {
  double onFactor = 0.4,
  double offFactor = 0.4,
  double decayFactor = 0.995,
  double minRange = 0.01,
  int minTransitionMs = 50,
}) {
  final trace = _loadBrightnessTrace(fixture.brightnessFile)!;
  final frameMs = (1000 / fixture.fps).round();

  final threshold = BrightnessThreshold(
    onFactor: onFactor,
    offFactor: offFactor,
    decayFactor: decayFactor,
    minRange: minRange,
    minTransitionMs: minTransitionMs,
  );

  final elements = <DecodedElement>[];
  final gate = MorseLockGate(onElement: elements.add);
  final builder = ElementBuilder(onElement: gate.add);

  for (var i = 0; i < trace.length; i++) {
    final ts = i * frameMs;
    final isOn = threshold.process(trace[i], timestampMs: ts);
    builder.transition(nowOn: isOn, timeMs: threshold.effectiveTransitionMs);
  }
  builder.flush();
  gate.flush();

  // Skip leading off-elements
  final filtered = elements.skipWhile((e) => !e.isOn).toList();

  final morseDecoder = MorseDecoder();
  final text = morseDecoder.decodeElements(filtered);

  final onDurations =
      filtered.where((e) => e.isOn).map((e) => e.durationMs).toList()..sort();
  var ditMs = 0.0;
  if (onDurations.isNotEmpty) {
    final idx = (onDurations.length * 0.25).floor();
    ditMs = onDurations[idx.clamp(0, onDurations.length - 1)].toDouble();
  }

  return (elements: filtered, text: text, ditMs: ditMs);
}

void main() {
  final manifestFile = File('test/assets/recordings/video/manifest.json');
  if (!manifestFile.existsSync()) {
    test('video recording fixtures not available — skipping', () {
      // Ignored: avoid_print is intentional for this test case.
      // ignore: avoid_print
      print('  Video recording tests skipped: manifest.json not found.');
    });
    return;
  }

  final fixtures = _loadVideoManifest();

  // One test per fixture whose brightness trace is available.
  // Fixtures without a local trace are reported and skipped
  // individually, so a partially-extracted set still runs the
  // rest.
  final available = <VideoRecordingFixture>[];
  for (final f in fixtures) {
    if (_loadBrightnessTrace(f.brightnessFile) != null) {
      available.add(f);
    } else {
      test('${f.name} trace missing — skipping', () {
        // Ignored: avoid_print is intentional for this test case.
        // ignore: avoid_print
        print(
          '  ${f.name}: brightness trace ${f.brightnessFile} not '
          'found locally — extract it to run this test.',
        );
      });
    }
  }

  if (available.isEmpty) {
    return;
  }

  group('VideoDecoder brightness traces from real recordings', () {
    for (final fixture in available) {
      test(
        '${fixture.name} (${fixture.fps} fps) decodes within CER budget',
        () {
          final result = _decodeBrightness(fixture);

          expect(result.elements.length, greaterThan(20));
          expect(result.text, isNotEmpty);

          final cer = characterErrorRate(
            result.text,
            fixture.expectedText,
          );

          // Ignored: avoid_print is intentional for this test case.
          // ignore: avoid_print
          print(cerReport(fixture.name, result.text, fixture.expectedText));

          expect(
            cer,
            lessThanOrEqualTo(fixture.maxCer),
            reason:
                'CER ${(cer * 100).toStringAsFixed(1)}% exceeds the '
                '${(fixture.maxCer * 100).toStringAsFixed(0)}% budget for '
                '${fixture.name}.',
          );
        },
      );
    }

    // High-FPS recordings of the same text at the same WPM should
    // decode at least as well as their 30 fps counterparts — that
    // is the whole point of the high frame-rate capture path.
    test('high-FPS fixtures decode no worse than 30 fps counterparts', () {
      final byWpm = <int, List<VideoRecordingFixture>>{};
      for (final f in available) {
        byWpm.putIfAbsent(f.expectedWpm, () => []).add(f);
      }

      for (final entry in byWpm.entries) {
        final highFps = entry.value.where((f) => f.isHighFps).toList();
        final lowFps = entry.value.where((f) => !f.isHighFps).toList();
        if (highFps.isEmpty || lowFps.isEmpty) continue;

        for (final hi in highFps) {
          for (final lo in lowFps) {
            final cerHi = characterErrorRate(
              _decodeBrightness(hi).text,
              hi.expectedText,
            );
            final cerLo = characterErrorRate(
              _decodeBrightness(lo).text,
              lo.expectedText,
            );
            expect(
              cerHi,
              lessThanOrEqualTo(cerLo + 0.02),
              reason:
                  '${hi.name} (${hi.fps} fps, CER '
                  '${(cerHi * 100).toStringAsFixed(1)}%) decodes worse '
                  'than ${lo.name} (${lo.fps} fps, CER '
                  '${(cerLo * 100).toStringAsFixed(1)}%) — a higher '
                  'frame rate must not degrade accuracy.',
            );
          }
        }
      }
    });
  });
}
