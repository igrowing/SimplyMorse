import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/presentation/widgets/app_top_bar.dart';

void main() {
  group('AppTopBar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      bool showSettingsIcon = true,
      VoidCallback? onSettingsTap,
    }) async {
      onSettingsTap ??= () {};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppTopBar(
              showSettingsIcon: showSettingsIcon,
              onSettingsTap: onSettingsTap,
            ),
          ),
        ),
      );
    }

    testWidgets('displays app name', (tester) async {
      await pumpBar(tester);
      expect(find.text(AppConstants.appName), findsOneWidget);
    });

    testWidgets('does not display version in app bar', (tester) async {
      await pumpBar(tester);
      expect(
        find.text('v${AppConstants.appVersion}'),
        findsNothing,
      );
    });

    testWidgets('shows settings gear icon by default', (tester) async {
      await pumpBar(tester);
      expect(find.byIcon(Icons.settings), findsOneWidget);
    });

    testWidgets('hides settings icon when showSettingsIcon is false', (
      tester,
    ) async {
      await pumpBar(tester, showSettingsIcon: false);
      expect(find.byIcon(Icons.settings), findsNothing);
    });

    testWidgets('calls onSettingsTap when gear pressed', (tester) async {
      var tapped = false;
      await pumpBar(
        tester,
        onSettingsTap: () => tapped = true,
      );

      await tester.tap(find.byIcon(Icons.settings));
      await tester.pump();

      expect(tapped, isTrue);
    });

    test('has correct preferred size', () {
      final bar = AppTopBar(onSettingsTap: () {});
      expect(
        bar.preferredSize,
        const Size.fromHeight(kToolbarHeight),
      );
    });
  });
}
