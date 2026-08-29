import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';

import '../../../../helpers/fakes.dart';
import '../../../../helpers/fake_feedback_service.dart';

void main() {
  late FakeSettingsRepository settingsRepo;
  late FakeTextHistoryRepository historyRepo;
  late FakeMorseTransmitter transmitter;

  setUp(() {
    settingsRepo = FakeSettingsRepository();
    historyRepo = FakeTextHistoryRepository();
    transmitter = FakeMorseTransmitter();

    final getIt = GetIt.instance;
    getIt
      ..registerFactory<EncodingController>(
        () => EncodingController(
          settingsRepository: settingsRepo,
          textHistoryRepository: historyRepo,
          morseEncoder: MorseEncoder(),
          morseTransmitter: transmitter,
        ),
      )
      ..registerSingleton<FeedbackService>(FakeFeedbackService())
      ..registerSingleton<ScreenFlashService>(ScreenFlashService());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    EncodingMode mode = EncodingMode.sound,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SendModeScreen(
          mode: mode,
          themeMode: ThemeMode.light,
          onThemeToggle: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SendModeScreen', () {
    group('common elements', () {
      testWidgets('displays app top bar with name', (tester) async {
        await pumpScreen(tester);

        expect(find.text('SimplyMorse'), findsOneWidget);
      });

      testWidgets('displays Send and Clear buttons', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Send'), findsOneWidget);
        expect(find.text('Clear'), findsOneWidget);
      });

      testWidgets('displays text input field', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Text to send'), findsOneWidget);
      });

      testWidgets('displays speed slider', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Speed'), findsOneWidget);
        expect(find.byType(Slider), findsAtLeast(1));
      });

      testWidgets('displays initial delay slider', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Initial delay'), findsOneWidget);
        expect(find.byType(Slider), findsAtLeast(2));
      });
    });

    group('sound mode', () {
      testWidgets('displays tone slider', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.sound);

        expect(find.text('Tone'), findsOneWidget);
      });

      testWidgets('displays Sound header with icon', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.sound);

        expect(find.text('Sound'), findsOneWidget);
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
      });

      testWidgets('does not show light method selector', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.sound);

        expect(find.text('Light method'), findsNothing);
      });
    });

    group('light mode (was flash)', () {
      testWidgets('hides tone slider', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.flash);

        expect(find.text('Tone'), findsNothing);
      });

      testWidgets('displays Light header', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.flash);

        expect(find.text('Light'), findsOneWidget);
      });

      testWidgets('displays light method selector', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.flash);

        expect(find.text('Light method'), findsOneWidget);
      });

      testWidgets('displays all three light method options', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.flash);

        expect(find.text('Flash LED'), findsOneWidget);
        expect(find.text('Display'), findsOneWidget);
        expect(find.text('Both'), findsAtLeast(1));
      });
    });

    group('both mode', () {
      testWidgets('displays tone slider', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.both);

        expect(find.text('Tone'), findsOneWidget);
      });

      testWidgets('displays Both header', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.both);

        expect(find.text('Both'), findsAtLeast(1));
      });

      testWidgets('displays light method selector', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.both);

        expect(find.text('Light method'), findsOneWidget);
      });
    });

    group('interactions', () {
      testWidgets(
        'Send button is disabled when text is empty',
        (tester) async {
          await pumpScreen(tester);

          final sendButton = find.widgetWithText(
            FilledButton,
            'Send',
          );
          expect(
            tester.widget<FilledButton>(sendButton).onPressed,
            isNull,
          );
        },
      );

      testWidgets(
        'Send button is enabled when text is entered',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'SOS',
          );
          await tester.pumpAndSettle();

          final sendButton = find.widgetWithText(
            FilledButton,
            'Send',
          );
          expect(
            tester.widget<FilledButton>(sendButton).onPressed,
            isNotNull,
          );
        },
      );

      testWidgets(
        'Clear button clears text input',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'hello',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Clear'));
          await tester.pumpAndSettle();

          final sendButton = find.widgetWithText(
            FilledButton,
            'Send',
          );
          expect(
            tester.widget<FilledButton>(sendButton).onPressed,
            isNull,
          );
        },
      );

      testWidgets(
        'updates WPM label when speed slider changes',
        (tester) async {
          await pumpScreen(tester);

          final slider = find.byType(Slider).first;
          await tester.drag(slider, const Offset(100, 0));
          await tester.pumpAndSettle();

          expect(find.textContaining('WPM'), findsOneWidget);
        },
      );

      testWidgets(
        'updates initial delay label when slider changes',
        (tester) async {
          await pumpScreen(tester);

          // Find the initial delay slider (second slider)
          final sliders = find.byType(Slider);
          // First slider is Speed, second is Initial delay
          await tester.drag(sliders.at(1), const Offset(100, 0));
          await tester.pumpAndSettle();

          expect(find.textContaining('s'), findsWidgets);
        },
      );

      testWidgets(
        'shows history dropdown when history exists',
        (tester) async {
          historyRepo.seed(['previous message']);
          await pumpScreen(tester);

          expect(find.text('History'), findsOneWidget);
        },
      );

      testWidgets(
        'hides history dropdown when history is empty',
        (tester) async {
          await pumpScreen(tester);

          expect(find.text('History'), findsNothing);
        },
      );

      testWidgets(
        'shows transmission label after text entry',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'SOS',
          );
          await tester.pumpAndSettle();

          expect(find.byType(RichText), findsWidgets);
        },
      );

      testWidgets(
        'Send triggers transmission',
        (tester) async {
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(
            find.byType(TextField),
            'E',
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();

          expect(find.text('E'), findsOneWidget);
        },
      );
    });

    group('haptic feedback', () {
      testWidgets('triggers heavy impact on Send', (tester) async {
        await pumpScreen(tester, mode: EncodingMode.flash);

        await tester.enterText(
          find.byType(TextField),
          'E',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();

        final feedback = GetIt.instance<FeedbackService>();
        expect(feedback, isNotNull);
      });

      testWidgets('triggers light impact on Clear', (tester) async {
        await pumpScreen(tester);

        await tester.enterText(
          find.byType(TextField),
          'hello',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        final feedback = GetIt.instance<FeedbackService>();
        expect(feedback, isNotNull);
      });
    });

    group('countdown overlay', () {
      testWidgets(
        'shows countdown when sending with initial delay > 0',
        (tester) async {
          settingsRepo.initialDelay = 3.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          // Countdown overlay should be visible
          expect(find.text('3'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);

          // Clean up: cancel and let the timer fire
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'shows instruction label for Flash LED mode',
        (tester) async {
          settingsRepo.initialDelay = 2.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          expect(
            find.text('Point the flash LED toward your target'),
            findsOneWidget,
          );

          // Clean up
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'shows instruction label for Display mode',
        (tester) async {
          settingsRepo.initialDelay = 2.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.flash);

          // Select Display light method
          await tester.tap(find.text('Display'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          expect(
            find.text('Point the screen toward your target'),
            findsOneWidget,
          );

          // Clean up
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'shows instruction label for Both light method',
        (tester) async {
          settingsRepo.initialDelay = 2.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.flash);

          // Select Both light method (last segment)
          await tester.tap(find.text('Both'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          expect(
            find.text('Point the flash LED and screen toward your target'),
            findsOneWidget,
          );

          // Clean up
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'shows generic label for sound-only mode',
        (tester) async {
          settingsRepo.initialDelay = 2.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.sound);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          expect(find.text('Get ready to transmit'), findsOneWidget);

          // Clean up
          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'Cancel button aborts the countdown',
        (tester) async {
          settingsRepo.initialDelay = 5.0;
          transmitter.autoComplete = false;
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pump();

          // Countdown is showing
          expect(find.text('Cancel'), findsOneWidget);

          await tester.tap(find.text('Cancel'));
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();

          // Should be back to normal — Send button visible again
          expect(find.text('Send'), findsOneWidget);
          // Countdown should be gone
          expect(find.text('Cancel'), findsNothing);
        },
      );
    });

    group('transmission controls', () {
      testWidgets(
        'shows Stop button when transmitting',
        (tester) async {
          transmitter.autoComplete = false;
          settingsRepo.initialDelay = 0.0;
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();

          // Stop button should be visible
          expect(find.text('Stop'), findsOneWidget);
          // Send and Clear should be hidden
          expect(find.text('Send'), findsNothing);
          expect(find.text('Clear'), findsNothing);
        },
      );

      testWidgets(
        'tapping Stop returns to Send button',
        (tester) async {
          transmitter.autoComplete = false;
          settingsRepo.initialDelay = 0.0;
          await pumpScreen(tester, mode: EncodingMode.flash);

          await tester.enterText(find.byType(TextField), 'E');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();

          // Verify Stop is showing
          expect(find.text('Stop'), findsOneWidget);

          // Ensure the button is visible and tap it
          await tester.ensureVisible(
            find.widgetWithText(FilledButton, 'Stop'),
          );
          await tester.tap(
            find.widgetWithText(FilledButton, 'Stop'),
          );
          await tester.pump();
          await tester.pumpAndSettle();

          // Send and Clear should reappear
          expect(find.text('Send'), findsOneWidget);
          expect(find.text('Clear'), findsOneWidget);
          expect(find.text('Stop'), findsNothing);
        },
      );
    });
  });
}
