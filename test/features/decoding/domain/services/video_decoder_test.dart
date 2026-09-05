import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';

/// Helper to create a [VideoFrame] with a bright source
/// at a given position.
VideoFrame _makeFrame({
  required int timestampMs,
  int sourceX = 40,
  int sourceY = 30,
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
              sourceOn: i.isEven,
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
                sourceOn: i.isEven,
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

      test(
        'ignores a blinking source outside the target area',
        () {
          final dec = VideoDecoder(historySize: 30);

          // A bright blinking dot in the top-left corner —
          // outside the central target area (x 28..52, y 18..42).
          // Nothing else blinks, but the decoder must stay in
          // scanning because the user has not aimed at it.
          for (var i = 0; i < 20; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: 12,
                sourceY: 12,
                sourceOn: i.isEven,
              ),
            );
          }

          expect(dec.state, VideoDecoderState.scanning);
        },
      );

      test('detects full-frame blink', () {
        final dec = VideoDecoder(historySize: 30);

        for (var i = 0; i < 15; i++) {
          dec.processFrame(
            VideoFrame(
              luminance: List<double>.filled(
                80 * 60,
                i.isEven ? 0.9 : 0.1,
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
              sourceOn: i.isEven,
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
              decayFactor: 1,
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
                sourceOn: i.isEven,
              ),
            );
          }
          expect(dec.state, VideoDecoderState.locked);

          // Continue with clear on/off pattern
          for (var i = 20; i < 40; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceOn: i.isEven,
              ),
            );
          }

          // Should have emitted elements
          dec
            ..flush()
            ..flush();
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
              decayFactor: 1,
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
                sourceOn: i.isEven,
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
                sourceOn: i.isEven,
              ),
            );
          }

          expect(
            dec.state,
            VideoDecoderState.locked,
          );
          dec
            ..flush()
            ..flush();
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
              decayFactor: 1,
              minRange: 0.01,
            ),
          );

          final elements = <DecodedElement>[];
          dec.onElement = elements.add;

          // Lock on at position (32, 30) — inside the
          // target area (x 28..52, y 18..42).
          for (var i = 0; i < 20; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: 32,
                sourceY: 30,
                sourceOn: i.isEven,
              ),
            );
          }
          expect(
            dec.state,
            VideoDecoderState.locked,
          );

          // Slide right ~0.5px per frame — stays inside the
          // target area the whole way (32 -> 51).
          for (var i = 20; i < 60; i++) {
            dec.processFrame(
              _makeFrame(
                timestampMs: i * 33,
                sourceX: 32 + (i - 20) ~/ 2,
                sourceY: 30,
                sourceOn: i.isEven,
              ),
            );
          }

          expect(
            dec.state,
            VideoDecoderState.locked,
          );
          dec
            ..flush()
            ..flush();
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
            decayFactor: 1,
            minRange: 0.01,
          ),
        );

        final elements = <DecodedElement>[];
        dec.onElement = elements.add;

        // Lock on at (34, 30) — inside the target area.
        for (var i = 0; i < 20; i++) {
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceX: 34,
              sourceY: 30,
              sourceOn: i.isEven,
            ),
          );
        }
        expect(
          dec.state,
          VideoDecoderState.locked,
        );

        // Slide right slowly + oscillate — stays inside the
        // target area (x 30..51).
        for (var i = 20; i < 60; i++) {
          final drift = (i - 20) ~/ 3;
          final shake = (4 * sin(i * 0.3)).round();
          dec.processFrame(
            _makeFrame(
              timestampMs: i * 33,
              sourceX: 34 + drift + shake,
              sourceY: 30 + shake ~/ 2,
              sourceOn: i.isEven,
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
                sourceOn: i.isEven,
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
              sourceOn: i.isEven,
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
        const frame = VideoFrame(
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
          const frame = VideoFrame(
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

    group('track overlay telemetry', () {
      /// Feeds a blinking source through the decoder and collects
      /// everything sent to onTrackOverlay.
      List<TrackOverlayInfo?> feed(
        VideoDecoder dec,
        List<(int, bool)> segments, {
        int periodMs = 33,
      }) {
        final infos = <TrackOverlayInfo?>[];
        dec.onTrackOverlay = infos.add;
        var t = 0;
        for (final (durationMs, on) in segments) {
          for (final end = t + durationMs; t < end; t += periodMs) {
            dec.processFrame(
              _makeFrame(timestampMs: t, sourceOn: on),
            );
          }
        }
        return infos;
      }

      test('emits nothing before the source is confirmed', () {
        final dec = VideoDecoder();
        // 10 frames: enough to enter confirming, not enough to
        // lock (10 frames of history + 3 confirm frames needed,
        // and only tracking emits overlay telemetry).
        final infos = feed(dec, [
          (150, true),
          (150, false),
        ]);

        expect(infos, isEmpty);
      });

      test(
        'emits normalized region center and size while locked',
        () {
          final dec = VideoDecoder();
          final infos = feed(dec, [
            for (var i = 0; i < 10; i++) (300, i.isEven),
            for (var i = 0; i < 10; i++) (300, i.isEven),
          ]);

          expect(dec.state, VideoDecoderState.locked);
          expect(infos, isNotEmpty);
          for (final info in infos.whereType<TrackOverlayInfo>()) {
            // Source at (40, 30) on an 80x60 frame lands in block
            // (5, 3) of the 8x8 grid; the tracked center is
            // block-quantized, i.e. (44, 28) -> fractions below.
            expect(info.centerX, moreOrLessEquals(44 / 80, epsilon: 0.01));
            expect(info.centerY, moreOrLessEquals(28 / 60, epsilon: 0.01));
            expect(info.regionSizePx, greaterThanOrEqualTo(8));
            expect(info.regionSizePx, lessThanOrEqualTo(32));
          }
        },
      );

      test('nulls the overlay when the signal is lost', () {
        final dec = VideoDecoder();
        final infos = feed(dec, [
          for (var i = 0; i < 12; i++) (300, i.isEven),
          // Steady dark frames: no variance, lock must drop.
          (1200, false),
        ]);

        expect(dec.state, VideoDecoderState.scanning);
        expect(infos.last, isNull);
      });

      test('reset nulls the overlay while locked', () {
        final dec = VideoDecoder();
        feed(dec, [for (var i = 0; i < 12; i++) (300, i.isEven)]);
        expect(dec.state, VideoDecoderState.locked);

        TrackOverlayInfo? last;
        dec.onTrackOverlay = (info) => last = info;
        dec.reset();

        expect(last, isNull);
      });

      test('classifies the live mark: dot first, then dash', () {
        final dec = VideoDecoder();
        final infos = feed(dec, [
          // Lock + establish a ~300ms dit estimate (p25 of marks).
          for (var i = 0; i < 8; i++) (300, i.isEven),
          // A long dash: 1200ms continuous ON.
          (1200, true),
          (300, false),
        ]);

        final duringDash = infos
            .whereType<TrackOverlayInfo>()
            .where((e) => e.signalOn && e.markClassified)
            .toList();

        expect(duringDash, isNotEmpty);
        // Early in the dash the mark can still end as a dit.
        expect(duringDash.first.isDash, isFalse);
        // Once the running duration passes twice the dit estimate,
        // the label must flip to dash.
        expect(duringDash.last.isDash, isTrue);
      });

      test('hides the label before a dit estimate exists', () {
        final dec = VideoDecoder();
        final infos = feed(dec, [
          for (var i = 0; i < 12; i++) (300, i.isEven),
        ]);

        // Before a mark completes, markClassified is false on
        // every ON frame.
        final onInfos = infos
            .whereType<TrackOverlayInfo>()
            .where((e) => e.signalOn)
            .toList();
        expect(onInfos, isNotEmpty);
        expect(
          onInfos.every((e) => e.markClassified),
          isFalse,
        );
      });
    });
  });
}
