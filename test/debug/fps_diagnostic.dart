// Debug CLI tool — printing to stdout is its entire purpose.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';
import 'package:simply_morse/features/decoding/domain/services/brightness_threshold.dart';
import 'package:simply_morse/features/decoding/domain/services/element_builder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_decoder.dart';
import 'package:simply_morse/features/decoding/domain/services/morse_lock_gate.dart';

/// Debug tool: decode one video fixture with explicit threshold
/// and decoder overrides, optionally dumping the element stream.
/// Used to sweep on/off factors and decoder thresholds per fixture.
///
///   dart test/debug/fps_diagnostic.dart NAME onF offF minT dump ditT gapT
void main(List<String> args) {
  final name = args.isNotEmpty ? args[0] : '20wpm_60fps';
  final onF = args.length > 1 ? double.parse(args[1]) : 0.75;
  final offF = args.length > 2 ? double.parse(args[2]) : 0.6;
  final minT = args.length > 3 ? int.parse(args[3]) : 33;
  final dump = args.length > 4 && args[4] == 'dump';

  final fps = name.contains('60fps') ? 60.0 : 30.0;
  final data = File(
    'test/assets/recordings/video/${name}_brightness.f32',
  ).readAsBytesSync();
  final trace = data.buffer.asFloat32List(0, data.length ~/ 4);
  final frameMs = (1000 / fps).round();

  final threshold = BrightnessThreshold(
    onFactor: onF,
    offFactor: offF,
    decayFactor: 0.995,
    minRange: 0.01,
    minTransitionMs: minT,
  );
  final elements = <DecodedElement>[];
  final gate = MorseLockGate(onElement: elements.add);
  final builder = ElementBuilder(onElement: gate.add);

  for (var i = 0; i < trace.length; i++) {
    final isOn = threshold.process(trace[i], timestampMs: i * frameMs);
    builder.transition(
      nowOn: isOn,
      timeMs: threshold.effectiveTransitionMs,
    );
  }
  builder.flush();
  gate.flush();

  if (dump) {
    for (final e in elements) {
      print('  ${e.isOn ? "ON " : "off"} ${e.durationMs}ms');
    }
  }
  final markDurs =
      elements
          .where((e) => e.isOn)
          .map((e) => e.durationMs.toDouble())
          .where((d) => d >= 8)
          .toList()
        ..sort();
  final estDit = markDurs.isEmpty
      ? 0.0
      : markDurs[(markDurs.length * 0.25).floor().clamp(
          0,
          markDurs.length - 1,
        )];
  print('  est-dit=$estDit wpm=${1200 / estDit}');
  final decoder = MorseDecoder(
    ditThreshold: args.length > 5 ? double.parse(args[5]) : 2.2,
    gapThreshold: args.length > 6 ? double.parse(args[6]) : 2.0,
  );
  final text = decoder.decodeElements(
    elements.skipWhile((e) => !e.isOn).toList(),
  );
  print('$name on=$onF off=$offF minT=$minT: "$text" (${elements.length} el)');
}
