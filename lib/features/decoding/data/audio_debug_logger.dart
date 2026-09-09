import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes audio-decoder debug data to a timestamped CSV file.
///
/// Follows the video debug logger's methodology that made offline
/// video debugging work:
///
/// - One wide, FIXED-schema CSV — every stage (capture, scanning,
///   lock, tracking, transitions, glitch merges, unlock) lands in
///   the same file, so a decode failure can be reconstructed
///   offline end-to-end.
/// - Every column carries a distinct, non-derived quantity;
///   fields that don't apply to a given event are left blank, not
///   zero-filled, so spreadsheet filters aren't polluted.
/// - Consistent units per column: dB columns hold dB, linear
///   columns hold linear. (The previous audio schema mixed a dB
///   mark level into a `noise_floor` column and a linear envelope
///   into `power` — misleading both.) Two envelope columns exist
///   by design: `env` is the raw IIR envelope (linear), `env_db`
///   its dB-domain form that shares a scale with the level-tracker
///   columns.
/// - Rows produced before [start] finished opening the file are
///   buffered (bounded) so capture-init events — which race the
///   asynchronous file open exactly like the camera's do — are not
///   lost.
///
/// Timestamps: decoder rows use *content time* (ms derived from
/// total samples — the same clock as the emitted elements); capture
/// rows use *wall time* (ms since epoch), since they report the
/// recorder's delivery cadence. Offline analysis distinguishes them
/// by phase. The file can be shared via the share sheet.
class AudioDebugLogger {
  /// Test seam for the documents directory; production uses
  /// [getApplicationDocumentsDirectory].
  AudioDebugLogger({
    this.enabled = false,
    Future<Directory> Function()? directoryProvider,
  }) : _directoryProvider =
           directoryProvider ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directoryProvider;

  bool enabled;
  IOSink? _sink;
  File? _logFile;
  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// Rows produced before [start] finished opening the file.
  /// The recorder reports its configuration while the file open
  /// is still awaited; dropping those rows (the previous
  /// behaviour) hid the sample-rate and permission facts exactly
  /// when a session was failing at startup.
  final List<String> _preStart = [];

  /// Cap on [_preStart] so a logging-enabled session that never
  /// starts cannot grow it without bound.
  static const int _maxPreStartRows = 64;

  /// Column order for every row — see the class docs on units.
  static const _header =
      'timestamp_ms,phase,event,idx,dt_ms,seq,'
      'freq_hz,bin,interp_freq_hz,power,avg_other_power,snr,concentration,'
      'noise_floor,'
      'run_len,run_bin,run_freq_hz,detection_count,frames_since_det,monotonic,'
      'env,env_db,mark_db,space_db,threshold_db,on_thr_db,off_thr_db,'
      'separation_db,is_ready,want_on,is_on,'
      'dit_ms,wpm,profile,dur_ms,detail';

  /// Number of data columns before `detail` — used to pad short
  /// rows so `detail` always lands in the same column.
  static const _columnCount = 35;

  /// Starts a new log session.
  Future<void> start() async {
    if (!enabled) return;
    await stop();

    final dir = await _directoryProvider();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${dir.path}/morse_audio_debug_$timestamp.csv';
    _logFile = File(path);
    _sink = _logFile!.openWrite();

    _writeln(_header);
    _preStart
      ..forEach(_writeln)
      ..clear();

    _flushTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _flush(),
    );
  }

  /// Logs a recorder lifecycle event: permission, start
  /// configuration, buffer arrivals (with wall-clock dt), and
  /// stop. Buffer rows make sample drops and stream stalls visible
  /// as timeline holes — problems the decoder itself cannot see.
  void logCapture({
    required int timestampMs,
    required String event,
    int? dtMs,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'capture',
      event: event,
      dtMs: dtMs,
      detail: detail,
    );
  }

  /// Logs one FFT scanning frame with the full monotonic-lock-gate
  /// state — the spectral-concentration check in particular is the
  /// main voice/noise rejector and was previously never logged.
  void logScanning({
    required int timestampMs,
    required int frameIdx,
    required int dominantBin,
    required double dominantFreqHz,
    required double dominantPower,
    required double avgOtherPower,
    required double snr,
    required double concentration,
    required double noiseFloor,
    required int runLen,
    required int runBin,
    required double runFreqHz,
    required int detectionCount,
    required int framesSinceDetection,
    required bool monotonic,
    required bool locked,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'scanning',
      event: 'sample',
      idx: frameIdx,
      freqHz: dominantFreqHz,
      bin: dominantBin,
      power: dominantPower,
      avgOtherPower: avgOtherPower,
      snr: snr,
      concentration: concentration,
      noiseFloor: noiseFloor,
      runLen: runLen,
      runBin: runBin,
      runFreqHz: runFreqHz,
      detectionCount: detectionCount,
      framesSinceDet: framesSinceDetection,
      monotonic: monotonic,
      detail: locked ? 'locked${detail == null ? '' : ' $detail'}' : detail,
    );
  }

  /// Logs a completed monotonic run that counted as a detection
  /// (long enough to count as a detection) — the repeat-criterion
  /// bookkeeping that decides whether a second/third sighting of
  /// the same frequency triggers a lock.
  void logDetection({
    required int timestampMs,
    required int frameIdx,
    required int runBin,
    required double runFreqHz,
    required int runLenFrames,
    required double runMs,
    required int detectionCount,
    required int gapFrames,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'scanning',
      event: 'detection',
      idx: frameIdx,
      runLen: runLenFrames,
      runBin: runBin,
      runFreqHz: runFreqHz,
      detectionCount: detectionCount,
      detail: 'run_ms=${_f(runMs, 1)} gap_frames=$gapFrames',
    );
  }

  /// Logs the lock event, including WHICH criterion fired
  /// ([path]: long_tone or repeats), the raw FFT bin versus the
  /// parabolic-interpolated frequency, and the real noise floor
  /// (the previous schema hardcoded 0 here).
  void logLock({
    required int timestampMs,
    required double freqHz,
    required double interpFreqHz,
    required int bin,
    required double bestAvgPower,
    required double noiseFloor,
    required double onThresholdFactor,
    required String path,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'lock',
      event: 'locked',
      freqHz: freqHz,
      interpFreqHz: interpFreqHz,
      bin: bin,
      power: bestAvgPower,
      noiseFloor: noiseFloor,
      detail: 'path=$path on_thr_factor=${_f(onThresholdFactor, 1)}',
    );
  }

  /// Logs the pre-lock replay: how much audio was re-decoded,
  /// the mark/space levels it seeded, and the keying-speed
  /// estimate that picked the level-tracking profile.
  void logReplay({
    required int timestampMs,
    required int blocks,
    required int windowMs,
    required double? markDb,
    required double? spaceDb,
    required int? ditEstimateMs,
    required String profile,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'lock',
      event: 'replay',
      markDb: markDb,
      spaceDb: spaceDb,
      ditMs: ditEstimateMs,
      profile: profile,
      detail:
          'window_ms=$windowMs blocks=$blocks'
          '${detail == null ? '' : ' $detail'}',
    );
  }

  /// Logs one tracking block with the full level-tracker state,
  /// all in dB, plus the live dit/WPM estimate and profile.
  void logTracking({
    required int timestampMs,
    required int blockIdx,
    required double freqHz,
    required double env,
    required double envDb,
    required double? markDb,
    required double? spaceDb,
    required double thresholdDb,
    required double onThrDb,
    required double offThrDb,
    required double separationDb,
    required bool isReady,
    required bool wantOn,
    required bool isOn,
    required int? ditMs,
    required int? wpm,
    required String profile,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'tracking',
      event: 'sample',
      idx: blockIdx,
      freqHz: freqHz,
      env: env,
      envDb: envDb,
      markDb: markDb,
      spaceDb: spaceDb,
      thresholdDb: thresholdDb,
      onThrDb: onThrDb,
      offThrDb: offThrDb,
      separationDb: separationDb,
      isReady: isReady,
      wantOn: wantOn,
      isOn: isOn,
      ditMs: ditMs,
      wpm: wpm,
      profile: profile,
      detail: detail,
    );
  }

  /// Logs a completed element with its sequence number and the
  /// dit/WPM estimate in force when it was emitted.
  void logTransition({
    required int timestampMs,
    required int blockIdx,
    required bool isOn,
    required int durationMs,
    required int seq,
    required int? ditMs,
    required int? wpm,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'tracking',
      event: 'transition',
      idx: blockIdx,
      isOn: isOn,
      durMs: durationMs,
      seq: seq,
      ditMs: ditMs,
      wpm: wpm,
    );
  }

  /// Logs a glitch merge: a segment shorter than the glitch
  /// threshold folded back into its neighbours instead of
  /// splitting them. Without this row the merge is invisible —
  /// the element stream just shows fewer transitions.
  void logGlitchMerge({
    required int timestampMs,
    required int blockIdx,
    required int absorbedMs,
    required int thresholdMs,
    required bool intoOn,
    required int? ditMs,
    required int? wpm,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'tracking',
      event: 'glitch_merge',
      idx: blockIdx,
      durMs: absorbedMs,
      ditMs: ditMs,
      wpm: wpm,
      detail:
          'into=${intoOn ? 'on' : 'off'} '
          'thr_ms=$thresholdMs',
    );
  }

  /// Logs one periodic re-tune check while tracking: what the
  /// dominant frequency was, how much power remained at the
  /// locked frequency, and whether the check triggered an unlock.
  void logRetuneCheck({
    required int timestampMs,
    required int blockIdx,
    required double dominantFreqHz,
    required double dominantPower,
    required double lockedFreqHz,
    required double lockedPower,
    required double avgOtherPower,
    required bool unlocked,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'tracking',
      event: 'retune_check',
      idx: blockIdx,
      freqHz: dominantFreqHz,
      power: dominantPower,
      avgOtherPower: avgOtherPower,
      detail:
          'locked_freq_hz=${lockedFreqHz.round()} '
          'locked_power=${_f(lockedPower, 6)} '
          'unlocked=${unlocked ? 1 : 0}',
    );
  }

  /// Logs the decoder returning to scanning, with the real
  /// content-time timestamp and a machine-readable reason.
  void logUnlock({
    required int timestampMs,
    required String reason,
    int? blockIdx,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'unlock',
      event: reason,
      idx: blockIdx,
      detail: detail,
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

  // -- Row assembly ------------------------------------------------

  static String _f(double? v, int digits) {
    if (v == null || v.isNaN || v.isInfinite) return '';
    return v.toStringAsFixed(digits);
  }

  static String _i(int? v) => v?.toString() ?? '';

  static String _b(bool? v) => v == null ? '' : (v ? '1' : '0');

  /// Assembles and buffers one CSV row. Every field is optional;
  /// omitted fields render as an empty cell. Column order here
  /// must match [_header] exactly.
  void _emit({
    required int timestampMs,
    required String phase,
    String? event,
    int? idx,
    int? dtMs,
    int? seq,
    double? freqHz,
    int? bin,
    double? interpFreqHz,
    double? power,
    double? avgOtherPower,
    double? snr,
    double? concentration,
    double? noiseFloor,
    int? runLen,
    int? runBin,
    double? runFreqHz,
    int? detectionCount,
    int? framesSinceDet,
    bool? monotonic,
    double? env,
    double? envDb,
    double? markDb,
    double? spaceDb,
    double? thresholdDb,
    double? onThrDb,
    double? offThrDb,
    double? separationDb,
    bool? isReady,
    bool? wantOn,
    bool? isOn,
    int? ditMs,
    int? wpm,
    String? profile,
    int? durMs,
    String? detail,
  }) {
    if (!enabled) return;

    final cells = <String>[
      _i(timestampMs),
      phase,
      event ?? '',
      _i(idx),
      _i(dtMs),
      _i(seq),
      _f(freqHz, 1),
      _i(bin),
      _f(interpFreqHz, 2),
      _f(power, 6),
      _f(avgOtherPower, 6),
      _f(snr, 2),
      _f(concentration, 3),
      _f(noiseFloor, 6),
      _i(runLen),
      _i(runBin),
      _f(runFreqHz, 1),
      _i(detectionCount),
      _i(framesSinceDet),
      _b(monotonic),
      _f(env, 6),
      _f(envDb, 2),
      _f(markDb, 2),
      _f(spaceDb, 2),
      _f(thresholdDb, 2),
      _f(onThrDb, 2),
      _f(offThrDb, 2),
      _f(separationDb, 2),
      _b(isReady),
      _b(wantOn),
      _b(isOn),
      _i(ditMs),
      _i(wpm),
      profile ?? '',
      _i(durMs),
      detail ?? '',
    ];
    assert(cells.length == _columnCount + 1, 'column drift');

    final line = cells.join(',');
    if (_sink != null) {
      _buffer.add(line);
    } else if (_preStart.length < _maxPreStartRows) {
      _preStart.add(line);
    }
  }

  void _writeln(String line) {
    _sink?.writeln(line);
  }

  void _flush() {
    if (_buffer.isEmpty || _sink == null) return;
    _buffer
      ..forEach(_sink!.writeln)
      ..clear();
  }
}
