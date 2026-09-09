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
    this.onMerge,
    this.minElementMs = 10,
    this.glitchRatio = 0.25,
    this.maxGlitchMs = 150,
    this.historySize = 24,
  });

  /// Receives each completed element.
  final void Function(DecodedElement element) onElement;

  /// Optional hook fired whenever a segment shorter than the
  /// glitch threshold is folded back into its neighbours:
  /// `absorbedMs` = duration of the absorbed segment,
  /// `intoOn` = polarity of the element it merged back into.
  ///
  /// Debug instrumentation only — decoding behaviour is identical
  /// when null. Merges are otherwise invisible from the emitted
  /// element stream, which just shows fewer transitions.
  final void Function({required int absorbedMs, required bool intoOn})? onMerge;

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

  /// Last committed unit estimate — updated when a mark element is
  /// emitted, read by [currentUnitMs]. Null until [historySize]
  /// bootstrap marks have accumulated. Kept as a field so the
  /// getter stays pure while the estimate changes only on real
  /// evidence (a completed mark).
  int? _lastUnitMs;

  bool _isOn = false;
  double _segStartMs = 0;
  bool _started = false;

  bool? _pendingIsOn;
  double _pendingStartMs = 0;
  double _pendingEndMs = 0;

  /// Whether the builder currently considers the signal on.
  bool get isOn => _isOn;

  /// Raw 25th-percentile unit — the historical running estimate,
  /// kept for [glitchThresholdMs]. Merging behaviour was tuned
  /// against this value (which, unlike the hardened estimate,
  /// includes dahs in its sample and so reads ~20% high at dit/dah
  /// ratios like Morse's); switching the threshold to the hardened
  /// [currentUnitMs] would lower it and let borderline fragments
  /// through that the tuned value absorbs.
  int? get _rawPercentileUnitMs {
    if (_recentOnMs.length < 6) return null;
    final sorted = List<int>.from(_recentOnMs)..sort();
    return sorted[(sorted.length * 0.25).floor()];
  }

  /// Current glitch threshold in ms.
  int get glitchThresholdMs {
    final unit = _rawPercentileUnitMs;
    if (unit == null) return minElementMs;
    return (unit * glitchRatio).round().clamp(minElementMs, maxGlitchMs);
  }

  /// Current dit estimate in ms, or null until at least 6 marks
  /// have been seen. Exposed (beyond [glitchThresholdMs]'s own use
  /// of it) so callers can adapt other rate-dependent behaviour,
  /// such as the depth of an on/off threshold, to the same estimate.
  ///
  /// **Hardened against fragment pollution.** Hardware logs showed
  /// the old running 25th percentile collapse from 60 ms to 30 ms on
  /// a 20 WPM stream purely because threshold chatter chopped dahs
  /// into 20-45 ms fragments that then dominated the low end of the
  /// history. The estimate therefore only trusts marks inside a
  /// plausible band around the current unit:
  ///
  /// * **bootstrap** (no estimate yet) — 25th percentile of the
  ///   last [historySize] marks, as before;
  /// * **fragment rejection** — only marks within 0.7x-2.2x the
  ///   current unit feed the refinement, so fragments below and
  ///   dahs above the band cannot drag it;
  /// * **bounded adaptation** — the estimate moves at most 25%
  ///   (up) / -35% (down) per emitted mark, so a burst of odd marks
  ///   cannot snap it to a wrong cluster;
  /// * **hold on thin evidence** — fewer than 4 in-band marks in
  ///   the window keeps the previous estimate unchanged.
  int? get currentUnitMs => _lastUnitMs;

  /// Recomputes the unit estimate after a mark was added to the
  /// history. See [currentUnitMs] for the guards.
  void _recomputeUnit() {
    if (_recentOnMs.length < 6) return;
    final sorted = List<int>.from(_recentOnMs)..sort();
    final prev = _lastUnitMs;
    if (prev == null) {
      _lastUnitMs = sorted[(sorted.length * 0.25).floor()];
      return;
    }
    final lo = (prev * 0.7).round();
    final hi = (prev * 2.2).round();
    final band = sorted.where((d) => d >= lo && d <= hi).toList();
    int est;
    if (band.length >= 4) {
      // Healthy: enough in-band marks to trust the band estimate.
      est = band[(band.length * 0.25).floor()];
    } else if (band.isEmpty) {
      // No in-band marks at all: the stream's rate has genuinely
      // changed (or every recent mark was a fragment). Re-bootstrap
      // from the raw percentile; the clamp below limits how far a
      // single re-bootstrap can move the estimate.
      est = sorted[(sorted.length * 0.25).floor()];
    } else {
      // Thin evidence mixed with out-of-band marks: hold the
      // estimate until the picture is clearer.
      return;
    }
    final loClamp = (prev * 0.65).round();
    final hiClamp = (prev * 1.25).round();
    _lastUnitMs = est < loClamp ? loClamp : (est > hiClamp ? hiClamp : est);
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
      onMerge?.call(absorbedMs: durationMs, intoOn: _pendingIsOn!);
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

  /// Releases the held-back element early once it can no longer be
  /// merged, given the current time [nowMs].
  ///
  /// [transition] deliberately emits one segment late so a following
  /// glitch can be folded back into the element before it (see the
  /// class docs). The cost is that the final mark of every character
  /// stays invisible until the *next* character starts — a `V`
  /// (`...-`) reads as `S` (`...`) for the whole inter-character gap
  /// and only completes when the next mark arrives.
  ///
  /// A decoder that calls this every frame with the current timestamp
  /// closes that gap: once [nowMs] is more than [glitchThresholdMs]
  /// past the pending element's end, the in-progress segment is
  /// already too long to be a glitch, so nothing that arrives later
  /// can merge the pending element away — it is safe to emit now.
  void tick(double nowMs) {
    if (_pendingIsOn == null) return;
    // Only once the element rate is known: before that the glitch
    // threshold is just [minElementMs], so an early flush here would
    // pre-empt merges that a matured threshold would still make —
    // which is exactly the noisy, no-real-signal startup window where
    // holding elements back matters most.
    if (currentUnitMs == null) return;
    if (nowMs - _pendingEndMs > glitchThresholdMs) _emitPending();
  }

  void _emitPending() {
    final isOn = _pendingIsOn;
    if (isOn == null) return;
    _pendingIsOn = null;

    final durationMs = (_pendingEndMs - _pendingStartMs).round();
    if (durationMs <= 0) return;

    if (isOn) {
      _recentOnMs.add(durationMs);
      if (_recentOnMs.length > historySize) _recentOnMs.removeAt(0);
      _recomputeUnit();
    }

    onElement(DecodedElement(isOn: isOn, durationMs: durationMs));
  }

  /// Clears all state.
  void reset() {
    _recentOnMs.clear();
    _lastUnitMs = null;
    _isOn = false;
    _segStartMs = 0;
    _started = false;
    _pendingIsOn = null;
  }
}
