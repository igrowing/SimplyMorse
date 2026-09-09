import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/data/audio_debug_logger.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('audio_debug_log_test');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  Future<AudioDebugLogger> makeLogger() async {
    final logger = AudioDebugLogger(
      enabled: true,
      directoryProvider: () async => tempDir,
    );
    await logger.start();
    addTearDown(logger.stop);
    return logger;
  }

  Future<List<String>> readRows(AudioDebugLogger logger) async {
    await logger.stop();
    final file = File(logger.logFilePath!);
    final lines = await file.readAsLines();
    return lines;
  }

  group('AudioDebugLogger', () {
    test('writes the header row on start', () async {
      final logger = await makeLogger();
      final rows = await readRows(logger);

      expect(rows.length, 1);
      expect(rows.first.split(',').first, 'timestamp_ms');
      expect(rows.first, contains('concentration'));
      expect(rows.first, contains('frames_since_det'));
      expect(
        rows.first.split(',').length,
        // 35 data columns + detail
        36,
      );
    });

    test('every row has the same column count as the header', () async {
      final logger = await makeLogger();
      logger.logCapture(timestampMs: 1000, event: 'permission');
      logger.logScanning(
        timestampMs: 1050,
        frameIdx: 3,
        dominantBin: 22,
        dominantFreqHz: 687.5,
        dominantPower: 1.5,
        avgOtherPower: 0.2,
        snr: 7.5,
        concentration: 0.82,
        noiseFloor: 0.19,
        runLen: 4,
        runBin: 22,
        runFreqHz: 687.5,
        detectionCount: 1,
        framesSinceDetection: -1,
        monotonic: true,
        locked: false,
      );
      logger.logTracking(
        timestampMs: 2000,
        blockIdx: 9,
        freqHz: 700,
        env: 0.4,
        envDb: -8,
        markDb: -5,
        spaceDb: -40,
        thresholdDb: -20,
        onThrDb: -17.5,
        offThrDb: -22.5,
        separationDb: 35,
        isReady: true,
        wantOn: true,
        isOn: false,
        ditMs: 100,
        wpm: 12,
        profile: 'normal',
      );
      logger.logUnlock(
        timestampMs: 3000,
        reason: 'signal_timeout',
        blockIdx: 45,
      );
      final rows = await readRows(logger);

      expect(rows.length, 5); // header + 4 events
      final headerCols = rows.first.split(',').length;
      for (final row in rows.skip(1)) {
        expect(row.split(',').length, headerCols, reason: row);
      }
    });

    test('phases and events land in their columns', () async {
      final logger = await makeLogger();
      logger.logLock(
        timestampMs: 1234,
        freqHz: 700.1,
        interpFreqHz: 700.1,
        bin: 22,
        bestAvgPower: 2.5,
        noiseFloor: 0.3,
        onThresholdFactor: 4,
        path: 'long_tone',
      );
      final rows = await readRows(logger);

      final cells = rows[1].split(',');
      expect(cells[0], '1234'); // timestamp_ms
      expect(cells[1], 'lock'); // phase
      expect(cells[2], 'locked'); // event
      expect(cells[6], '700.1'); // freq_hz
      expect(cells[7], '22'); // bin
      expect(cells[35], 'path=long_tone on_thr_factor=4.0'); // detail
    });

    test('omitted fields render as empty cells, not zeros', () async {
      final logger = await makeLogger();
      logger.logCapture(timestampMs: 100, event: 'stop');
      final rows = await readRows(logger);

      final cells = rows[1].split(',');
      expect(cells[5], ''); // seq
      expect(cells[11], ''); // snr
      expect(cells[31], ''); // dit_ms
      expect(cells[34], ''); // profile
    });

    test('NaN values render blank, not "NaN"', () async {
      final logger = await makeLogger();
      logger.logTracking(
        timestampMs: 500,
        blockIdx: 1,
        freqHz: 700,
        env: 0.5,
        envDb: double.nan,
        markDb: null,
        spaceDb: null,
        thresholdDb: 0,
        onThrDb: 0,
        offThrDb: 0,
        separationDb: 0,
        isReady: false,
        wantOn: false,
        isOn: false,
        ditMs: null,
        wpm: null,
        profile: 'default',
      );
      final rows = await readRows(logger);

      final cells = rows[1].split(',');
      expect(cells[21], ''); // env_db blank for NaN
      expect(cells[22], ''); // mark_db blank for null
      expect(cells[28], '0'); // is_ready renders 0
    });

    test('disabled logger drops rows silently', () async {
      final logger = AudioDebugLogger(
        enabled: false,
        directoryProvider: () async => tempDir,
      );
      await logger.start();

      logger.logCapture(timestampMs: 1, event: 'stop');
      expect(logger.logFilePath, isNull);
    });

    test('pre-start rows are buffered and flushed into the file', () async {
      final logger = AudioDebugLogger(
        enabled: true,
        directoryProvider: () async => tempDir,
      );
      // Events before start() completes the async file open.
      logger.logCapture(timestampMs: 10, event: 'permission');
      logger.logCapture(timestampMs: 20, event: 'start');
      await logger.start();
      addTearDown(logger.stop);

      final rows = await readRows(logger);
      expect(rows.length, 3); // header + 2 buffered rows
      expect(rows[1].split(',')[2], 'permission');
      expect(rows[2].split(',')[2], 'start');
    });
  });

  group('DebugAudioCaptureEventCallback', () {
    test('accepts dtMs and detail', () async {
      // Compile-level check that the wiring in injection.dart
      // (capture events → logCapture) can carry the wall-clock dt.
      DebugAudioCaptureEventCallback? captured;
      captured = ({required timestampMs, required event, dtMs, detail}) {
        expect(timestampMs, 100);
        expect(event, 'buffer');
        expect(dtMs, 25);
        expect(detail, 'n=1 bytes=2');
      };
      captured(
        timestampMs: 100,
        event: 'buffer',
        dtMs: 25,
        detail: 'n=1 bytes=2',
      );
    });
  });
}
