import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
import 'package:simply_morse/features/encoding/domain/models/light_method.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_encoder.dart';
import 'package:simply_morse/features/encoding/domain/services/morse_transmitter.dart';

import '../../../../helpers/fakes.dart';

void main() {
  late FakeTorchService torch;
  late MorseTransmitter transmitter;
  late MorseEncoder encoder;

  setUp(() {
    torch = FakeTorchService();
    transmitter = MorseTransmitter(torchService: torch);
    encoder = MorseEncoder();
  });

  tearDown(() {
    transmitter.dispose();
  });

  group('MorseTransmitter', () {
    group('flash transmission (flashLed)', () {
      test('toggles torch on for a single dit (E)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        expect(torch.calls, isNotEmpty);
        expect(torch.calls.first, isTrue);
        expect(torch.calls.last, isFalse);
      });

      test('toggles torch correctly for SOS', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('SOS', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        final onCount = torch.calls.where((c) => c).length;
        expect(onCount, 9);
        expect(torch.calls.last, isFalse);
      });

      test('toggles torch correctly for T (single dah)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('T', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        final onCount = torch.calls.where((c) => c).length;
        expect(onCount, 1);
        expect(torch.calls.last, isFalse);
      });

      test('respects on/off event pattern for HI', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('HI', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        final toneOnCount = events.where((e) => e.isOn).length;
        final torchOnCount = torch.calls.where((c) => c).length;
        expect(torchOnCount, toneOnCount);
      });

      test('flash-only mode never creates AudioPlayer', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        expect(transmitter.hasAudioPlayer, isFalse);
      });
    });

    group('display transmission', () {
      test('toggles displayBlink for SOS', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.display,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('SOS', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        // displayBlink should end as false after transmission
        expect(transmitter.displayBlink.value, isFalse);
        // torch should not be called at all
        expect(torch.calls, isEmpty);
      });

      test('display-only mode never creates AudioPlayer', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.display,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        expect(transmitter.hasAudioPlayer, isFalse);
        expect(torch.calls, isEmpty);
      });
    });

    group('both (torch + display)', () {
      test('toggles both torch and displayBlink', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.both,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        // Torch should have been called
        expect(torch.calls, isNotEmpty);
        expect(torch.calls.first, isTrue);
        expect(torch.calls.last, isFalse);
        // displayBlink should end as false
        expect(transmitter.displayBlink.value, isFalse);
      });
    });

    group('initial delay', () {
      test('completes transmission even with delay', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0.1,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        var completed = false;
        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () => completed = true,
        );
        // Allow the progress timer to fire
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(completed, isTrue);
      });

      test('zero delay starts immediately', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
          lightMethod: LightMethod.flashLed,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        expect(torch.calls, isNotEmpty);
      });
    });

    group('event validation', () {
      test('receives correct events for E (dit)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 10,
          toneHz: 700,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        expect(events.where((e) => e.isOn).length, 1);
        expect(events.first.isOn, isTrue);
      });

      test('receives correct events for T (dah)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 10,
          toneHz: 700,
          initialDelaySec: 0,
        );
        final symbols = encoder.encode('T', settings);
        final events = encoder.buildTimeline(symbols, settings);

        final onEvents = events.where((e) => e.isOn);
        expect(onEvents.length, 1);
        final ditMs = 1200 / 10;
        final dahMs = 3 * ditMs;
        expect(onEvents.first.durationMs, dahMs.round());
      });

      test(
        'SOS has 9 on events (3 dits + 3 dahs + 3 dits)',
        () {
          final settings = EncodingSettings(
            mode: EncodingMode.flash,
            speedWpm: 20,
            toneHz: 700,
            initialDelaySec: 0,
          );
          final symbols = encoder.encode('SOS', settings);
          final events = encoder.buildTimeline(symbols, settings);

          expect(events.where((e) => e.isOn).length, 9);
        },
      );
    });
  });
}
