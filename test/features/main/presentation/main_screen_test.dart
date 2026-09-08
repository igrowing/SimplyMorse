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
      tester
        ..view.physicalSize = const Size(800, 900)
        ..view.devicePixelRatio = 1.0;
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

  group('MainScreen layout', () {
    testWidgets('narrow layout stacks receiving group under Send', (
      tester,
    ) async {
      tester
        ..view.physicalSize = const Size(560, 900)
        ..view.devicePixelRatio = 1.0;
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

      // Send sits above the receiving group with clear spacing…
      final sendRect = tester.getRect(find.text('Send'));
      final listenRect = tester.getRect(find.text('Listen'));
      expect(listenRect.top, greaterThan(sendRect.bottom + 31));
      // …and Listen and Watch share a horizontal row.
      final watchRect = tester.getRect(find.text('Watch'));
      expect(watchRect.top, closeTo(listenRect.top, 1));
    });

    testWidgets('wide layout stacks receiving group vertically', (
      tester,
    ) async {
      tester
        ..view.physicalSize = const Size(1200, 800)
        ..view.devicePixelRatio = 1.0;
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

      // Watch sits below Listen in the same column…
      final listenRect = tester.getRect(find.text('Listen'));
      final watchRect = tester.getRect(find.text('Watch'));
      expect(watchRect.top, greaterThan(listenRect.bottom));
      // …and the group sits beside the Send button.
      final sendRect = tester.getRect(find.text('Send'));
      expect(listenRect.left, greaterThan(sendRect.right));
    });
  });
}
