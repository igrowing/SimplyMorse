@Tags(['field-logs'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

import 'cer.dart';

/// Replays the `brightness` column of on-device debug CSVs through
/// the real threshold → element-builder → lock-gate → decoder chain.
///
/// The committed scoreboard fixtures are clean pre-recorded brightness
/// traces; these are whole *sessions* captured from a phone, junk
/// prefix and all, including one recorded with nothing transmitting at
/// all. That last case is the point: it is the only fixture that
/// measures false-positive output, which no clean fixture can.
///
/// Drop `<prefix>*.csv` files in the project root and run:
///   flutter test --tags field-logs test/support/field_log_replay_test.dart
/// Skips silently when the logs aren't present, since they are
/// developer captures rather than committed fixtures.
void main() {
  test('field log replay', () {
    const expectations = <String, String>{
      'no_morse': '',
      '8wpm_2times': 'HELLO, WORLD! HELLO, WORLD!',
      '16wpm_2_times': 'HELLO, WORLD! HELLO, WORLD!',
    };

    var totalErr = 0;
    var totalLen = 0;
    var found = 0;
    final report = <String>[];

    for (final entry in expectations.entries) {
      final path = _findLog(entry.key);
      if (path == null) continue;
      found++;

      final rows = _rows(path);
      final produced = <DecodedElement>[];
      final emitted = <DecodedElement>[];

      // Mirror VideoDecoder's lifecycle: the threshold, builder and
      // gate are reset on every lock and released on every signal
      // loss, so a session with several lock/loss cycles must be
      // replayed as several independent segments — replaying it as
      // one stream hides exactly the junk this harness exists to see.
      var threshold = BrightnessThreshold();
      var gate = MorseLockGate(onElement: emitted.add);
      var builder = ElementBuilder(
        onElement: (e) {
          produced.add(e);
          gate.add(e);
        },
      );

      for (final row in rows) {
        switch (row.kind) {
          case _RowKind.locked:
            threshold = BrightnessThreshold();
            gate = MorseLockGate(onElement: emitted.add);
            builder = ElementBuilder(
              onElement: (e) {
                produced.add(e);
                gate.add(e);
              },
            );
          case _RowKind.signalLost:
            builder.flush();
            gate.releaseOnSignalLoss();
          case _RowKind.sample:
            final isOn = threshold.process(
              row.brightness,
              timestampMs: row.timestampMs,
            );
            builder.transition(
              nowOn: isOn,
              timeMs: threshold.effectiveTransitionMs,
            );
        }
      }
      builder.flush();
      gate.flush();

      final text = MorseDecoder().decodeElements(
        emitted.skipWhile((e) => !e.isOn).toList(),
      );
      final err = editDistance(text, entry.value);
      totalErr += err;
      // A no-signal fixture has no length to normalise against, so
      // every character it emits counts as one error out of one.
      totalLen += entry.value.isEmpty ? text.length : entry.value.length;

      report.add(
        '  ${entry.key.padRight(14)} '
        'built=${produced.length.toString().padLeft(3)} '
        'emitted=${emitted.length.toString().padLeft(3)} '
        'err=${err.toString().padLeft(3)} "$text"',
      );
    }

    if (found == 0) {
      // ignore_for_file: avoid_print — this suite prints a scoreboard.
      print('  (no field logs in project root — skipped)');
      return;
    }
    report.forEach(print);
    print('  ══ FIELD TOTAL err=$totalErr/$totalLen');
  });
}

/// Newest `<prefix>*.csv` in the project root, or null if absent.
String? _findLog(String prefix) {
  final matches =
      Directory('.')
          .listSync()
          .whereType<File>()
          .where(
            (f) =>
                f.uri.pathSegments.last.startsWith(prefix) &&
                f.path.endsWith('.csv'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return matches.isEmpty ? null : matches.last.path;
}

/// What a replayed CSV row asks the pipeline to do.
enum _RowKind { locked, signalLost, sample }

class _Row {
  const _Row(this.kind, this.timestampMs, this.brightness);
  final _RowKind kind;
  final int timestampMs;
  final double brightness;
}

/// The lock lifecycle and brightness samples of a debug CSV, in order.
List<_Row> _rows(String path) {
  final out = <_Row>[];
  final lines = File(path).readAsLinesSync();
  final head = lines.first.split(',');
  final iTs = head.indexOf('timestamp_ms');
  final iPhase = head.indexOf('phase');
  final iEvent = head.indexOf('event');
  final iBright = head.indexOf('brightness');
  for (final line in lines.skip(1)) {
    final f = line.split(',');
    if (f.length <= iBright) continue;
    final ts = int.tryParse(f[iTs]);
    if (ts == null) continue;
    if (f[iPhase] == 'state_change' && f[iEvent] == 'locked') {
      out.add(_Row(_RowKind.locked, ts, 0));
      continue;
    }
    if (f[iPhase] == 'tracking' && f[iEvent] == 'signal_lost') {
      out.add(_Row(_RowKind.signalLost, ts, 0));
      continue;
    }
    if (f[iPhase] != 'tracking') continue;
    if (f[iEvent] != 'sample' && f[iEvent] != 'hold') continue;
    final b = double.tryParse(f[iBright]);
    if (b == null) continue;
    out.add(_Row(_RowKind.sample, ts, b));
  }
  return out;
}
