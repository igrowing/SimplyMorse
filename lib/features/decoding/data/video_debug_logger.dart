import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes video-decoder debug data to a timestamped log file.
///
/// Logs scanning variance, confirming state, locked brightness
/// readings, threshold values, and on/off transitions.
/// The log file can be shared via the share sheet for debugging.
class VideoDebugLogger {
  VideoDebugLogger({this.enabled = false});

  bool enabled;
  IOSink? _sink;
  File? _logFile;
  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// Starts a new log session.
  Future<void> start() async {
    if (!enabled) return;
    await stop();

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${dir.path}/morse_video_debug_$timestamp.csv';
    _logFile = File(path);
    _sink = _logFile!.openWrite();

    _writeln(
      'timestamp_ms,phase,event,region_x,region_y,region_size,'
      'variance,brightness,min_brightness,max_brightness,'
      'range,on_threshold,off_threshold,is_on,duration_ms,detail',
    );

    _flushTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _flush(),
    );
  }

  /// Logs a camera capture lifecycle event: init attempts,
  /// frame-rate fallbacks, exposure mode, and periodic measured
  /// frame rates.
  void logCapture({
    required int timestampMs,
    required String event,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,capture,$event,0,0,0,0,0,0,0,0,0,0,0,0,'
      '${detail ?? ''}',
    );
  }

  void logScanning({
    required int timestampMs,
    required double maxVariance,
    required double meanVariance,
    required int frameCount,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,scanning,variance,0,0,0,'
      '$maxVariance,0,0,0,0,0,0,0,0,'
      'mean_var=$meanVariance,frames=$frameCount,${detail ?? ''}',
    );
  }

  void logConfirming({
    required int timestampMs,
    required double variance,
    required int confirmCount,
    required double filterX,
    required double filterY,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,confirming,variance,${filterX.round()},'
      '${filterY.round()},0,$variance,0,0,0,0,0,0,0,0,'
      'confirm_count=$confirmCount,${detail ?? ''}',
    );
  }

  void logTracking({
    required int timestampMs,
    required double variance,
    required double brightness,
    required double minBrightness,
    required double maxBrightness,
    required double range,
    required double onThreshold,
    required double offThreshold,
    required bool isOn,
    required int regionX,
    required int regionY,
    required int regionSize,
    required double innovation,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,tracking,sample,$regionX,$regionY,$regionSize,'
      '$variance,$brightness,$minBrightness,$maxBrightness,'
      '$range,$onThreshold,$offThreshold,${isOn ? 1 : 0},0,'
      'innovation=${innovation.toStringAsFixed(2)},${detail ?? ''}',
    );
  }

  void logTransition({
    required int timestampMs,
    required bool isOn,
    required int durationMs,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,tracking,transition,0,0,0,'
      '0,0,0,0,0,0,0,${isOn ? 1 : 0},$durationMs,'
      '${isOn ? "on_to_off" : "off_to_on"}',
    );
  }

  void logSignalLost({
    required int timestampMs,
    required int lostFrameCount,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,tracking,signal_lost,0,0,0,'
      '0,0,0,0,0,0,0,0,0,lost_frames=$lostFrameCount',
    );
  }

  void logStateChange({
    required int timestampMs,
    required String newState,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    _writeln(
      '$timestampMs,state_change,$newState,0,0,0,'
      '0,0,0,0,0,0,0,0,0,${detail ?? ''}',
    );
  }

  String? get logFilePath => _logFile?.path;

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _flush();
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  void _writeln(String line) {
    if (_sink != null) {
      _buffer.add(line);
    }
  }

  void _flush() {
    if (_buffer.isEmpty || _sink == null) return;
    _buffer
      ..forEach(_sink!.writeln)
      ..clear();
  }
}
