import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_mode.dart';
import 'package:simply_morse/features/decoding/domain/models/decoding_status.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
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

  DecodingController makeController({
    DecodingMode mode = DecodingMode.audio,
  }) {
    final controller = DecodingController(
      morseDecoder: morseDecoder,
      audioDecoder: audioDecoder,
      audioCapture: audioCapture,
      videoDecoder: videoDecoder,
      cameraCapture: cameraCapture,
    );
    controller.init(mode);
    return controller;
  }

  group('DecodingController', () {
    group('initial state', () {
      test('starts idle with empty text', () {
        final controller = makeController();

        expect(controller.status, DecodingStatus.idle);
        expect(controller.decodedText, isEmpty);
        expect(controller.isIdle, isTrue);
        expect(controller.isListening, isFalse);
        expect(controller.isPaused, isFalse);
      });

      test('mode is set by init', () {
        final audioController = makeController(mode: DecodingMode.audio);
        expect(audioController.mode, DecodingMode.audio);

        final videoController = makeController(mode: DecodingMode.video);
        expect(videoController.mode, DecodingMode.video);
      });
    });

    group('start / pause / resume', () {
      test('start sets status to listening', () {
        final controller = makeController();

        controller.start();

        expect(controller.status, DecodingStatus.listening);
        expect(controller.isListening, isTrue);
      });

      test('pause sets status to paused', () {
        final controller = makeController();
        controller.start();

        controller.pause();

        expect(controller.status, DecodingStatus.paused);
        expect(controller.isPaused, isTrue);
      });

      test('resume sets status back to listening', () {
        final controller = makeController();
        controller.start();
        controller.pause();

        controller.resume();

        expect(controller.status, DecodingStatus.listening);
        expect(controller.isListening, isTrue);
      });

      test('start in audio mode activates audio capture', () {
        final controller = makeController(mode: DecodingMode.audio);

        controller.start();

        expect(audioCapture.isActive, isTrue);
      });

      test('start in video mode activates camera capture', () {
        final controller = makeController(mode: DecodingMode.video);

        controller.start();

        expect(cameraCapture.isActive, isTrue);
      });

      test('pause stops audio capture', () {
        final controller = makeController(mode: DecodingMode.audio);
        controller.start();

        controller.pause();

        expect(audioCapture.isActive, isFalse);
      });

      test('pause stops camera capture', () {
        final controller = makeController(mode: DecodingMode.video);
        controller.start();

        controller.pause();

        expect(cameraCapture.isActive, isFalse);
      });

      test('resume restarts audio capture', () {
        final controller = makeController(mode: DecodingMode.audio);
        controller.start();
        controller.pause();

        controller.resume();

        expect(audioCapture.isActive, isTrue);
      });
    });

    group('clear', () {
      test('clears decoded text and returns to idle', () {
        final controller = makeController();
        controller.updateText('hello');

        controller.clear();

        expect(controller.decodedText, isEmpty);
        expect(controller.status, DecodingStatus.idle);
        expect(controller.isIdle, isTrue);
      });

      test('clear resets audio decoder', () {
        final controller = makeController(mode: DecodingMode.audio);
        controller.start();

        controller.clear();

        expect(audioDecoder.state, DecoderState.scanning);
      });
    });

    group('updateText', () {
      test('updates decoded text', () {
        final controller = makeController();

        controller.updateText('SOS');

        expect(controller.decodedText, 'SOS');
      });

      test('notifies listeners', () {
        final controller = makeController();
        var notified = 0;
        controller.addListener(() => notified++);

        controller.updateText('test');

        expect(notified, 1);
      });
    });

    group('processElements', () {
      test('appends decoded text from elements', () {
        final controller = makeController();
        controller.updateText('HI');

        // E = single dit. on-dit 120ms, then char gap 360ms.
        controller.processElements([
          const DecodedElement(isOn: true, durationMs: 120),
          const DecodedElement(isOn: false, durationMs: 360),
        ]);

        // Should decode "E" and append to "HI"
        expect(controller.decodedText, 'HIE');
      });

      test('notifies listeners', () {
        final controller = makeController();
        var notified = 0;
        controller.addListener(() => notified++);

        controller.processElements([
          const DecodedElement(isOn: true, durationMs: 120),
        ]);

        expect(notified, 1);
      });
    });

    group('checkPermission', () {
      test('returns true for audio mode when permission granted', () async {
        final controller = makeController(mode: DecodingMode.audio);
        final result = await controller.checkPermission();
        expect(result, isTrue);
      });

      test('returns false for audio mode when permission denied', () async {
        audioCapture = FakeAudioCapture(hasPermissionValue: false);
        final controller = makeController(mode: DecodingMode.audio);
        final result = await controller.checkPermission();
        expect(result, isFalse);
      });

      test('returns true for video mode when permission granted', () async {
        final controller = makeController(mode: DecodingMode.video);
        final result = await controller.checkPermission();
        expect(result, isTrue);
      });

      test('returns false for video mode when permission denied', () async {
        cameraCapture = FakeCameraCapture(hasPermissionValue: false);
        final controller = makeController(mode: DecodingMode.video);
        final result = await controller.checkPermission();
        expect(result, isFalse);
      });
    });

    group('isHighFrameRate', () {
      test('returns true for audio mode', () {
        final controller = makeController(mode: DecodingMode.audio);
        expect(controller.isHighFrameRate, isTrue);
      });

      test('returns true for video mode with high-fps camera', () {
        cameraCapture = FakeCameraCapture(isHighFrameRateValue: true);
        final controller = makeController(mode: DecodingMode.video);
        expect(controller.isHighFrameRate, isTrue);
      });

      test('returns false for video mode with low-fps camera', () {
        cameraCapture = FakeCameraCapture(isHighFrameRateValue: false);
        final controller = makeController(mode: DecodingMode.video);
        expect(controller.isHighFrameRate, isFalse);
      });
    });

    group('audio pipeline wiring', () {
      test('audio decoder receives samples from capture', () {
        final elements = <DecodedElement>[];
        audioDecoder.onElement = elements.add;

        final controller = makeController(mode: DecodingMode.audio);
        controller.start();

        // Emit enough noise to fill the noise floor
        final noise = List<double>.filled(256 * 6, 0.0);
        audioCapture.emit(noise);

        expect(audioDecoder.state, DecoderState.scanning);

        controller.pause();
      });
    });

    group('video pipeline wiring', () {
      test('video decoder receives frames from camera', () {
        final controller = makeController(mode: DecodingMode.video);
        controller.start();

        // Emit a few frames — not enough to trigger detection
        for (var i = 0; i < 5; i++) {
          cameraCapture.emit(
            VideoFrame(
              luminance: List<double>.filled(80 * 60, 0.5),
              width: 80,
              height: 60,
              timestampMs: i * 33,
            ),
          );
        }

        // Should still be scanning (uniform brightness → no variance)
        expect(videoDecoder.state, VideoDecoderState.scanning);

        controller.pause();
      });
    });

    group('dispose', () {
      test('stops audio capture', () {
        final controller = makeController(mode: DecodingMode.audio);
        controller.start();

        controller.dispose();

        expect(audioCapture.isActive, isFalse);
      });

      test('stops camera capture', () {
        final controller = makeController(mode: DecodingMode.video);
        controller.start();

        controller.dispose();

        expect(cameraCapture.isActive, isFalse);
      });

      test('sets status to idle', () {
        final controller = makeController();
        controller.start();

        controller.dispose();

        expect(controller.status, DecodingStatus.idle);
      });
    });

    group('notifications', () {
      test('start notifies listeners', () {
        final controller = makeController();
        var notified = 0;
        controller.addListener(() => notified++);

        controller.start();

        expect(notified, 1);
      });

      test('pause notifies listeners', () {
        final controller = makeController();
        controller.start();
        var notified = 0;
        controller.addListener(() => notified++);

        controller.pause();

        expect(notified, 1);
      });

      test('clear notifies listeners', () {
        final controller = makeController();
        var notified = 0;
        controller.addListener(() => notified++);

        controller.clear();

        expect(notified, 1);
      });
    });
  });
}
