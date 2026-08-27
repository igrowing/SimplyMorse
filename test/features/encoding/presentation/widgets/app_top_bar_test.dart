import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

void main() {
  group('AppTopBar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      ThemeMode mode = ThemeMode.light,
      Brightness platformBrightness = Brightness.light,
      VoidCallback? onToggle,
    }) async {
      onToggle ??= () {};
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(platformBrightness: platformBrightness),
            child: Scaffold(
              body: AppTopBar(
                themeMode: mode,
                onThemeToggle: onToggle,
              ),
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
      'shows dark_mode icon when system is light (system theme)',
      (tester) async {
        await pumpBar(
          tester,
          mode: ThemeMode.system,
          platformBrightness: Brightness.light,
        );

        // System is light → show opposite (dark_mode)
        expect(find.byIcon(Icons.dark_mode), findsOneWidget);
      },
    );

    testWidgets(
      'shows light_mode icon when system is dark (system theme)',
      (tester) async {
        await pumpBar(
          tester,
          mode: ThemeMode.system,
          platformBrightness: Brightness.dark,
        );

        // System is dark → show opposite (light_mode)
        expect(find.byIcon(Icons.light_mode), findsOneWidget);
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
