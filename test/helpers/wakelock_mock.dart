import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakelock_plus_platform_interface/messages.g.dart';

/// Mocks the Pigeon channel behind `WakelockPlus.toggle` so
/// `ScreenTimeoutService.setMode` can run in the test binding,
/// where no platform backend exists.
///
/// Must be called after `TestWidgetsFlutterBinding.ensureInitialized()`.
void mockWakelockToggleChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockDecodedMessageHandler(
        const BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.'
          'WakelockPlusApi.toggle',
          WakelockPlusApi.pigeonChannelCodec,
        ),
        (message) async => <Object?>[null],
      );
}
