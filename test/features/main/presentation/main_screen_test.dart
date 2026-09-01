import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/main/presentation/main_screen.dart';

void main() {
  late ThemeController themeController;
  late ScreenTimeoutService screenTimeoutService;

  setUp(() {
    themeController = ThemeController();
    screenTimeoutService = ScreenTimeoutService();
  });

  group('MainScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MainScreen(
            themeController: themeController,
            screenTimeoutService: screenTimeoutService,
            displayTimeout: DisplayTimeout.system,
            onDisplayTimeoutChanged: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('displays app top bar with name', (tester) async {
      await pumpScreen(tester);
      expect(find.text('SimplyMorse'), findsOneWidget);
    });

    testWidgets('displays Send button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Send'), findsOneWidget);
    });

    testWidgets('displays Listen button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Listen'), findsOneWidget);
    });

    testWidgets('displays Watch button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Watch'), findsOneWidget);
    });

    testWidgets('displays mic icon for Listen', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('displays camera icon for Watch', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('all buttons are tappable on non-web', (tester) async {
      await pumpScreen(tester);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithIcon(FilledButton, Icons.send))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithIcon(FilledButton, Icons.mic))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithIcon(FilledButton, Icons.camera_alt),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('does not show "Not available on web" on non-web', (
      tester,
    ) async {
      await pumpScreen(tester);
      expect(find.text('Not available on web'), findsNothing);
    });
  });
}
