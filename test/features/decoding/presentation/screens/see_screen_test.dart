import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/see_screen.dart';

import '../../../../helpers/decoding_fakes.dart';
import '../../../../helpers/fake_feedback_service.dart';
import '../../../../helpers/fake_share_service.dart';

void main() {
  late MorseDecoder morseDecoder;
  late AudioDecoder audioDecoder;
  late FakeAudioCapture audioCapture;
  late VideoDecoder videoDecoder;
  late FakeCameraCapture cameraCapture;
  late FakeFeedbackService feedbackService;
  late FakeShareService shareService;

  setUp(() {
    morseDecoder = MorseDecoder();
    audioDecoder = AudioDecoder();
    audioCapture = FakeAudioCapture();
    videoDecoder = VideoDecoder();
    cameraCapture = FakeCameraCapture(isHighFrameRateValue: true);
    feedbackService = FakeFeedbackService();
    shareService = FakeShareService();

    final getIt = GetIt.instance;
    getIt
      ..registerFactory<DecodingController>(
        () => DecodingController(
          morseDecoder: morseDecoder,
          audioDecoder: audioDecoder,
          audioCapture: audioCapture,
          videoDecoder: videoDecoder,
          cameraCapture: cameraCapture,
        ),
      )
      ..registerSingleton<CameraCaptureImpl>(CameraCaptureImpl())
      ..registerSingleton<FeedbackService>(feedbackService)
      ..registerSingleton<ShareService>(shareService);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SeeScreen(
          themeController: ThemeController(),
          screenTimeoutService: ScreenTimeoutService(),
          displayTimeout: DisplayTimeout.system,
          onDisplayTimeoutChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SeeScreen high-fps camera', () {
    testWidgets('displays Watch header', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Watch'), findsOneWidget);
    });

    testWidgets('displays Start button initially', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('Start button changes to Pause when watching', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('Pause button changes to Resume when paused', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('Clear button is present', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('shows decoded text input field', (tester) async {
      await pumpScreen(tester);
      expect(
        find.text('Decoded text will appear here…'),
        findsOneWidget,
      );
    });

    testWidgets('shows camera preview placeholder when not initialized', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Camera preview'), findsOneWidget);
    });

    testWidgets('no reticle before the camera initializes', (
      tester,
    ) async {
      await pumpScreen(tester);
      // In the test harness no real camera is available, so the
      // placeholder shows and the reticle must NOT be painted —
      // it belongs to the live preview only.
      expect(find.byKey(const Key('targeting-reticle')), findsNothing);
    });

    testWidgets('shows Idle status when not started', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('shows Watching status when active', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Watching'), findsOneWidget);
    });

    testWidgets('shows Paused status when paused', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsOneWidget);
    });
  });

  group('SeeScreen WPM display', () {
    testWidgets('does not show WPM when idle', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('WPM'), findsNothing);
    });
  });

  group('SeeScreen share/clipboard', () {
    testWidgets('Copy/Share are disabled when no decoded text', (
      tester,
    ) async {
      await pumpScreen(tester);
      // The buttons are always visible in the bottom row but
      // inert until there is text to act on.
      final copy = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Copy'),
      );
      final share = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Share'),
      );
      expect(copy.onPressed, isNull);
      expect(share.onPressed, isNull);
    });

    testWidgets('Copy/Share enable once text is decoded', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      cameraCapture.emit(
        VideoFrame(
          luminance: List<double>.filled(80 * 60, 0.5),
          width: 80,
          height: 60,
          timestampMs: 0,
        ),
      );
      await tester.pumpAndSettle();

      // Type text so the buttons have something to act on.
      await tester.enterText(
        find.byType(TextField),
        'HELLO',
      );
      await tester.pumpAndSettle();

      final copy = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Copy'),
      );
      expect(copy.onPressed, isNotNull);
    });
  });

  group('TargetReticlePainter', () {
    test('paints without throwing and reports repaint on color change', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = Size.square(120);

      TargetReticlePainter(color: Colors.white).paint(canvas, size);

      final picture = recorder.endRecording();
      expect(picture, isNotNull);

      final painter = TargetReticlePainter(color: Colors.white);
      expect(
        painter.shouldRepaint(TargetReticlePainter(color: Colors.green)),
        isTrue,
      );
      expect(
        painter.shouldRepaint(TargetReticlePainter(color: Colors.white)),
        isFalse,
      );
    });
  });

  group('SeeScreen haptic feedback', () {
    testWidgets('triggers medium impact on Start', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(feedbackService.calls, contains('medium'));
    });

    testWidgets('triggers light impact on Pause', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      feedbackService.reset();

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(feedbackService.calls, contains('light'));
    });
  });

  group('TrackedSpotPainter', () {
    const canvasSize = Size(160, 120);

    TrackOverlayInfo info({int regionSizePx = 8}) => TrackOverlayInfo(
      centerX: 0.5,
      centerY: 0.5,
      regionSizePx: regionSizePx,
      signalOn: true,
      markClassified: true,
      isDash: false,
    );

    test('maps fraction center onto the preview canvas', () {
      final center = TrackedSpotPainter.centerOf(info(), canvasSize);

      expect(center.dx, closeTo(80, 0.001));
      expect(center.dy, closeTo(60, 0.001));
    });

    test('circle diameter is double the detected spot diameter', () {
      // 8 processing px on an 80-px-wide frame scale 2x onto a
      // 160-px-wide canvas: spot diameter 16, circle radius 16
      // (i.e. diameter 32 = 2 x 16).
      expect(
        TrackedSpotPainter.spotDiameterOf(info(), canvasSize),
        closeTo(16, 0.001),
      );
      expect(
        TrackedSpotPainter.radiusOf(info(), canvasSize),
        closeTo(16, 0.001),
      );
    });

    testWidgets('paints without throwing for on and off marks', (tester) async {
      final painter = TrackedSpotPainter(info: info());
      final painterOff = TrackedSpotPainter(
        info: const TrackOverlayInfo(
          centerX: 0.5,
          centerY: 0.5,
          regionSizePx: 8,
          signalOn: false,
          markClassified: false,
          isDash: false,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 160,
            height: 120,
            child: CustomPaint(
              painter: painter,
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 160,
            height: 120,
            child: CustomPaint(
              painter: painterOff,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
