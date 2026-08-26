import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/presentation/screens/receive_screen.dart';

void main() {
  group('ReceiveScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiveScreen(
            themeMode: ThemeMode.light,
            onThemeToggle: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('displays app top bar with name', (tester) async {
      await pumpScreen(tester);
      expect(find.text('SimplyMorse'), findsOneWidget);
    });

    testWidgets('displays Hear button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Hear'), findsOneWidget);
    });

    testWidgets('displays Watch button', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Watch'), findsOneWidget);
    });

    testWidgets('displays mic icon for Hear', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.mic), findsOneWidget);
    });

    testWidgets('displays camera icon for Watch', (tester) async {
      await pumpScreen(tester);
      expect(find.byIcon(Icons.camera_alt), findsOneWidget);
    });

    testWidgets('both buttons are tappable', (tester) async {
      await pumpScreen(tester);
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
  });
}
