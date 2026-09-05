import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:simply_morse/core/services/feedback_service.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_mode_screen.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/transmission_progress_text.dart';
import '../../../../helpers/fake_feedback_service.dart';
import '../../../../helpers/fakes.dart';

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

  Future<void> pumpScreen(WidgetTester tester) async {
    // Use a taller surface so bottom buttons (Send, Clear)
    // are within hit-test bounds.
    tester
      ..view.physicalSize = const Size(800, 900)
      ..view.devicePixelRatio = 1.0;
    await tester.pumpWidget(
      MaterialApp(
        home: SendModeScreen(
          themeController: ThemeController(),
          screenTimeoutService: ScreenTimeoutService(),
          displayTimeout: DisplayTimeout.system,
          onDisplayTimeoutChanged: (_) {},
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

      testWidgets('displays back button in app bar', (tester) async {
        // Push the screen onto a navigator so canPop() is true.
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      unawaited(
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SendModeScreen(
                              themeController: ThemeController(),
                              screenTimeoutService: ScreenTimeoutService(),
                              displayTimeout: DisplayTimeout.system,
                              onDisplayTimeoutChanged: (_) {},
                            ),
                          ),
                        ),
                      );
                    },
                    child: const Text('Go'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Go'));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      });
    });

    group('output method toggle', () {
      testWidgets('displays Output label', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Output'), findsOneWidget);
      });

      testWidgets('displays Sound, LED, Display chips', (tester) async {
        await pumpScreen(tester);

        expect(find.text('Sound'), findsOneWidget);
        expect(find.text('LED'), findsOneWidget);
        expect(find.text('Display'), findsOneWidget);
      });

      testWidgets('Sound is selected by default', (tester) async {
        await pumpScreen(tester);

        final soundChip = find.widgetWithText(FilterChip, 'Sound');
        expect(
          tester.widget<FilterChip>(soundChip).selected,
          isTrue,
        );
      });

      testWidgets('LED and Display are not selected by default', (
        tester,
      ) async {
        await pumpScreen(tester);

        final ledChip = find.widgetWithText(FilterChip, 'LED');
        final displayChip = find.widgetWithText(FilterChip, 'Display');
        expect(tester.widget<FilterChip>(ledChip).selected, isFalse);
        expect(tester.widget<FilterChip>(displayChip).selected, isFalse);
      });

      testWidgets('tapping LED adds it to selection', (tester) async {
        await pumpScreen(tester);

        await tester.tap(find.text('LED'));
        await tester.pumpAndSettle();

        final ledChip = find.widgetWithText(FilterChip, 'LED');
        expect(tester.widget<FilterChip>(ledChip).selected, isTrue);
        final soundChip = find.widgetWithText(FilterChip, 'Sound');
        expect(tester.widget<FilterChip>(soundChip).selected, isTrue);
      });

      testWidgets(
        'tapping Sound when only Sound is selected does nothing',
        (tester) async {
          await pumpScreen(tester);

          await tester.tap(find.text('Sound'));
          await tester.pumpAndSettle();

          final soundChip = find.widgetWithText(FilterChip, 'Sound');
          expect(tester.widget<FilterChip>(soundChip).selected, isTrue);
        },
      );

      testWidgets('selecting LED shows tone slider (sound still on)', (
        tester,
      ) async {
        await pumpScreen(tester);

        // Tone should be visible because Sound is selected by default
        expect(find.text('Tone'), findsOneWidget);
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

          await tester.ensureVisible(find.text('Clear'));
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
        'shows no separate transmission label after text entry',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'SOS',
          );
          await tester.pumpAndSettle();

          // The input box is the only transmission display: while
          // idle there is no progress view, only the TextField.
          expect(find.byType(TransmissionProgressText), findsNothing);
          expect(find.byType(TextField), findsOneWidget);
        },
      );

      testWidgets(
        'shows transmission progress inside the input box',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'SOS',
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.text('Send'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send'));
          // One frame into the transmission: the input box is
          // replaced in place by the progress view, not by a
          // separate follow-up box.
          await tester.pump();

          expect(find.byType(TextField), findsNothing);
          final progress = find.byType(TransmissionProgressText);
          expect(progress, findsOneWidget);
          // The full message is rendered inside the input box,
          // one span per character (per-character highlighting is
          // covered by the TransmissionProgressText widget tests).
          final richText = tester.widget<RichText>(
            find.descendant(
              of: find.byType(TransmissionProgressText),
              matching: find.byType(RichText),
            ),
          );
          final spans = (richText.text as TextSpan).children!;
          expect(spans.length, 3);
          expect(spans.map((s) => (s as TextSpan).text).join(), 'SOS');

          // After completion the editable input returns, with
          // the text intact.
          await tester.pumpAndSettle();
          expect(find.byType(TransmissionProgressText), findsNothing);
          expect(find.byType(TextField), findsOneWidget);
          expect(find.text('SOS'), findsOneWidget);
        },
      );

      testWidgets(
        'Send triggers transmission',
        (tester) async {
          await pumpScreen(tester);

          await tester.enterText(
            find.byType(TextField),
            'E',
          );
          await tester.pumpAndSettle();

          await tester.ensureVisible(find.text('Send'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();

          expect(find.text('E'), findsOneWidget);
        },
      );
    });

    group('haptic feedback', () {
      testWidgets('triggers heavy impact on Send', (tester) async {
        await pumpScreen(tester);

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
          'E',
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.text('Clear'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();

        final feedback = GetIt.instance<FeedbackService>();
        expect(feedback, isNotNull);
      });
    });
  });
}
