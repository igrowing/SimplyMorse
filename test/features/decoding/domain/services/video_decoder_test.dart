import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';

/// Helper to create a [VideoFrame] with a bright source
/// at a given position.
VideoFrame _makeFrame({
  required int timestampMs,
  int sourceX = 12,
  int sourceY = 12,
  int sourceSize = 8,
  bool sourceOn = true,
  double bgBrightness = 0.1,
  int width = 80,
  int height = 60,
}) {
  final luminance = List<double>.filled(
    width * height,
    bgBrightness,
  );

  if (sourceOn) {
    final half = sourceSize ~/ 2;
    for (var y = max(0, sourceY - half); y < min(height, sourceY + half); y++) {
      for (
        var x = max(0, sourceX - half);
        x < min(width, sourceX + half);
        x++
      ) {
        luminance[y * width + x] = 0.9;
      }
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
              sourceOn: i % 2 == 0,
            ),
          );
        }
        expect(dec.state, VideoDecoderState.scanning);
      });

      test(
        'transitions to confirming when a blinking '
        'source is detected',
        () {
          final dec = VideoDecoder(historySize: 30);

          for (var i = 0; i < 15; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: i % 2 == 0,
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
            VideoFrame(
              luminance: List<double>.filled(
                80 * 60,
                i % 2 == 0 ? 0.9 : 0.1,
              ),
              width: 80,
              height: 60,
              timestampMs: i * 33,
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
        );

        for (var i = 0; i < 20; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceOn: i % 2 == 0,
            ),
          );
        }

        expect(dec.state, VideoDecoderState.locked);
      });
    });

    group('tracking with motion compensation', () {
      test(
        'tracks a static source and emits elements',
        () {
          final dec = VideoDecoder(
            historySize: 30,
            confirmFrames: 3,
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

          // Lock on
          for (var i = 0; i < 20; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: i % 2 == 0,
              ),
            );
          }
          expect(dec.state, VideoDecoderState.locked);

          // Continue with clear on/off pattern
          for (var i = 20; i < 40; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: i % 2 == 0,
              ),
            );
          }

          // Should have emitted elements
          dec.flush();
          dec.flush();
        expect(elements, isNotEmpty);
        },
      );

      test(
        'tracks a shaking source (oscillating position)',
        () {
          final dec = VideoDecoder(
            historySize: 30,
            confirmFrames: 3,
            rescanIntervalMs: 10000,
            searchRadius: 3,
            threshold: BrightnessThreshold(
              onFactor: 0.6,
              offFactor: 0.4,
              decayFactor: 1.0,
              minRange: 0.01,
            ),
          );

          final elements = <DecodedElement>[];
          dec.onElement = elements.add;

          // Phase 1: lock on with shaking
          for (var i = 0; i < 25; i++) {
            final shakeX = 40 + (5 * sin(i * 0.5)).round();
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: shakeX,
                sourceOn: i % 2 == 0,
              ),
            );
          }

          expect(dec.state, VideoDecoderState.locked);

          // Phase 2: continue shaking
          for (var i = 25; i < 50; i++) {
            final shakeX = 40 + (5 * sin(i * 0.5)).round();
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: shakeX,
                sourceOn: i % 2 == 0,
              ),
            );
          }

          expect(
            dec.state,
            VideoDecoderState.locked,
          );
          dec.flush();
          dec.flush();
        expect(elements, isNotEmpty);
        },
      );

      test(
        'tracks a sliding source (steady drift)',
        () {
          final dec = VideoDecoder(
            historySize: 30,
            confirmFrames: 3,
            rescanIntervalMs: 10000,
            searchRadius: 3,
            threshold: BrightnessThreshold(
              onFactor: 0.6,
              offFactor: 0.4,
              decayFactor: 1.0,
              minRange: 0.01,
            ),
          );

          final elements = <DecodedElement>[];
          dec.onElement = elements.add;

          // Lock on at position (12, 12)
          for (var i = 0; i < 20; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: 12,
                sourceY: 12,
                sourceOn: i % 2 == 0,
              ),
            );
          }
          expect(
            dec.state,
            VideoDecoderState.locked,
          );

          // Slide right 1px per frame
          for (var i = 20; i < 60; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: 12 + (i - 20),
                sourceY: 12,
                sourceOn: i % 2 == 0,
              ),
            );
          }

          expect(
            dec.state,
            VideoDecoderState.locked,
          );
          dec.flush();
          dec.flush();
        expect(elements, isNotEmpty);
        },
      );

      test('tracks combined shake + slide', () {
        final dec = VideoDecoder(
          historySize: 30,
          confirmFrames: 3,
          rescanIntervalMs: 10000,
          searchRadius: 4,
          threshold: BrightnessThreshold(
            onFactor: 0.6,
            offFactor: 0.4,
            decayFactor: 1.0,
            minRange: 0.01,
          ),
        );

        final elements = <DecodedElement>[];
        dec.onElement = elements.add;

        // Lock on
        for (var i = 0; i < 20; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceX: 20,
              sourceY: 20,
              sourceOn: i % 2 == 0,
            ),
          );
        }
        expect(
          dec.state,
          VideoDecoderState.locked,
        );

        // Slide right + oscillate
        for (var i = 20; i < 60; i++) {
          final drift = i - 20;
          final shake = (4 * sin(i * 0.3)).round();
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceX: 20 + drift + shake,
              sourceY: 20 + shake ~/ 2,
              sourceOn: i % 2 == 0,
            ),
          );
        }

        expect(
          dec.state,
          VideoDecoderState.locked,
        );
        dec.flush();
        expect(elements, isNotEmpty);
      });

      test(
        'loses signal when source disappears',
        () {
          final dec = VideoDecoder(
            historySize: 15,
            confirmFrames: 3,
            lostFrameLimit: 5,
          );

          // Lock on
          for (var i = 0; i < 20; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: i % 2 == 0,
              ),
            );
          }
          expect(
            dec.state,
            VideoDecoderState.locked,
          );

          // Source disappears — feed enough dark
          // frames to flush history (15) + trigger
          // signal loss (5 more)
          for (var i = 20; i < 50; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: false,
              ),
            );
          }

          expect(
            dec.state,
            VideoDecoderState.scanning,
          );
        },
      );
    });

    group('reset', () {
      test('returns to scanning state', () {
        final dec = VideoDecoder();

        for (var i = 0; i < 15; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceOn: i % 2 == 0,
            ),
          );
        }

        dec.reset();
        expect(
          dec.state,
          VideoDecoderState.scanning,
        );
      });
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
        },
      );
    });
  });
}
