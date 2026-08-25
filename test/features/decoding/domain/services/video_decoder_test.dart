import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';

/// Helper to create a [VideoFrame] with a given brightness
/// pattern.
VideoFrame _makeFrame({
  required int timestampMs,
  required double brightness,
  double regionBrightness = 0,
  int regionX = 0,
  int regionY = 0,
  int regionW = 8,
  int regionH = 8,
  int width = 24,
  int height = 24,
}) {
  final luminance = List<double>.filled(
    width * height,
    brightness,
  );

  for (var y = regionY; y < min(regionY + regionH, height); y++) {
    for (var x = regionX; x < min(regionX + regionW, width); x++) {
      luminance[y * width + x] = regionBrightness;
    }
  }

  return VideoFrame(
    luminance: luminance,
    width: width,
    height: height,
    timestampMs: timestampMs,
  );
}

void main() {
  group('VideoDecoder', () {
    group('scanning', () {
      test('stays in scanning with insufficient frames', () {
        final dec = VideoDecoder(historySize: 30);
        for (var i = 0; i < 5; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              brightness: 0.5,
              regionBrightness: 0.9,
            ),
          );
        }
        expect(dec.state, VideoDecoderState.scanning);
      });

      test(
        'transitions to confirming when a blinking '
        'region is detected',
        () {
          final dec = VideoDecoder(historySize: 30);

          for (var i = 0; i < 15; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                brightness: 0.1,
                regionBrightness: i % 2 == 0 ? 0.9 : 0.1,
                regionX: 8,
                regionY: 8,
              ),
            );
          }

          expect(
            dec.state,
            anyOf(
              VideoDecoderState.confirming,
              VideoDecoderState.locked,
            ),
          );
        },
      );

      test('detects full-frame blink', () {
        final dec = VideoDecoder(historySize: 30);

        for (var i = 0; i < 15; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              brightness: i % 2 == 0 ? 0.9 : 0.1,
            ),
          );
        }

        expect(
          dec.state,
          isNot(VideoDecoderState.scanning),
        );
      });
    });

    group('confirming → locked', () {
      test('locks after enough confirm frames', () {
        final dec = VideoDecoder(
          historySize: 30,
          confirmFrames: 3,
          blockSize: 8,
        );

        for (var i = 0; i < 20; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              brightness: 0.1,
              regionBrightness: i % 2 == 0 ? 0.9 : 0.1,
              regionX: 8,
              regionY: 8,
            ),
          );
        }

        expect(
          dec.state,
          VideoDecoderState.locked,
        );
      });

      test('falls back to scanning if region disappears', () {
        final dec = VideoDecoder(
          historySize: 15,
          confirmFrames: 3,
          blockSize: 8,
          rescanIntervalMs: 200,
        );

        // Phase 1: lock on blinking region
        for (var i = 0; i < 20; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              brightness: 0.1,
              regionBrightness: i % 2 == 0 ? 0.9 : 0.1,
              regionX: 8,
              regionY: 8,
            ),
          );
        }
        expect(dec.state, VideoDecoderState.locked);

        // Phase 2: feed uniform frames with timestamps
        // past the rescan interval. The history
        // (size 15) will be fully replaced by uniform
        // frames after 15 more frames, at which point
        // the variance drops to 0 and the re-scan
        // unlocks.
        for (var i = 0; i < 25; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: 700 + i * 33,
              brightness: 0.5,
              regionBrightness: 0.5,
              regionX: 8,
              regionY: 8,
            ),
          );
        }

        expect(
          dec.state,
          anyOf(
            VideoDecoderState.scanning,
            VideoDecoderState.confirming,
          ),
        );
      });
    });

    group('tracking', () {
      test('emits elements on brightness transitions', () {
        final dec = VideoDecoder(
          historySize: 30,
          confirmFrames: 2,
          blockSize: 8,
          rescanIntervalMs: 10000,
          threshold: BrightnessThreshold(
            onFactor: 0.6,
            offFactor: 0.4,
            decayFactor: 1.0,
            minRange: 0.01,
          ),
        );

        final elements = <DecodedElement>[];
        dec.onElement = elements.add;

        for (var i = 0; i < 15; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              brightness: 0.1,
              regionBrightness: i % 2 == 0 ? 0.9 : 0.1,
              regionX: 8,
              regionY: 8,
            ),
          );
        }

        if (dec.state == VideoDecoderState.locked) {
          dec.processFrame(
            _makeFrame(
              timestampMs: 500,
              brightness: 0.1,
              regionBrightness: 0.9,
              regionX: 8,
              regionY: 8,
            ),
          );
          dec.processFrame(
            _makeFrame(
              timestampMs: 600,
              brightness: 0.1,
              regionBrightness: 0.1,
              regionX: 8,
              regionY: 8,
            ),
          );

          expect(elements, isNotEmpty);
        }
      });

      test(
        'reset returns to scanning state',
        () {
          final dec = VideoDecoder();

          for (var i = 0; i < 15; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                brightness: 0.1,
                regionBrightness: i % 2 == 0 ? 0.9 : 0.1,
                regionX: 8,
                regionY: 8,
              ),
            );
          }

          dec.reset();
          expect(
            dec.state,
            VideoDecoderState.scanning,
          );
        },
      );
    });

    group('VideoFrame', () {
      test('meanLuminance computes average', () {
        final frame = VideoFrame(
          luminance: [0.0, 0.5, 1.0, 0.5],
          width: 2,
          height: 2,
          timestampMs: 0,
        );
        expect(
          frame.meanLuminance(),
          closeTo(0.5, 0.001),
        );
      });

      test(
        'meanLuminance on empty frame returns 0',
        () {
          final frame = VideoFrame(
            luminance: [],
            width: 0,
            height: 0,
            timestampMs: 0,
          );
          expect(frame.meanLuminance(), 0);
        },
      );

      test(
        'regionMeanLuminance computes sub-region average',
        () {
          final frame = VideoFrame(
            luminance: [
              0.0,
              0.0,
              1.0,
              1.0,
              0.0,
              0.0,
              1.0,
              1.0,
              0.0,
              0.0,
              1.0,
              1.0,
              0.0,
              0.0,
              1.0,
              1.0,
            ],
            width: 4,
            height: 4,
            timestampMs: 0,
          );

          expect(
            frame.regionMeanLuminance(0, 0, 2, 2),
            closeTo(0.0, 0.001),
          );
          expect(
            frame.regionMeanLuminance(2, 2, 2, 2),
            closeTo(1.0, 0.001),
          );
          expect(
            frame.regionMeanLuminance(0, 0, 4, 4),
            closeTo(0.5, 0.001),
          );
        },
      );

      test(
        'regionMeanLuminance handles out-of-bounds',
        () {
          final frame = VideoFrame(
            luminance: [0.5, 0.5, 0.5, 0.5],
            width: 2,
            height: 2,
            timestampMs: 0,
          );
          expect(
            frame.regionMeanLuminance(1, 1, 5, 5),
            closeTo(0.5, 0.001),
          );
        },
      );
    });
  });
}
