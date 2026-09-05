import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';
import 'package:simply_morse/core/theme/theme_controller.dart';
import 'package:simply_morse/features/settings/presentation/screens/settings_screen.dart';

import '../../../../helpers/wakelock_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockWakelockToggleChannel();

  group('SettingsScreen display timeout switch', () {
    testWidgets(
      'switch selection updates immediately without a parent rebuild',
      (tester) async {
        final service = ScreenTimeoutService();

        // The service is the single source of truth; the screen
        // reads the selection from its notifier — not from the
        // constructor param captured when the route was pushed.
        await service.setMode(DisplayTimeout.system);

        await tester.pumpWidget(
          MaterialApp(
            home: SettingsScreen(
              themeController: ThemeController(),
              screenTimeoutService: service,
              themeMode: ThemeMode.system,
              displayTimeout: DisplayTimeout.system,
              onDisplayTimeoutChanged: service.setMode,
            ),
          ),
        );
        await tester.pumpAndSettle();

        Set<DisplayTimeout> selected() => tester
            .widget<SegmentedButton<DisplayTimeout>>(
              find.byType(SegmentedButton<DisplayTimeout>),
            )
            .selected;

        expect(selected(), {DisplayTimeout.system});

        // Tap the '3× System' segment. The pushed screen's parent
        // never rebuilds — the selection must refresh on its own
        // from the service notifier.
        await tester.tap(find.text('3× System'));
        await tester.pumpAndSettle();

        expect(service.mode, DisplayTimeout.tripleSystem);
        expect(selected(), {DisplayTimeout.tripleSystem});

        // Dispose before the test ends so the inactivity timer
        // does not outlive the widget tree.
        service.dispose();
      },
    );
  });
}
