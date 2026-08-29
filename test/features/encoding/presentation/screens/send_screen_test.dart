import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/presentation/screens/send_screen.dart';

void main() {
  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SendScreen(
          themeMode: ThemeMode.light,
          onThemeToggle: noop,
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

void noop() {}
