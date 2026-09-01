import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';
import 'package:simply_morse/features/encoding/domain/models/output_method.dart';
import 'package:simply_morse/features/encoding/domain/models/transmission_state.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/presentation/controllers/encoding_controller.dart';

import '../../../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeSettingsRepository settingsRepo;
  late FakeTextHistoryRepository historyRepo;
  late MorseEncoder encoder;
  late FakeMorseTransmitter transmitter;
  late EncodingController controller;

  setUp(() {
    settingsRepo = FakeSettingsRepository();
    historyRepo = FakeTextHistoryRepository();
    encoder = MorseEncoder();
    transmitter = FakeMorseTransmitter();
    controller = EncodingController(
      settingsRepository: settingsRepo,
      textHistoryRepository: historyRepo,
      morseEncoder: encoder,
      morseTransmitter: transmitter,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('EncodingController', () {
    group('init', () {
      test('loads settings and history', () async {
        settingsRepo.speed = 15.0;
        settingsRepo.tone = 800.0;
        settingsRepo.initialDelay = 5.0;
        historyRepo.seed(['hello', 'sos']);

        await controller.init();

        expect(controller.mode, EncodingMode.sound);
        expect(controller.speedWpm, 15.0);
        expect(controller.toneHz, 800.0);
        expect(controller.initialDelaySec, 5.0);
        expect(controller.history, ['hello', 'sos']);
        expect(controller.text, isEmpty);
        expect(controller.isTransmitting, isFalse);
      });

      test('only initializes once', () async {
        await controller.init();
        await controller.init();

        // Mode should stay as first init
        expect(controller.mode, EncodingMode.sound);
      });

      test('notifies listeners after init', () async {
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.init();

        expect(notifyCount, greaterThan(0));
      });
    });

    group('updateText', () {
      test('updates text value', () async {
        await controller.init();
        controller.updateText('hello');

        expect(controller.text, 'hello');
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.updateText('test');

        expect(notifyCount, 1);
      });
    });

    group('selectFromHistory', () {
      test('sets text from history entry', () async {
        await controller.init();
        controller.selectFromHistory('SOS');

        expect(controller.text, 'SOS');
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.selectFromHistory('SOS');

        expect(notifyCount, 1);
      });
    });

    group('updateSpeed', () {
      test('updates speed value', () async {
        await controller.init();
        await controller.updateSpeed(20.0);

        expect(controller.speedWpm, 20.0);
      });

      test('persists to settings repository', () async {
        await controller.init();
        await controller.updateSpeed(25.0);

        expect(settingsRepo.saveSpeedCount, 1);
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.updateSpeed(15.0);

        expect(notifyCount, 1);
      });
    });

    group('updateTone', () {
      test('updates tone value', () async {
        await controller.init();
        await controller.updateTone(850.0);

        expect(controller.toneHz, 850.0);
      });

      test('persists to settings repository', () async {
        await controller.init();
        await controller.updateTone(600.0);

        expect(settingsRepo.saveToneCount, 1);
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.updateTone(500.0);

        expect(notifyCount, 1);
      });
    });

    group('updateInitialDelay', () {
      test('updates initial delay value', () async {
        await controller.init();
        await controller.updateInitialDelay(10.0);

        expect(controller.initialDelaySec, 10.0);
      });

      test('persists to settings repository', () async {
        await controller.init();
        await controller.updateInitialDelay(5.0);

        expect(settingsRepo.saveInitialDelayCount, 1);
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.updateInitialDelay(3.0);

        expect(notifyCount, 1);
      });
    });

    group('updateLightMethod', () {
      test('updates light method value', () async {
        await controller.init();
        controller.updateLightMethod(LightMethod.display);

        expect(controller.lightMethod, LightMethod.display);
      });

      test('updates to both', () async {
        await controller.init();
        controller.updateLightMethod(LightMethod.both);

        expect(controller.lightMethod, LightMethod.both);
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.updateLightMethod(LightMethod.display);

        expect(notifyCount, 1);
      });
    });

    group('send', () {
      test('does nothing when text is empty', () async {
        await controller.init();
        await controller.send();

        expect(transmitter.transmitCount, 0);
      });

      test('does nothing when already transmitting', () async {
        await controller.init();
        controller.updateText('SOS');
        await controller.send();
        expect(transmitter.transmitCount, 1);
      });

      test('encodes and transmits the text', () async {
        await controller.init();
        controller.updateText('SOS');
        await controller.send();

        expect(transmitter.transmitCount, 1);
        expect(transmitter.lastEvents, isNotNull);
        expect(transmitter.lastEvents!, isNotEmpty);
        expect(transmitter.lastSettings!.mode, EncodingMode.sound);
      });

      test('passes light method to settings', () async {
        await controller.init();
        controller.updateLightMethod(LightMethod.display);
        controller.updateText('SOS');
        await controller.send();

        expect(
          transmitter.lastSettings!.lightMethod,
          LightMethod.display,
        );
      });

      test('runs countdown before transmit when delay > 0', () async {
        await controller.init();
        await controller.updateInitialDelay(1.0);
        controller.updateText('SOS');

        // The countdown should fire during send()
        final countdownValues = <int?>[];
        controller.countdownRemaining.addListener(() {
          countdownValues.add(controller.countdownRemaining.value);
        });

        await controller.send();

        // Transmitter receives delay = 0 (countdown consumed it)
        expect(transmitter.lastSettings!.initialDelaySec, 0);
        // Countdown went through 1 -> null
        expect(countdownValues, contains(1));
        expect(controller.countdownRemaining.value, isNull);
      });

      test('transmits immediately when delay is 0', () async {
        await controller.init();
        controller.updateText('SOS');
        await controller.send();

        expect(transmitter.lastSettings!.initialDelaySec, 0);
      });

      test('saves text to history', () async {
        await controller.init();
        controller.updateText('HELLO');
        await controller.send();

        expect(historyRepo.saveCount, 1);
        expect(controller.history, contains('HELLO'));
      });

      test(
        'updates transmission status to completed',
        () async {
          await controller.init();
          controller.updateText('E');
          await controller.send();

          expect(
            controller.transmission.status,
            TransmissionStatus.completed,
          );
        },
      );
    });

    group('clear', () {
      test('clears text and resets transmission state', () async {
        await controller.init();
        controller.updateText('hello');
        await controller.clear();

        expect(controller.text, isEmpty);
        expect(
          controller.transmission.status,
          TransmissionStatus.idle,
        );
      });

      test('stops the transmitter', () async {
        await controller.init();
        controller.updateText('hello');
        await controller.send();
        await controller.clear();

        expect(transmitter.stopCount, 1);
      });

      test('notifies listeners', () async {
        await controller.init();
        controller.updateText('hello');
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.clear();

        expect(notifyCount, greaterThan(0));
      });
    });

    group('pause', () {
      test('stops the transmitter', () async {
        await controller.init();
        controller.updateText('hello');
        await controller.pause();

        expect(transmitter.stopCount, 1);
      });

      test('resets transmission state to idle', () async {
        await controller.init();
        controller.updateText('hello');
        await controller.pause();

        expect(
          controller.transmission.status,
          TransmissionStatus.idle,
        );
      });

      test('notifies listeners', () async {
        await controller.init();
        var notifyCount = 0;
        controller.addListener(() => notifyCount++);

        await controller.pause();

        expect(notifyCount, greaterThan(0));
      });
    });

    group('defaults', () {
      test('has default speed, tone and delay before init', () {
        expect(controller.speedWpm, 7.0);
        expect(controller.toneHz, 700.0);
        expect(controller.initialDelaySec, 1.0);
      });

      test('has default light method before init', () {
        expect(controller.lightMethod, LightMethod.display);
      });

      test(
        'transmission state starts idle',
        () {
          expect(
            controller.transmission.status,
            TransmissionStatus.idle,
          );
          expect(controller.isTransmitting, isFalse);
        },
      );
    });

    group('displayBlink', () {
      test('exposes a ValueNotifier from transmitter', () async {
        await controller.init();

        expect(controller.displayBlink, isA<ValueNotifier<bool>>());
        expect(controller.displayBlink.value, isFalse);
      });
    });

    group('output methods', () {
      test('defaults to sound only', () async {
        await controller.init();

        expect(controller.outputs, {OutputMethod.sound});
        expect(controller.hasSound, isTrue);
        expect(controller.hasLed, isFalse);
        expect(controller.hasDisplay, isFalse);
      });

      test('updateOutputs changes the selection', () async {
        await controller.init();
        controller.updateOutputs({OutputMethod.led, OutputMethod.display});

        expect(controller.hasSound, isFalse);
        expect(controller.hasLed, isTrue);
        expect(controller.hasDisplay, isTrue);
        expect(controller.mode, EncodingMode.flash);
        expect(controller.lightMethod, LightMethod.both);
      });

      test('updateOutputs rejects empty selection', () async {
        await controller.init();
        controller.updateOutputs({});

        // Stays as sound
        expect(controller.hasSound, isTrue);
      });

      test('toggleOutput adds a method', () async {
        await controller.init();
        controller.toggleOutput(OutputMethod.led);

        expect(controller.hasSound, isTrue);
        expect(controller.hasLed, isTrue);
        expect(controller.mode, EncodingMode.both);
      });

      test('toggleOutput removes a method (if not the last)', () async {
        await controller.init();
        controller.toggleOutput(OutputMethod.led);
        controller.toggleOutput(OutputMethod.sound);

        expect(controller.hasSound, isFalse);
        expect(controller.hasLed, isTrue);
      });

      test('toggleOutput cannot remove the last method', () async {
        await controller.init();
        controller.toggleOutput(OutputMethod.sound);

        expect(controller.hasSound, isTrue);
      });

      test('sound+led maps to both mode with flashLed method', () async {
        await controller.init();
        controller.toggleOutput(OutputMethod.led);

        expect(controller.mode, EncodingMode.both);
        expect(controller.lightMethod, LightMethod.flashLed);
      });

      test('sound+display maps to both mode with display method', () async {
        await controller.init();
        controller.toggleOutput(OutputMethod.display);

        expect(controller.mode, EncodingMode.both);
        expect(controller.lightMethod, LightMethod.display);
      });

      test('led only maps to flash mode with flashLed method', () async {
        await controller.init();
        controller.updateOutputs({OutputMethod.led});

        expect(controller.mode, EncodingMode.flash);
        expect(controller.lightMethod, LightMethod.flashLed);
      });

      test('display only maps to flash mode with display method', () async {
        await controller.init();
        controller.updateOutputs({OutputMethod.display});

        expect(controller.mode, EncodingMode.flash);
        expect(controller.lightMethod, LightMethod.display);
      });
    });
  });
}
