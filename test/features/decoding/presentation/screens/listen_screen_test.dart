import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/share_service.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/video_decoder.dart';
import 'package:simply_morse/features/decoding/presentation/controllers/decoding_controller.dart';
import 'package:simply_morse/features/decoding/presentation/screens/listen_screen.dart';

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
    cameraCapture = FakeCameraCapture();
    feedbackService = FakeFeedbackService();
    shareService = FakeShareService();
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    bool hasPermission = true,
  }) async {
    audioCapture = FakeAudioCapture(hasPermissionValue: hasPermission);

    final getIt = GetIt.instance;
    await getIt.reset();
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
      ..registerSingleton<FeedbackService>(feedbackService)
      ..registerSingleton<ShareService>(shareService);

    await tester.pumpWidget(
      MaterialApp(
        home: ListenScreen(
          themeMode: ThemeMode.light,
          onThemeToggle: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ListenScreen', () {
    testWidgets('displays Hear header', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Hear'), findsOneWidget);
    });

    testWidgets('displays Start button initially', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('shows Idle status when not started', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Idle'), findsOneWidget);
    });

    testWidgets('shows decoded text input field', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Decoded text'), findsOneWidget);
    });

    testWidgets('shows Clear button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Clear'), findsOneWidget);
    });

    testWidgets('Start changes to Pause when listening', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Pause'), findsOneWidget);
    });

    testWidgets('Pause changes to Resume when paused', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
    });

    testWidgets('shows Calibrating status when active', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('Calibrating…'), findsOneWidget);
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

    testWidgets('does not show WPM when idle', (tester) async {
      await pumpScreen(tester);
      expect(find.textContaining('WPM'), findsNothing);
    });

    testWidgets('does not show Copy/Share buttons when no decoded text', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets(
      'shows permission snackbar when mic permission denied',
      (tester) async {
        await pumpScreen(tester, hasPermission: false);

        await tester.ensureVisible(find.text('Start'));
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        expect(
          find.text('Microphone permission is required to decode Morse audio.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'does not start listening when permission denied',
      (tester) async {
        await pumpScreen(tester, hasPermission: false);

        await tester.ensureVisible(find.text('Start'));
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();

        expect(find.text('Start'), findsOneWidget);
        expect(find.text('Idle'), findsOneWidget);
      },
    );

    testWidgets('Clear button resets to idle', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Pause'));
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Clear'));
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();

      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('haptic feedback is triggered on Start', (tester) async {
      await pumpScreen(tester);

      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(feedbackService.calls, contains('medium'));
    });

    testWidgets('haptic feedback is triggered on Pause', (tester) async {
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
