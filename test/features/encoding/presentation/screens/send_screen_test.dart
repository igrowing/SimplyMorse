import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_screen.dart';

void main() {
  late ThemeController themeController;
  late ScreenTimeoutService screenTimeoutService;

  setUp(() {
    themeController = ThemeController();
    screenTimeoutService = ScreenTimeoutService();
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SendScreen(
          themeController: themeController,
          screenTimeoutService: screenTimeoutService,
          displayTimeout: DisplayTimeout.system,
          onDisplayTimeoutChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SendScreen', () {
    testWidgets('displays Sound button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Sound'), findsOneWidget);
    });

    testWidgets('displays Light button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('displays Both button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Both'), findsOneWidget);
    });

    testWidgets('all three mode buttons are present', (tester) async {
      await pumpScreen(tester);
      expect(find.byType(FilledButton), findsNWidgets(3));
    });

    testWidgets('does not display old Flash LED label', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Flash LED'), findsNothing);
    });
  });
}
