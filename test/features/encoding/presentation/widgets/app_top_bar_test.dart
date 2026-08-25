import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

void main() {
  group('AppTopBar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      ThemeMode mode = ThemeMode.light,
      VoidCallback? onToggle,
    }) async {
      onToggle ??= () {};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTopBar(
              themeMode: mode,
              onThemeToggle: onToggle,
            ),
          ),
        ),
      );
    }

    testWidgets('displays app name and version', (tester) async {
      await pumpBar(tester);

      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(
        find.text('v${AppConstants.appVersion}'),
        findsOneWidget,
      );
    });

    testWidgets('shows light_mode icon for light theme', (tester) async {
      await pumpBar(tester, mode: ThemeMode.light);

      expect(find.byIcon(Icons.light_mode), findsOneWidget);
    });

    testWidgets('shows dark_mode icon for dark theme', (tester) async {
      await pumpBar(tester, mode: ThemeMode.dark);

      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    });

    testWidgets(
      'shows brightness_auto icon for system theme',
      (tester) async {
        await pumpBar(tester, mode: ThemeMode.system);

        expect(find.byIcon(Icons.brightness_auto), findsOneWidget);
      },
    );

    testWidgets('calls onThemeToggle when icon pressed', (tester) async {
      var tapped = false;
      await pumpBar(
        tester,
        onToggle: () => tapped = true,
      );

      await tester.tap(find.byIcon(Icons.light_mode));
      await tester.pump();

      expect(tapped, isTrue);
    });

    test('has correct preferred size', () {
      final bar = AppTopBar(
        themeMode: ThemeMode.light,
        onThemeToggle: () {},
      );
      expect(
        bar.preferredSize,
        const Size.fromHeight(kToolbarHeight),
      );
    });
  });
}
