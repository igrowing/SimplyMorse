import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';

import '../../../../helpers/decoding_fakes.dart';

void main() {
  late MorseDecoder morseDecoder;
  late AudioDecoder audioDecoder;
  late FakeAudioCapture audioCapture;
  late VideoDecoder videoDecoder;
  late FakeCameraCapture cameraCapture;

  setUp(() {
    morseDecoder = MorseDecoder();
    audioDecoder = AudioDecoder();
    audioCapture = FakeAudioCapture();
    videoDecoder = VideoDecoder();
    cameraCapture = FakeCameraCapture();
  });

  DecodingController makeController() {
    final controller = DecodingController(
      morseDecoder: morseDecoder,
      audioDecoder: audioDecoder,
      audioCapture: audioCapture,
      videoDecoder: videoDecoder,
      cameraCapture: cameraCapture,
    );
    return controller;
  }

  group('DecodingController WPM', () {
    test('returns 0 when no elements decoded', () {
      final controller = makeController();
      expect(controller.currentWpm, 0);
    });

    test('returns 0 when only off-elements present', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: false, durationMs: 120),
        const DecodedElement(isOn: false, durationMs: 360),
      ]);
      expect(controller.currentWpm, 0);
    });

    test('estimates WPM from single dit', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 120),
      ]);
      // dit = 120ms, WPM = 1200 / 120 = 10
      expect(controller.currentWpm, 10);
    });

    test('estimates WPM from multiple elements', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 60), // dit
        const DecodedElement(isOn: false, durationMs: 60), // intra-gap
        const DecodedElement(isOn: true, durationMs: 180), // dah (3x dit)
        const DecodedElement(isOn: false, durationMs: 180), // char-gap
      ]);
      // dit = 60ms (shortest on), WPM = 1200 / 60 = 20
      expect(controller.currentWpm, 20);
    });

    test('uses shortest on-element as dit', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 200), // dah
        const DecodedElement(isOn: false, durationMs: 200), // gap
        const DecodedElement(isOn: true, durationMs: 100), // dit (shorter)
      ]);
      // dit = 100ms, WPM = 1200 / 100 = 12
      expect(controller.currentWpm, 12);
    });

    test('handles very fast Morse (short dit)', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(
          isOn: true,
          durationMs: 40,
        ), // dit at 40ms = 30 WPM
      ]);
      expect(controller.currentWpm, 30);
    });

    test('handles very slow Morse (long dit)', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(
          isOn: true,
          durationMs: 600,
        ), // dit at 600ms = 2 WPM
      ]);
      expect(controller.currentWpm, 2);
    });

    test('clear resets WPM to 0', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 120),
      ]);
      expect(controller.currentWpm, 10);

      controller.clear();
      expect(controller.currentWpm, 0);
    });

    test('WPM updates as more elements arrive', () {
      final controller = makeController();
      // First element: 120ms dit → 10 WPM
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 120),
      ]);
      expect(controller.currentWpm, 10);

      // Second batch has a shorter dit: 60ms → 20 WPM
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 60),
      ]);
      expect(controller.currentWpm, 20);
    });

    test('ignores zero-duration elements', () {
      final controller = makeController();
      controller.processElements([
        const DecodedElement(isOn: true, durationMs: 0),
        const DecodedElement(isOn: true, durationMs: 120),
      ]);
      // The 0ms element should be ignored; dit = 120ms → 10 WPM
      expect(controller.currentWpm, 10);
    });
  });
}
