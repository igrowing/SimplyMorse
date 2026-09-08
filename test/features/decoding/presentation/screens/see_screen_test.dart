import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/data/video_debug_logger.dart';
import 'package:simply_morse/features/decoding/domain/models/track_overlay_info.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/see_screen.dart';

import '../../../../helpers/decoding_fakes.dart';
import '../../../../helpers/fake_camera_platform.dart';
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

  /// Pumps SeeScreen pushed on top of a dummy home route, so
  /// `Navigator.canPop()` is true inside it — [pumpScreen] makes it
  /// the app's only (home) route, where nothing can be popped, so
  /// it can't exercise the back button at all.
  Future<void> pumpScreenWithBackStack(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeeScreen(
                      themeController: ThemeController(),
                      screenTimeoutService: ScreenTimeoutService(),
                      displayTimeout: DisplayTimeout.system,
                      onDisplayTimeoutChanged: (_) {},
                    ),
                  ),
                ),
                child: const Text('Open Watch'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open Watch'));
    await tester.pumpAndSettle();
  }

  group('SeeScreen high-fps camera', () {
    testWidgets('displays Watch header', (tester) async {
      // The AppBar (and its title) is portrait-only — landscape
      // drops it for a small back button instead, to reclaim
      // vertical space (see 'SeeScreen landscape layout' below).
      tester
        ..view.physicalSize = const Size(400, 800)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

    testWidgets('bottom actions are split into two rows', (tester) async {
      // This 2x2 grid is the portrait layout specifically (the
      // landscape layout stacks all four vertically in a side
      // column instead — see 'action buttons stack vertically in
      // landscape' below) — force a portrait shape rather than
      // relying on the default test surface.
      tester
        ..view.physicalSize = const Size(400, 800)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(tester);

      // First row: Start/Pause + Clear. Second row: Copy + Share,
      // strictly below the first row.
      final startRect = tester.getRect(find.text('Start'));
      final clearRect = tester.getRect(find.text('Clear'));
      final copyRect = tester.getRect(find.text('Copy'));
      final shareRect = tester.getRect(find.text('Share'));

      expect(clearRect.top, closeTo(startRect.top, 1));
      expect(copyRect.top, greaterThan(startRect.bottom));
      expect(shareRect.top, closeTo(copyRect.top, 1));
    });

    testWidgets('shows decoded text input field', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Decoded text will appear here…'), findsOneWidget);
    });

    testWidgets('shows camera preview placeholder when not initialized', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Camera preview'), findsOneWidget);
    });

    testWidgets('no reticle before the camera initializes', (tester) async {
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
    testWidgets('Copy/Share are disabled when no decoded text', (tester) async {
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
      await tester.enterText(find.byType(TextField), 'HELLO');
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

    test('maps fraction center onto the preview canvas (landscape)', () {
      final center = TrackedSpotPainter.centerOf(
        info(),
        canvasSize,
        isPortrait: false,
      );

      expect(center.dx, closeTo(80, 0.001));
      expect(center.dy, closeTo(60, 0.001));
    });

    test(
      'circle diameter is double the detected spot diameter (landscape)',
      () {
        // 8 processing px on an 80-px-wide frame scale 2x onto a
        // 160-px-wide canvas: spot diameter 16, circle radius 16
        // (i.e. diameter 32 = 2 x 16).
        expect(
          TrackedSpotPainter.spotDiameterOf(
            info(),
            canvasSize,
            isPortrait: false,
          ),
          closeTo(16, 0.001),
        );
        expect(
          TrackedSpotPainter.radiusOf(info(), canvasSize, isPortrait: false),
          closeTo(16, 0.001),
        );
      },
    );

    group('rotation between the raw processing buffer and the canvas', () {
      // Off-center fractions so a rotation actually moves the
      // point — (0.5, 0.5) is a fixed point of the rotation and
      // can't distinguish "rotated" from "not rotated".
      const offCenterInfo = TrackOverlayInfo(
        centerX: 0.9,
        centerY: 0.1,
        regionSizePx: 8,
        signalOn: true,
        markClassified: true,
        isDash: false,
      );

      test('landscape: buffer fraction maps straight onto the canvas', () {
        final center = TrackedSpotPainter.centerOf(
          offCenterInfo,
          canvasSize,
          isPortrait: false,
        );
        expect(center.dx, closeTo(0.9 * canvasSize.width, 0.001));
        expect(center.dy, closeTo(0.1 * canvasSize.height, 0.001));
      });

      test('portrait: buffer fraction is rotated 90° before mapping onto the '
          'canvas', () {
        // A 90°-clockwise rotation sends buffer fraction (fx, fy)
        // to canvas fraction (1 - fy, fx) — see
        // frameFractionToDisplayFraction's doc comment. For
        // (0.9, 0.1) that is (0.9, 0.9): the point sits near the
        // buffer's RIGHT edge, which becomes the canvas's BOTTOM
        // edge after the rotation — not near the top, as a plain
        // (unrotated) mapping would place it.
        const portraitCanvas = Size(120, 160);
        final center = TrackedSpotPainter.centerOf(
          offCenterInfo,
          portraitCanvas,
          isPortrait: true,
        );
        expect(center.dx, closeTo(0.9 * portraitCanvas.width, 0.001));
        expect(center.dy, closeTo(0.9 * portraitCanvas.height, 0.001));
      });

      test("portrait: spot diameter scales off the buffer's HEIGHT axis", () {
        // In portrait the canvas's width axis corresponds to the
        // buffer's 60px-tall axis (rotation swaps the axes), not
        // its 80px-wide axis — 8 processing px on that 60px axis,
        // scaled onto a 120-px-wide canvas: 8/60 * 120 = 16.
        const portraitCanvas = Size(120, 160);
        expect(
          TrackedSpotPainter.spotDiameterOf(
            offCenterInfo,
            portraitCanvas,
            isPortrait: true,
          ),
          closeTo(16, 0.001),
        );
      });
    });

    testWidgets('paints without throwing for on and off marks', (tester) async {
      final painter = TrackedSpotPainter(info: info(), isPortrait: false);
      final painterOff = TrackedSpotPainter(
        isPortrait: false,
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
            child: CustomPaint(painter: painter),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 160,
            height: 120,
            child: CustomPaint(painter: painterOff),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('SeeScreen live preview geometry (regression)', () {
    // Originally reproduced a stretch bug: the preview box that
    // wraps CameraPreview was sized from
    // `camController.value.aspectRatio` directly (see_screen.dart
    // ~L221-222 at the time), which is always the SENSOR (landscape)
    // aspect ratio. In portrait that box was never rotated to
    // match, so fitting it onto a portrait screen blew the picture
    // up and distorted its proportions.
    //
    // The screen has since moved from cover-fit (fills the screen,
    // crops the excess) to contain-fit / letterbox (the full frame
    // always visible, black bars fill the rest) — the tests below
    // cover both: the aspect ratio staying correct (unaffected by
    // which fit mode is active) and the letterbox itself (no crop,
    // bars on the axis with room to spare).
    late CameraPlatform originalCameraPlatform;

    setUp(() {
      originalCameraPlatform = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform(
        // Sensor reports a 16:9 landscape buffer, as a typical
        // ResolutionPreset.low back camera does.
        previewSize: const Size(1280, 720),
      );
    });

    tearDown(() {
      CameraPlatform.instance = originalCameraPlatform;
    });

    testWidgets('keeps the correct aspect ratio in portrait (no stretch)', (
      tester,
    ) async {
      tester
        ..view.physicalSize = const Size(400, 800)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();
      expect(camImpl.controller!.value.isInitialized, isTrue);

      await pumpScreen(tester);

      final previewRect = tester.getRect(find.byType(CameraPreview));

      // The frame's correct display aspect in portrait is
      // 720/1280 = 0.5625 (width/height) — the sensor's aspect
      // inverted for portrait — not the raw sensor 1280/720. This
      // must hold under either fit mode, so derive the expected
      // width from the *measured* height rather than hardcoding
      // either dimension.
      final expectedWidth = previewRect.height * (720 / 1280);
      expect(previewRect.width, closeTo(expectedWidth, 5));
    });

    testWidgets('letterboxes a portrait screen — bars top/bottom, no crop', (
      tester,
    ) async {
      tester
        ..view.physicalSize = const Size(400, 800)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();

      await pumpScreen(tester);

      final screenRect = tester.getRect(find.byType(MaterialApp));
      final previewRect = tester.getRect(find.byType(CameraPreview));

      // Contain-fit: the frame is never larger than the screen on
      // either axis (no crop) ...
      expect(previewRect.width, lessThanOrEqualTo(screenRect.width + 0.5));
      expect(previewRect.height, lessThanOrEqualTo(screenRect.height + 0.5));
      // ... and in portrait, a 16:9 sensor is proportionally
      // wider than the screen, so it's constrained by width —
      // the full screen width is used, with bars above/below.
      expect(previewRect.width, closeTo(screenRect.width, 1));
      expect(previewRect.height, lessThan(screenRect.height));
    });

    testWidgets('letterboxes a landscape screen — bars left/right, no crop', (
      tester,
    ) async {
      tester
        ..view.physicalSize = const Size(800, 400)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();

      await pumpScreen(tester);

      final screenRect = tester.getRect(find.byType(MaterialApp));
      final previewRect = tester.getRect(find.byType(CameraPreview));

      // No crop on either axis ...
      expect(previewRect.width, lessThanOrEqualTo(screenRect.width + 0.5));
      expect(previewRect.height, lessThanOrEqualTo(screenRect.height + 0.5));
      // ... and here the body (screen minus the app bar) is
      // proportionally wider than a 16:9 sensor, so contain-fit
      // is constrained by height, leaving the frame narrower than
      // the screen — bars on the sides. Under the old cover-fit
      // this would instead stretch to the full screen width
      // (cropping the excess height), so this is the assertion
      // that actually distinguishes contain from cover.
      expect(previewRect.width, lessThan(screenRect.width * 0.95));
      // Correct, unswapped aspect for landscape (no bar-induced
      // distortion of the frame's own shape).
      expect(previewRect.width / previewRect.height, closeTo(1280 / 720, 0.02));
    });

    testWidgets(
      'reticle matches the portrait-corrected target area, not the raw '
      'sensor one',
      (tester) async {
        // Reproduces a second bug with the same root cause: the
        // separate `scaledW`/`reticleEdgeGap` computation in
        // _buildBody (see_screen.dart ~L190, used to size the
        // reticle and to gate whether the decoded-text overlay has
        // room to show) also read the raw, uninverted
        // camController.value.aspectRatio.
        tester
          ..view.physicalSize = const Size(400, 800)
          ..view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final camImpl = GetIt.instance<CameraCaptureImpl>();
        await camImpl.initialize();

        await pumpScreen(tester);

        // Ground truth: the body height, which is driven by the
        // screen (not the aspect bug — cover-fit is height-driven
        // here regardless of which aspect is used, so this stays a
        // safe anchor even while the width computation is broken),
        // combined with the KNOWN correct display aspect for a
        // 1280x720 sensor in portrait (720/1280 = 0.5625 — the
        // sensor aspect inverted, not the raw 1280/720). Using the
        // preview's own measured WIDTH here instead would make this
        // test tautological: the reticle and the preview box share
        // the same (buggy or fixed) aspect computation, so they'd
        // always agree with each other even when both are wrong.
        final previewHeight = tester.getSize(find.byType(CameraPreview)).height;
        const correctDisplayAspect = 720 / 1280;
        final expectedSide =
            VideoDecoder.reticleFraction *
            min(previewHeight * correctDisplayAspect, previewHeight);

        final reticleSize = tester.getSize(
          find.byKey(const Key('targeting-reticle')),
        );
        expect(reticleSize.width, closeTo(expectedSide, 1));
        expect(reticleSize.height, closeTo(expectedSide, 1));
      },
    );
  });

  group('SeeScreen status bar wrapping', () {
    late CameraPlatform originalCameraPlatform;

    setUp(() {
      originalCameraPlatform = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform(
        previewSize: const Size(1280, 720),
      );
    });

    tearDown(() {
      CameraPlatform.instance = originalCameraPlatform;
    });

    testWidgets('splits into two lines when the state + details do not fit', (
      tester,
    ) async {
      // Narrow enough that "Idle · 1280×720 · 120 FPS" cannot
      // fit one line alongside the status icon and the pill's own
      // padding. This is a portrait shape (600 > 130), so it hits
      // the portrait layout's status bar.
      tester
        ..view.physicalSize = const Size(130, 600)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();

      await pumpScreen(tester);

      // Split into a state line and a details line, each its own
      // Text widget — not silently ellipsized away as one line.
      // The negotiated capture rate (120, the first of
      // CameraCaptureImpl's preferred rates FakeCameraPlatform
      // always grants) shows alongside the resolution even while
      // idle — see the status bar's doc comment.
      expect(find.text('Idle'), findsOneWidget);
      expect(find.textContaining('1280×720'), findsOneWidget);
      expect(find.textContaining('120 FPS'), findsOneWidget);
      // The combined single-line form must NOT be present.
      expect(find.textContaining('Idle ·'), findsNothing);
    });

    testWidgets('stays on one line on a wide enough screen', (tester) async {
      // Landscape shape (800 > 600) — hits the landscape layout,
      // which still keeps the status bar at the top (see
      // _buildLandscapeBody), and it's wide enough that the same
      // text needn't wrap there either.
      tester
        ..view.physicalSize = const Size(800, 600)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();

      await pumpScreen(tester);

      expect(
        find.text('Idle · 1280×720 · 120 FPS · up to 36 WPM'),
        findsOneWidget,
      );
    });
  });

  group('SeeScreen landscape layout', () {
    // Reproduces the reported bug: with a real (initialized)
    // camera, the portrait overlay design's decoded-text box is
    // gated on leftover vertical space above the reticle
    // (`reticleEdgeGap > 120`), which can shrink to nothing once
    // the live preview is letterboxed rather than full-bleed — the
    // box then never showed at all in landscape. The landscape
    // layout instead gives it (and the action buttons) dedicated
    // panels that don't depend on that heuristic.
    late CameraPlatform originalCameraPlatform;

    setUp(() {
      originalCameraPlatform = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform(
        previewSize: const Size(1280, 720),
      );
    });

    tearDown(() {
      CameraPlatform.instance = originalCameraPlatform;
    });

    Future<void> pumpLandscape(
      WidgetTester tester, {
      bool withBackStack = false,
    }) async {
      tester
        ..view.physicalSize = const Size(800, 400)
        ..view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final camImpl = GetIt.instance<CameraCaptureImpl>();
      await camImpl.initialize();

      if (withBackStack) {
        await pumpScreenWithBackStack(tester);
      } else {
        await pumpScreen(tester);
      }
    }

    testWidgets('decoded text box is visible (not gated away)', (tester) async {
      await pumpLandscape(tester);
      expect(find.text('Decoded text will appear here…'), findsOneWidget);
    });

    testWidgets('decoded text box sits on the left of the screen', (
      tester,
    ) async {
      await pumpLandscape(tester);

      final screenRect = tester.getRect(find.byType(MaterialApp));
      final textFieldRect = tester.getRect(find.byType(TextField));

      expect(textFieldRect.left, lessThan(screenRect.width * 0.35));
      expect(textFieldRect.right, lessThan(screenRect.width * 0.5));
    });

    testWidgets('action buttons form a vertical stack on the right', (
      tester,
    ) async {
      await pumpLandscape(tester);

      final screenRect = tester.getRect(find.byType(MaterialApp));
      final startRect = tester.getRect(find.text('Start'));
      final clearRect = tester.getRect(find.text('Clear'));
      final copyRect = tester.getRect(find.text('Copy'));
      final shareRect = tester.getRect(find.text('Share'));

      // On the right of the screen ...
      for (final r in [startRect, clearRect, copyRect, shareRect]) {
        expect(r.left, greaterThan(screenRect.width * 0.6));
      }
      // ... stacked vertically, in order, one per row (each
      // button's row strictly below the previous one) — not
      // paired up two-per-row the way the portrait layout does.
      expect(clearRect.top, greaterThan(startRect.bottom));
      expect(copyRect.top, greaterThan(clearRect.bottom));
      expect(shareRect.top, greaterThan(copyRect.bottom));
    });

    testWidgets('status bar stays near the top', (tester) async {
      await pumpLandscape(tester);

      final screenRect = tester.getRect(find.byType(MaterialApp));
      final statusRect = tester.getRect(find.textContaining('Idle'));

      expect(statusRect.top, lessThan(screenRect.height * 0.25));
    });

    testWidgets('has no AppBar (title text is gone)', (tester) async {
      await pumpLandscape(tester);
      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Watch'), findsNothing);
    });

    testWidgets(
      'shows a back button in the upper-left corner when it can pop',
      (tester) async {
        await pumpLandscape(tester, withBackStack: true);

        final screenRect = tester.getRect(find.byType(MaterialApp));
        final backButtonRect = tester.getRect(find.byIcon(Icons.arrow_back));

        expect(backButtonRect.left, lessThan(screenRect.width * 0.15));
        expect(backButtonRect.top, lessThan(screenRect.height * 0.25));
      },
    );

    testWidgets('back button pops the route', (tester) async {
      await pumpLandscape(tester, withBackStack: true);
      expect(find.text('Open Watch'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Open Watch'), findsOneWidget);
    });

    testWidgets('no back button when there is nothing to pop to', (
      tester,
    ) async {
      // pumpScreen (not pumpScreenWithBackStack) makes SeeScreen
      // the app's only route.
      await pumpLandscape(tester);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });

  group('SeeScreen video debug log (TEMP DEBUG)', () {
    // The log file lives in getApplicationDocumentsDirectory(),
    // which on a real device is app-private internal storage no
    // Files app can browse — showing just the path (the original
    // approach) left the user with no way to actually retrieve it.
    // Sharing the file directly sidesteps needing filesystem access
    // at all.
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return Directory.systemTemp.path;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    /// Re-registers DecodingController with a real, enabled
    /// VideoDebugLogger — the default registration in the outer
    /// setUp above has none, matching how most tests don't need it.
    Future<void> enableVideoDebugLogging() async {
      await GetIt.instance.unregister<DecodingController>();
      GetIt.instance.registerFactory<DecodingController>(
        () => DecodingController(
          morseDecoder: morseDecoder,
          audioDecoder: audioDecoder,
          audioCapture: audioCapture,
          videoDecoder: videoDecoder,
          cameraCapture: cameraCapture,
          videoDebugLogger: VideoDebugLogger(enabled: true),
        ),
      );
    }

    testWidgets(
      'offers to share the log file on Start, instead of just a path',
      (tester) async {
        await enableVideoDebugLogging();
        await pumpScreen(tester);

        await tester.ensureVisible(find.text('Start'));
        await tester.tap(find.text('Start'));
        // The SnackBar appears after a short delay (see
        // _onStartPressed) while VideoDebugLogger.start() resolves
        // getApplicationDocumentsDirectory() — pump through it
        // rather than settling immediately.
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('Video debug log ready'), findsOneWidget);
        // Not find.text('Share') — the bottom action bar already
        // has its own "Share" button for the decoded text.
        expect(find.byType(SnackBarAction), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SnackBarAction),
            matching: find.text('Share'),
          ),
          findsOneWidget,
        );
        // The SnackBarAction must not be a dead end: it needs an
        // onPressed to actually do the sharing.
        final action = tester.widget<SnackBarAction>(
          find.byType(SnackBarAction),
        );
        expect(action.onPressed, isNotNull);
      },
    );
  });
}
