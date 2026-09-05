import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/screen_timeout_service.dart';

import '../../helpers/wakelock_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  mockWakelockToggleChannel();

  group('ScreenTimeoutService modeListenable', () {
    test('starts at system and broadcasts setMode', () async {
      final service = ScreenTimeoutService();

      expect(service.modeListenable.value, DisplayTimeout.system);

      final received = <DisplayTimeout>[];
      service.modeListenable.addListener(
        () => received.add(service.modeListenable.value),
      );

      await service.setMode(DisplayTimeout.tripleSystem);

      expect(service.mode, DisplayTimeout.tripleSystem);
      expect(service.modeListenable.value, DisplayTimeout.tripleSystem);
      expect(received, [DisplayTimeout.tripleSystem]);
      service.dispose();
    });

    test('no notification when the mode does not change', () async {
      final service = ScreenTimeoutService();

      await service.setMode(DisplayTimeout.system);
      await service.setMode(DisplayTimeout.system);

      // Only real transitions notify: one change (the initial
      // setMode with the same value is a no-op broadcast-wise).
      final received = <DisplayTimeout>[];
      service.modeListenable.addListener(
        () => received.add(service.modeListenable.value),
      );
      await service.setMode(DisplayTimeout.alwaysOn);
      await service.setMode(DisplayTimeout.alwaysOn);
      expect(received, [DisplayTimeout.alwaysOn]);
      service.dispose();
    });
  });
}
