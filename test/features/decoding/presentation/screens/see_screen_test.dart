import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
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
      expect(find.text('Decoded text'), findsOneWidget);
    });

    testWidgets('shows camera preview placeholder when not initialized', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Camera preview'), findsOneWidget);
    });

    testWidgets('shows SCANNING indicator when watching', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('SCANNING'), findsOneWidget);
    });

    testWidgets('does not show SCANNING indicator when idle', (tester) async {
      await pumpScreen(tester);
      expect(find.text('SCANNING'), findsNothing);
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
    testWidgets('does not show Copy/Share when no decoded text', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Share'), findsNothing);
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
}
