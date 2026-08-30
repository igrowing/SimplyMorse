/// Turns a stream of on/off transitions into timed Morse elements.
library;

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';

/// Converts on/off transitions into [DecodedElement]s, merging
/// segments too short to be real.
///
/// Shared by the audio and video decoders so both get the same
/// treatment of glitches.
///
/// **Merging, not dropping.** A segment shorter than the glitch
/// threshold is folded into its neighbours rather than discarded.
/// Discarding it keeps the split it caused — `ON 50 / off 20 / ON 60`
/// becomes two spurious dits instead of the single `ON 130` that was
/// actually transmitted.
///
/// **A rate-relative threshold.** The threshold is a fraction of the
/// estimated dit rather than a fixed duration, because no fixed value
/// serves the whole speed range: 30 ms is a fifth of a dit at 8 WPM,
/// where it usefully absorbs noise, but half a dit at 20 WPM, where it
/// merges genuine dits into dahs.
///
/// Elements are emitted one transition late so that the segment that
/// follows a glitch can still be merged with the one before it. Call
/// [flush] at the end of a transmission to release the last element.
class ElementBuilder {
  ElementBuilder({
    required this.onElement,
    this.minElementMs = 10,
    this.glitchRatio = 0.25,
    this.maxGlitchMs = 150,
    this.historySize = 24,
  });

  /// Receives each completed element.
  final void Function(DecodedElement element) onElement;

  /// Absolute floor for the glitch threshold, used until the element
  /// rate has been estimated.
  final int minElementMs;

  /// Glitch threshold as a fraction of the estimated dit.
  final double glitchRatio;

  /// Upper bound on the glitch threshold.
  final int maxGlitchMs;

  /// How many recent mark durations feed the dit estimate.
  final int historySize;

  final List<int> _recentOnMs = [];

  bool _isOn = false;
  double _segStartMs = 0;
  bool _started = false;

  bool? _pendingIsOn;
  double _pendingStartMs = 0;
  double _pendingEndMs = 0;

  /// Whether the builder currently considers the signal on.
  bool get isOn => _isOn;

  /// Current glitch threshold in ms.
  int get glitchThresholdMs {
    final unit = currentUnitMs;
    if (unit == null) return minElementMs;
    return (unit * glitchRatio).round().clamp(minElementMs, maxGlitchMs);
  }

  /// Current dit estimate in ms — the 25th percentile of recent mark
  /// durations — or null until enough history has accumulated to
  /// trust it. Exposed (beyond [glitchThresholdMs]'s own use of it)
  /// so callers can adapt other rate-dependent behaviour, such as the
  /// depth of an on/off threshold, to the same estimate.
  int? get currentUnitMs {
    if (_recentOnMs.length < 6) return null;
    final sorted = List<int>.from(_recentOnMs)..sort();
    return sorted[(sorted.length * 0.25).floor()];
  }

  /// Records that the signal changed to [nowOn] at [timeMs].
  ///
  /// [timeMs] may be fractional — video decoders interpolate the
  /// crossing between frames.
  void transition({required bool nowOn, required double timeMs}) {
    if (!_started) {
      _started = true;
      _isOn = nowOn;
      _segStartMs = timeMs;
      return;
    }
    if (nowOn == _isOn) return;

    final segIsOn = _isOn;
    final durationMs = (timeMs - _segStartMs).round();

    if (durationMs < glitchThresholdMs && _pendingIsOn != null) {
      // Fold the glitch, and the segment it interrupted, back into the
      // pending element by reverting to the pending polarity.
      _isOn = _pendingIsOn!;
      _segStartMs = _pendingStartMs;
      _pendingIsOn = null;
      return;
    }

    _emitPending();

    if (durationMs > 0) {
      _pendingIsOn = segIsOn;
      _pendingStartMs = _segStartMs;
      _pendingEndMs = timeMs;
    }

    _isOn = nowOn;
    _segStartMs = timeMs;
  }

  /// Emits the element still held back, if any.
  void flush() => _emitPending();

  void _emitPending() {
    final isOn = _pendingIsOn;
    if (isOn == null) return;
    _pendingIsOn = null;

    final durationMs = (_pendingEndMs - _pendingStartMs).round();
    if (durationMs <= 0) return;

    if (isOn) {
      _recentOnMs.add(durationMs);
      if (_recentOnMs.length > historySize) _recentOnMs.removeAt(0);
    }

    onElement(DecodedElement(isOn: isOn, durationMs: durationMs));
  }

  /// Clears all state.
  void reset() {
    _recentOnMs.clear();
    _isOn = false;
    _segStartMs = 0;
    _started = false;
    _pendingIsOn = null;
  }
}
