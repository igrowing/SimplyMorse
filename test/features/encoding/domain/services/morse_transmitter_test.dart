import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_mode.dart';
import 'package:simply_morse/features/encoding/domain/models/encoding_settings.dart';
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
    group('flash transmission', () {
      test('toggles torch on for a single dit (E)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        // E = single dit → torch enabled once then disabled
        expect(torch.calls, isNotEmpty);
        expect(torch.calls.first, isTrue);
        expect(torch.calls.last, isFalse);
      });

      test('toggles torch correctly for SOS', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
        );
        final symbols = encoder.encode('SOS', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        // SOS = ... --- ... → 9 tone events (on)
        final onCount = torch.calls.where((c) => c).length;
        expect(onCount, 9);
        expect(torch.calls.last, isFalse);
      });

      test('toggles torch correctly for T (single dah)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 100,
          toneHz: 700,
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
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        await transmitter.transmit(
          events: events,
          settings: settings,
          onProgress: (_) {},
          onComplete: () {},
        );

        // AudioPlayer should not be created in flash-only mode
        expect(transmitter.hasAudioPlayer, isFalse);
      });
    });

    group('event validation', () {
      test('receives correct events for E (dit)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 10,
          toneHz: 700,
        );
        final symbols = encoder.encode('E', settings);
        final events = encoder.buildTimeline(symbols, settings);

        // E = dit → 1 on event
        expect(events.where((e) => e.isOn).length, 1);
        expect(events.first.isOn, isTrue);
      });

      test('receives correct events for T (dah)', () async {
        final settings = EncodingSettings(
          mode: EncodingMode.flash,
          speedWpm: 10,
          toneHz: 700,
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
          );
          final symbols = encoder.encode('SOS', settings);
          final events = encoder.buildTimeline(symbols, settings);

          expect(events.where((e) => e.isOn).length, 9);
        },
      );
    });
  });
}
