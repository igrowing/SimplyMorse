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

/// Helper to load float32 brightness trace from test assets.
///
/// Returns null if the file is not present (e.g. on CI or when the
/// user has not downloaded the video recordings locally).
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
    required this.brightnessFile,
    required this.fps,
    required this.nFrames,
    required this.durationS,
    required this.expectedWpm,
    required this.expectedText,
  });

  final String brightnessFile;
  final double fps;
  final int nFrames;
  final double durationS;
  final int expectedWpm;
  final String expectedText;
}

List<VideoRecordingFixture> _loadVideoManifest() {
  final file = File('test/assets/recordings/video/manifest.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return json.entries
      .map(
        (e) => VideoRecordingFixture(
          brightnessFile:
              (e.value as Map<String, dynamic>)['brightness_file'] as String,
          fps: (e.value as Map<String, dynamic>)['fps'] as double,
          nFrames: (e.value as Map<String, dynamic>)['n_frames'] as int,
          durationS: (e.value as Map<String, dynamic>)['duration_s'] as double,
          expectedWpm: (e.value as Map<String, dynamic>)['expected_wpm'] as int,
          expectedText:
              (e.value as Map<String, dynamic>)['expected_text'] as String,
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
  final frameMs = (1000 / fixture.fps).round(); // ~33ms at 30fps

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
  // Skip all tests in this file if the brightness trace fixtures
  // are not available locally.
  final manifestFile = File('test/assets/recordings/video/manifest.json');
  final manifestExists = manifestFile.existsSync();
  final firstTraceExists = _loadBrightnessTrace('4wpm_brightness.f32') != null;

  if (!manifestExists || !firstTraceExists) {
    test('video recording fixtures not available — skipping', () {
      // Ignored: avoid_print is intentional for this test case.
      // ignore: avoid_print
      print(
        '  Video recording tests skipped: brightness trace fixtures '
        'not found locally. Download the video recordings and extract '
        'traces to run these tests.',
      );
    });
    return;
  }

  final fixtures = _loadVideoManifest();

  group('VideoDecoder brightness traces from real recordings', () {
    test('4wpm detects blinking dot and decodes Morse elements', () {
      final fixture = fixtures.firstWhere(
        (f) => f.brightnessFile.contains('4wpm'),
      );
      final result = _decodeBrightness(fixture);

      expect(result.elements.length, greaterThan(20));
      expect(result.text, isNotEmpty);
      expect(result.ditMs, greaterThan(200));
      // The 4 WPM recording spends its first ~10 s acquiring, which
      // injects junk elements ahead of the message. MorseLockGate
      // (below fastUnitThresholdMs, sending here is slow enough to
      // gate) drops most of it but not all — some junk still slips
      // through close enough to the real unit to pass the fit check.
      expect(
        characterErrorRate(result.text, fixture.expectedText),
        lessThanOrEqualTo(0.75),
      );

      // Ignored: avoid_print is intentional for this test case.
      // ignore: avoid_print
      print(cerReport('4wpm', result.text, fixture.expectedText));
    });

    test('8wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.brightnessFile.contains('8wpm'),
      );
      final result = _decodeBrightness(fixture);

      expect(result.elements.length, greaterThan(30));
      expect(result.text, isNotEmpty);
      expect(result.ditMs, closeTo(150, 50));
      expect(result.text, contains('ELLO'));
      expect(
        characterErrorRate(result.text, fixture.expectedText),
        lessThanOrEqualTo(0.40),
      );

      // Ignored: avoid_print is intentional for this test case.
      // ignore: avoid_print
      print(cerReport('8wpm', result.text, fixture.expectedText));
    });

    test('20wpm decodes "HELLO, WORLD!"', () {
      final fixture = fixtures.firstWhere(
        (f) => f.brightnessFile.contains('20wpm'),
      );
      final result = _decodeBrightness(fixture);

      expect(result.elements.length, greaterThan(60));
      expect(result.text, isNotEmpty);
      expect(result.ditMs, closeTo(60, 20));
      // 20 WPM at 30 fps is 1.8 frames per dit — the dah and
      // character-gap clusters overlap, so this is frame-rate
      // limited rather than threshold limited. BrightnessThreshold's
      // falling-edge bias correction recovers most of that (measured
      // 37.0% -> 29.6%) by undoing the systematic mark/gap dilation
      // frame integration and LED persistence introduce — see its
      // class docs.
      expect(
        characterErrorRate(result.text, fixture.expectedText),
        lessThanOrEqualTo(0.35),
      );

      // Ignored: avoid_print is intentional for this test case.
      // ignore: avoid_print
      print(cerReport('20wpm', result.text, fixture.expectedText));
    });
  });
}
