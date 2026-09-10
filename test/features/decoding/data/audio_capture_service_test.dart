import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:record_platform_interface/record_platform_interface.dart';
import 'package:simply_morse/features/decoding/data/audio_capture_service.dart';

import '../../../helpers/fake_record_platform.dart';

void main() {
  late FakeRecordPlatform fake;
  late AudioCaptureImpl capture;

  setUp(() {
    fake = FakeRecordPlatform();
    RecordPlatform.instance = fake;
    capture = AudioCaptureImpl();
  });

  tearDown(() async {
    await capture.stop();
  });

  /// Pumps the event queue until pending microtasks/futures settle.
  Future<void> pump([
    int times = 8,
  ]) async {
    for (var i = 0; i < times; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('AudioCaptureImpl debug events', () {
    test('startDetail describes the android audio source', () {
      // defaultSource: no support flag needed.
      expect(
        AudioCaptureImpl.startDetail(
          platform: TargetPlatform.android,
          audioSource: AndroidAudioSource.defaultSource,
        ),
        'requested_sample_rate=44100 channels=1 pcm16 '
        'audio_source=defaultSource',
      );

      // unprocessed: the device support flag must be visible.
      expect(
        AudioCaptureImpl.startDetail(
          platform: TargetPlatform.android,
          audioSource: AndroidAudioSource.unprocessed,
          unprocessedSupported: true,
        ),
        'requested_sample_rate=44100 channels=1 pcm16 '
        'audio_source=unprocessed unprocessed_supported=1',
      );
      expect(
        AudioCaptureImpl.startDetail(
          platform: TargetPlatform.android,
          audioSource: AndroidAudioSource.unprocessed,
          unprocessedSupported: false,
        ),
        'requested_sample_rate=44100 channels=1 pcm16 '
        'audio_source=unprocessed unprocessed_supported=0',
      );
      expect(
        AudioCaptureImpl.startDetail(
          platform: TargetPlatform.android,
          audioSource: AndroidAudioSource.unprocessed,
        ),
        'requested_sample_rate=44100 channels=1 pcm16 '
        'audio_source=unprocessed unprocessed_supported=?',
      );
    });

    test('startDetail states disabled voice AGC on iOS', () {
      expect(
        AudioCaptureImpl.startDetail(
          platform: TargetPlatform.iOS,
          audioSource: AndroidAudioSource.defaultSource,
        ),
        'requested_sample_rate=44100 channels=1 pcm16 voice_agc=off',
      );
    });

    test('hasPermission reports the permission event', () async {
      final events = <Map<String, Object?>>[];
      capture.onDebugEvent =
          ({required timestampMs, required event, dtMs, detail}) {
            events.add({'event': event, 'detail': detail});
          };

      await capture.hasPermission();

      expect(events, hasLength(1));
      expect(events.single['event'], 'permission');
      expect(events.single['detail'], 'granted=1');
    });

    test('start and buffers report lifecycle events with samples', () async {
      final events = <Map<String, Object?>>[];
      capture.onDebugEvent =
          ({required timestampMs, required event, dtMs, detail}) {
            events.add({'event': event, 'detail': detail});
          };

      final received = <List<double>>[];
      final done = Completer<void>();
      final sub = capture.start().listen(
        received.add,
        onDone: done.complete,
      );

      // The async* generator only runs once listened: wait for the
      // 'started' event (emitted after startStream resolves).
      await pump();
      expect(
        events.map((e) => e['event']).toList(),
        containsAllInOrder(['start', 'started']),
      );
      expect(
        events.firstWhere((e) => e['event'] == 'start')['detail'],
        contains('requested_sample_rate=44100'),
      );

      // Push one PCM frame: +1 then -1 (full-scale little-endian
      // 16-bit), and a truncated trailing byte that must be
      // dropped by the byte→sample conversion.
      fake.emit(Uint8List.fromList([0x01, 0x00, 0xFF, 0xFF, 0x00]));
      await pump();

      expect(received, hasLength(1));
      expect(received.single, hasLength(2));
      expect(received.single[0], closeTo(1 / 32768, 1e-9));
      expect(received.single[1], closeTo(-1 / 32768, 1e-9));

      final bufferEvents = events.where((e) => e['event'] == 'buffer');
      expect(bufferEvents, hasLength(1));
      expect(bufferEvents.single['detail'], contains('bytes=5'));

      // Stop BEFORE cancel: closing the platform stream lets the
      // generator's await-for loop run out, otherwise the cancel
      // future would wait forever for the next (never-coming)
      // buffer.
      await capture.stop();
      await sub.cancel();
      await done.future; // completes when the generator ends
    });

    test('buffer events report wall-clock dt between arrivals', () async {
      final bufferDts = <int?>[];
      capture.onDebugEvent =
          ({required timestampMs, required event, dtMs, detail}) {
            if (event == 'buffer') bufferDts.add(dtMs);
          };

      final sub = capture.start().listen((_) {});
      await pump();

      fake.emit(Uint8List(2));
      await pump(1);
      fake.emit(Uint8List(2));
      await pump();

      expect(bufferDts, hasLength(2));
      // The first buffer's dt measures from the 'started' event.
      expect(bufferDts.first, greaterThanOrEqualTo(0));
      expect(bufferDts.last, greaterThanOrEqualTo(0));

      await capture.stop();
      await sub.cancel();
    });

    test('stop reports the stop event', () async {
      final events = <String>[];
      capture.onDebugEvent =
          ({required timestampMs, required event, dtMs, detail}) {
            events.add(event);
          };

      final sub = capture.start().listen((_) {});
      await pump();
      await capture.stop();
      await sub.cancel();

      expect(events, containsAllInOrder(['start', 'stop']));
    });

    test('stop is idempotent and does not re-report', () async {
      final events = <String>[];
      capture.onDebugEvent =
          ({required timestampMs, required event, dtMs, detail}) {
            events.add(event);
          };

      final sub = capture.start().listen((_) {});
      await pump();
      await capture.stop();
      await capture.stop();
      await sub.cancel();

      expect(events.where((e) => e == 'stop'), hasLength(1));
    });
  });
}
