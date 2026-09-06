import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Writes video-decoder debug data to a timestamped CSV file.
///
/// One row per processed frame (scanning / confirming / tracking),
/// plus rows for transitions, state changes and signal loss. The
/// schema is deliberately wide but every column carries a distinct,
/// non-derived quantity — see [_header] — so the lead-up to a lock
/// loss (previously an unlogged blind spot) is fully reconstructable
/// offline. The file can be shared via the share sheet.
class VideoDebugLogger {
  VideoDebugLogger({this.enabled = false});

  bool enabled;
  IOSink? _sink;
  File? _logFile;
  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// Rows produced before [start] finished opening the file.
  ///
  /// The camera reports the interesting part of its configuration —
  /// which frame rate it actually granted, whether high-speed mode
  /// was available, the exposure mode — while it initialises, and
  /// that races [start]'s asynchronous file open. Dropping those rows
  /// (the previous behaviour) meant not one `capture` row appeared in
  /// any field log, leaving the achieved frame rate unknowable
  /// exactly when a 16 WPM decode was failing for want of frames.
  final List<String> _preStart = [];

  /// Cap on [_preStart], so a session with logging enabled but never
  /// started cannot grow it without bound.
  static const int _maxPreStartRows = 64;

  /// Column order for every row. Fields that don't apply to a given
  /// event are left blank rather than zero-filled, so a spreadsheet
  /// filter on, say, `held=1` isn't polluted by scanning rows.
  static const _header =
      'timestamp_ms,frame_idx,dt_ms,phase,event,'
      'pred_x,pred_y,meas_x,meas_y,vel_x,vel_y,innovation,'
      'search_var,min_var,peak_bx,peak_by,win,blocks_above_floor,weight_sum,'
      'raw_bright,annulus,brightness,b_min,b_max,on_thr,off_thr,'
      'is_on,reg_x,reg_y,reg_size,full_frame,held,lost_cnt,'
      'dit_ms,wpm,dur_ms,seq,detail';

  /// Number of data columns before `detail` — used to pad short
  /// rows so `detail` always lands in the same column.
  static const _columnCount = 38;

  /// Starts a new log session.
  Future<void> start() async {
    if (!enabled) return;
    await stop();

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${dir.path}/morse_video_debug_$timestamp.csv';
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

  /// Logs a camera capture lifecycle event: init attempts,
  /// frame-rate fallbacks, exposure mode, and periodic measured
  /// frame rates.
  void logCapture({
    required int timestampMs,
    required String event,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      phase: 'capture',
      event: event,
      detail: detail,
    );
  }

  void logScanning({
    required int timestampMs,
    required int frameIndex,
    required int dtMs,
    required double maxVariance,
    required double meanVariance,
    required double minVariance,
    required int frameCount,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: frameIndex,
      dtMs: dtMs,
      phase: 'scanning',
      event: 'variance',
      searchVar: maxVariance,
      minVar: minVariance,
      detail:
          'mean_var=${_f(meanVariance, 6)} frames=$frameCount'
          '${detail == null ? '' : ' $detail'}',
    );
  }

  void logConfirming({
    required int timestampMs,
    required int frameIndex,
    required int dtMs,
    required double variance,
    required double minVariance,
    required int confirmCount,
    required double predictedX,
    required double predictedY,
    required double measuredX,
    required double measuredY,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: frameIndex,
      dtMs: dtMs,
      phase: 'confirming',
      event: 'variance',
      predX: predictedX,
      predY: predictedY,
      measX: measuredX,
      measY: measuredY,
      searchVar: variance,
      minVar: minVariance,
      detail: 'confirm_count=$confirmCount${detail == null ? '' : ' $detail'}',
    );
  }

  void logTracking({
    required int timestampMs,
    required int frameIndex,
    required int dtMs,
    required double searchVariance,
    required double minVariance,
    required int lostFrameCount,
    required bool held,
    required bool isFullFrame,
    required double predictedX,
    required double predictedY,
    required double measuredX,
    required double measuredY,
    required double velocityX,
    required double velocityY,
    required double innovation,
    required int peakBx,
    required int peakBy,
    required int winMinBx,
    required int winMaxBx,
    required int winMinBy,
    required int winMaxBy,
    required int blocksAboveFloor,
    required double weightSum,
    required double rawBrightness,
    required double annulusBrightness,
    required double brightness,
    required double minBrightness,
    required double maxBrightness,
    required double onThreshold,
    required double offThreshold,
    required bool isOn,
    required int regionX,
    required int regionY,
    required int regionSize,
    required double ditEstimateMs,
    required int wpm,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: frameIndex,
      dtMs: dtMs,
      phase: 'tracking',
      event: held ? 'hold' : 'sample',
      predX: predictedX,
      predY: predictedY,
      measX: measuredX,
      measY: measuredY,
      velX: velocityX,
      velY: velocityY,
      innovation: innovation,
      searchVar: searchVariance,
      minVar: minVariance,
      peakBx: peakBx,
      peakBy: peakBy,
      win: '$winMinBx-$winMaxBx:$winMinBy-$winMaxBy',
      blocksAboveFloor: blocksAboveFloor,
      weightSum: weightSum,
      rawBright: rawBrightness,
      annulus: annulusBrightness,
      brightness: brightness,
      bMin: minBrightness,
      bMax: maxBrightness,
      onThr: onThreshold,
      offThr: offThreshold,
      isOn: isOn,
      regX: regionX,
      regY: regionY,
      regSize: regionSize,
      fullFrame: isFullFrame,
      held: held,
      lostCnt: lostFrameCount,
      ditMs: ditEstimateMs,
      wpm: wpm,
    );
  }

  void logTransition({
    required int timestampMs,
    required int frameIndex,
    required bool isOn,
    required int durationMs,
    required int sequence,
    required double effectiveTransitionMs,
    required double edgeMs,
    required double ditEstimateMs,
    required int wpm,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: frameIndex,
      phase: 'tracking',
      event: 'transition',
      isOn: isOn,
      durMs: durationMs,
      seq: sequence,
      ditMs: ditEstimateMs,
      wpm: wpm,
      detail:
          '${isOn ? "on_to_off" : "off_to_on"} '
          'effective_ms=${_f(effectiveTransitionMs, 1)} '
          'edge_ms=${_f(edgeMs, 1)}',
    );
  }

  void logSignalLost({
    required int timestampMs,
    required int frameIndex,
    required int lostFrameCount,
    required int heldForMs,
    required double lastSearchVariance,
    required double minVariance,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: frameIndex,
      phase: 'tracking',
      event: 'signal_lost',
      searchVar: lastSearchVariance,
      minVar: minVariance,
      lostCnt: lostFrameCount,
      detail: 'held_for_ms=$heldForMs',
    );
  }

  void logStateChange({
    required int timestampMs,
    required String newState,
    String? detail,
  }) {
    _emit(
      timestampMs: timestampMs,
      frameIndex: _lastFrameIndex,
      phase: 'state_change',
      event: newState,
      detail: detail,
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

  // -- Row assembly --------------------------------------------------

  int _lastFrameIndex = 0;

  static String _f(double v, int digits) {
    if (v.isNaN || v.isInfinite) return '';
    return v.toStringAsFixed(digits);
  }

  static String _b(bool? v) => v == null ? '' : (v ? '1' : '0');

  static String _i(int? v) => v?.toString() ?? '';

  /// Assembles and buffers one CSV row. Every field is optional;
  /// omitted fields render as an empty cell. Column order here must
  /// match [_header] exactly.
  void _emit({
    required int timestampMs,
    required String phase,
    int? frameIndex,
    int? dtMs,
    String? event,
    double? predX,
    double? predY,
    double? measX,
    double? measY,
    double? velX,
    double? velY,
    double? innovation,
    double? searchVar,
    double? minVar,
    int? peakBx,
    int? peakBy,
    String? win,
    int? blocksAboveFloor,
    double? weightSum,
    double? rawBright,
    double? annulus,
    double? brightness,
    double? bMin,
    double? bMax,
    double? onThr,
    double? offThr,
    bool? isOn,
    int? regX,
    int? regY,
    int? regSize,
    bool? fullFrame,
    bool? held,
    int? lostCnt,
    double? ditMs,
    int? wpm,
    int? durMs,
    int? seq,
    String? detail,
  }) {
    if (!enabled) return;
    if (frameIndex != null) _lastFrameIndex = frameIndex;

    final fields = <String>[
      '$timestampMs',
      _i(frameIndex),
      _i(dtMs),
      phase,
      event ?? '',
      _f(predX ?? double.nan, 2),
      _f(predY ?? double.nan, 2),
      _f(measX ?? double.nan, 2),
      _f(measY ?? double.nan, 2),
      _f(velX ?? double.nan, 1),
      _f(velY ?? double.nan, 1),
      _f(innovation ?? double.nan, 2),
      _f(searchVar ?? double.nan, 6),
      _f(minVar ?? double.nan, 6),
      _i(peakBx),
      _i(peakBy),
      win ?? '',
      _i(blocksAboveFloor),
      _f(weightSum ?? double.nan, 4),
      _f(rawBright ?? double.nan, 4),
      _f(annulus ?? double.nan, 4),
      _f(brightness ?? double.nan, 4),
      _f(bMin ?? double.nan, 4),
      _f(bMax ?? double.nan, 4),
      _f(onThr ?? double.nan, 4),
      _f(offThr ?? double.nan, 4),
      _b(isOn),
      _i(regX),
      _i(regY),
      _i(regSize),
      _b(fullFrame),
      _b(held),
      _i(lostCnt),
      _f(ditMs ?? double.nan, 0),
      _i(wpm),
      _i(durMs),
      _i(seq),
      (detail ?? '').replaceAll(',', ';'),
    ];
    assert(
      fields.length == _columnCount,
      'row has ${fields.length} fields, header has $_columnCount',
    );
    final row = fields.join(',');
    if (_sink == null) {
      // Not started yet — hold the row so start() can write it out.
      _preStart.add(row);
      if (_preStart.length > _maxPreStartRows) _preStart.removeAt(0);
      return;
    }
    _writeln(row);
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
