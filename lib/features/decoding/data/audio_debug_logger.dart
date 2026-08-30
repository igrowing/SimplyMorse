import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes audio-decoder debug data to a timestamped log file.
///
/// Logs calibration FFT bins, noise-floor values, lock events,
/// IIR envelope values, and on/off transitions.
/// The log file can be shared via the share sheet for debugging.
class AudioDebugLogger {
  AudioDebugLogger({this.enabled = false});

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
    final path = '${dir.path}/morse_audio_debug_$timestamp.csv';
    _logFile = File(path);
    _sink = _logFile!.openWrite();

    // CSV header
    _writeln(
      'timestamp_ms,phase,event,freq_hz,power,envelope,'
      'noise_floor,on_threshold,off_threshold,is_on,duration_ms,detail',
    );

    // Flush every 500ms
    _flushTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _flush(),
    );
  }

  /// Logs a calibration frame.
  void logCalibration({
    required int totalSamples,
    required int sampleRate,
    required double avgPower,
    required double noiseFloor,
    required Map<int, double> binPower,
    required int calibrationFrames,
    required double elapsedMs,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    final ts = (totalSamples * 1000 / sampleRate).round();
    _writeln(
      '$ts,calibrating,fft_frame,0,$avgPower,0,$noiseFloor,0,0,0,0,'
      'frames=$calibrationFrames,elapsed_ms=${elapsedMs.round()}',
    );
    if (detail != null) {
      _writeln('$ts,calibrating,detail,0,0,0,0,0,0,0,0,$detail');
    }
  }

  /// Logs the lock event.
  void logLock({
    required int totalSamples,
    required int sampleRate,
    required double freq,
    required double bestAvgPower,
    required double noiseFloor,
    required double onThresholdFactor,
  }) {
    if (!enabled || _sink == null) return;
    final ts = (totalSamples * 1000 / sampleRate).round();
    _writeln(
      '$ts,lock,locked,${freq.round()},$bestAvgPower,0,$noiseFloor,'
      '${noiseFloor * onThresholdFactor},0,0,0,freq_locked',
    );
  }

  /// Logs a tracking frame.
  void logTracking({
    required int totalSamples,
    required int sampleRate,
    required double freq,
    required double power,
    required double envelope,
    required double noiseFloor,
    required double onThreshold,
    required double offThreshold,
    required bool isOn,
    String? detail,
  }) {
    if (!enabled || _sink == null) return;
    final ts = (totalSamples * 1000 / sampleRate).round();
    _writeln(
      '$ts,tracking,sample,${freq.round()},$power,$envelope,'
      '$noiseFloor,$onThreshold,$offThreshold,${isOn ? 1 : 0},0,'
      '${detail ?? ''}',
    );
  }

  /// Logs an on/off transition.
  void logTransition({
    required int totalSamples,
    required int sampleRate,
    required bool isOn,
    required int durationMs,
  }) {
    if (!enabled || _sink == null) return;
    final ts = (totalSamples * 1000 / sampleRate).round();
    _writeln(
      '$ts,tracking,transition,0,0,0,0,0,0,${isOn ? 1 : 0},'
      '$durationMs,${isOn ? "on_to_off" : "off_to_on"}',
    );
  }

  /// Returns the path to the current log file, if any.
  String? get logFilePath => _logFile?.path;

  /// Stops logging and flushes remaining data.
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
    for (final line in _buffer) {
      _sink!.writeln(line);
    }
    _buffer.clear();
  }
}
