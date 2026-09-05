/// Confirms a stream of elements is genuinely Morse-timed before
/// letting any of it through — but only where that confirmation is
/// safe to ask for.
library;

import 'package:simply_morse/features/decoding/domain/models/decoded_element.dart';

/// Filters a leading run of non-Morse elements out of an element
/// stream before it reaches the decoder — for slow sending only.
///
/// **Why this exists.** The audio decoder never sees this problem:
/// its FFT scanning phase requires a monotonic tone to repeat several
/// times (or hold steady for 500 ms) before it locks at all, so
/// non-Morse audio — voice, room noise, a hand bumping the mic — is
/// rejected before tracking ever starts. Video's scanning phase has
/// no equivalent: it locks onto anything with high temporal variance
/// and a roughly bimodal brightness (a genuine beacon, but just as
/// well camera autoexposure settling, a hand steadying the phone, or
/// a sender-side countdown UI) and starts reading elements
/// immediately. Measured on the reference recordings, one video
/// fixture's brightness trace opens with ~20 elements of exactly this
/// kind of junk — durations like 3993 ms, 2673 ms, 1749 ms that don't
/// relate to each other by any small integer ratio — before the real
/// ~300 ms-unit Morse pattern begins, and it wrecks the whole decode
/// (the false dit estimate from that junk propagates through every
/// downstream element).
///
/// **Why it only engages at low speed.** A strict fit-tolerance narrow
/// enough to reject that junk is, at fast sending speeds, also narrow
/// enough to reject genuine content: at 20 WPM on 30 fps video a dit
/// is only ~1.8 frames, so a single frame of timing quantization is
/// already a large fraction of the unit, and *every* window ends up
/// with at least one element the fit check calls bad. Measured, this
/// gate applied unconditionally fixes the one fixture with a real
/// junk prefix but makes 20 WPM content dramatically worse (its
/// natural quantization noise looks exactly like the junk this gate
/// is built to reject, and there is no junk there to find instead).
/// The two situations are told apart by the same number that predicts
/// the failure mode: how large a fraction of the unit a frame or a
/// timing glitch actually is. Rather than one tolerance trying to
/// serve both, the gate decides once, from the first
/// [minElementsToLock] elements' provisional median mark duration,
/// whether sending is slow enough ([fastUnitThresholdMs] or slower)
/// for strict fitting to be safe at all — and if it isn't, stops
/// gating and passes everything through unfiltered from that point,
/// rather than risk discarding real content while chasing a fit that
/// quantization noise will never cleanly produce.
///
/// **How the slow-speed fit decides.** Once engaged, elements are
/// buffered, not forwarded, until [minElementsToLock] have
/// accumulated. At that point every mark in the buffer must be within
/// [tolerance] of 1 or 3 times the buffer's own median mark duration,
/// and every *short* space (at most 5 units) must likewise fit 1 or 3
/// units — long spaces are never held against the fit, since a
/// genuine pause of any length is valid Morse and including it in a
/// ratio-tolerance check would let its enormous absolute tolerance
/// (`7 units x tolerance`) wave through exactly the kind of junk this
/// gate exists to catch. [minAbsoluteSlackMs] additionally floors how
/// many milliseconds of slack the fit allows, since the same
/// millisecond of jitter is a small fraction of a slow unit but a
/// large one of a fast unit even within the "slow enough to gate"
/// regime. If the buffer fits, it locks: the whole buffer is flushed
/// in order and every element after it passes straight through. If it
/// doesn't fit, the oldest element is dropped and the gate keeps
/// waiting — a sliding window, not a fixed one, so it recovers once
/// genuine content starts arriving rather than getting stuck on a
/// single bad early window.
///
/// **If it never locks.** [flush] still emits whatever is buffered
/// rather than silently discarding it — a short or unusual
/// transmission should degrade, not vanish. The same applies if
/// [maxPatience] sliding attempts pass without a clean fit: rather
/// than lose everything but the tail, the gate gives up gating and
/// lets the buffered content and everything after it through as-is.
class MorseLockGate {
  MorseLockGate({
    required this.onElement,
    this.minElementsToLock = 12,
    this.minMarksToLock = 6,
    this.tolerance = 0.25,
    this.minAbsoluteSlackMs = 35,
    this.maxPatience = 60,
    this.fastUnitThresholdMs = 120,
  });

  /// Receives each element once the gate has locked, has decided to
  /// bypass, or on [flush].
  final void Function(DecodedElement element) onElement;

  /// Buffer size at which the speed decision is made, and at which a
  /// fit is first attempted for content found to be slow enough to
  /// gate.
  final int minElementsToLock;

  /// Minimum number of marks in the buffer before a fit — or the
  /// initial speed decision — is attempted at all. A median of fewer
  /// marks is too easily skewed by one of them landing near a
  /// candidate boundary.
  final int minMarksToLock;

  /// Fractional tolerance for a duration to count as fitting a
  /// candidate multiple of the unit. See [minAbsoluteSlackMs].
  final double tolerance;

  /// Absolute floor, in ms, for how far a duration may be from a
  /// candidate multiple of the unit and still fit.
  ///
  /// Used together with [tolerance], whichever allows more: a pure
  /// fraction is the wrong tool on its own because the same sampling
  /// noise (e.g. one video frame's worth of timing quantization) is a
  /// small fraction of a slow unit but a much larger one of a faster
  /// unit still within the gate's "slow enough" regime. Anchoring an
  /// absolute floor in milliseconds means jitter of a fixed physical
  /// size (a frame period, a filter settling time) costs the same
  /// fit-budget regardless of exactly how slow "slow" is.
  final double minAbsoluteSlackMs;

  /// Number of elements the gate will slide past looking for a clean
  /// fit before giving up gating and passing the rest through as-is.
  ///
  /// Even within the "slow enough to gate" regime, real content can
  /// occasionally fail to find a clean window (e.g. an unusually long
  /// operator pause). Past this many attempts, "never found a clean
  /// fit" degrades to "didn't filter anything" rather than losing
  /// everything except the last few elements — worse than not gating
  /// at all would only happen for a genuine junk run longer than
  /// this, well beyond the ~20-element runs this gate is built to
  /// catch.
  final int maxPatience;

  /// Median mark duration, in ms, at or above which sending is
  /// treated as slow enough to gate. Below it, the gate makes its one
  /// speed decision from the first [minElementsToLock] elements and
  /// then stops filtering — see the class docs for why fast sending
  /// makes gating actively harmful rather than merely unnecessary.
  ///
  /// 120 ms is a 10 WPM dit — measured, the reference recordings'
  /// only fixture with a genuine junk prefix sends slower than this,
  /// and the fixture whose natural jitter this gate must not be
  /// mistaken for sends at 20 WPM (60 ms dits), comfortably on the
  /// fast side of the line.
  final double fastUnitThresholdMs;

  final List<DecodedElement> _buffer = [];
  bool _locked = false;
  bool? _isSlow;
  int _attempts = 0;

  /// Whether the gate has locked onto genuine Morse timing (including
  /// having decided to bypass fast content, or given up after
  /// [maxPatience]). Once true, elements pass straight through.
  bool get isLocked => _locked;

  /// Whether the gate is actively filtering (decided slow enough to
  /// gate and not yet locked). False before enough elements have
  /// accumulated to decide, and false once locked or bypassing.
  bool get isGating => _isSlow == true && !_locked;

  /// Feeds one element from the upstream element builder.
  void add(DecodedElement element) {
    if (_locked) {
      onElement(element);
      return;
    }

    _buffer.add(element);

    _isSlow ??= _classifySpeed();
    if (_isSlow == false) {
      _bypass();
      return;
    }
    if (_isSlow == null) return; // still waiting to classify

    if (_buffer.length < minElementsToLock) return;

    _attempts++;
    if (_fits() || _attempts >= maxPatience) {
      _bypass();
    } else {
      _buffer.removeAt(0);
    }
  }

  /// Decides whether sending is slow enough to gate, from the
  /// buffer's provisional median mark duration. Returns null if there
  /// still aren't enough marks to tell.
  bool? _classifySpeed() {
    if (_buffer.length < minElementsToLock) return null;
    final marks = _buffer.where((e) => e.isOn).map((e) => e.durationMs).toList()
      ..sort();
    if (marks.length < minMarksToLock) return null;
    return marks[marks.length ~/ 2] >= fastUnitThresholdMs;
  }

  /// Fraction of the buffer that may fail the fit without failing
  /// the window. Genuine sending at fine timing resolution always
  /// carries a few jitter outliers — measured on the 60 fps
  /// reference recordings, one long dit (~1.35 units) and one short
  /// inter-character gap per ~12 elements — while the junk runs
  /// this gate exists to catch are off by large multiples across
  /// *most* of the window. A small outlier budget separates them:
  /// genuine windows fail on only 1-2 elements, junk windows on
  /// nearly all of them.
  static const double _maxOutlierFraction = 1 / 6;

  /// Upper bound on the mark-unit : space-unit ratio. Genuine video
  /// timing is asymmetric (marks run ~1.3x spaces on the reference
  /// recordings) but stays near 1; junk timing makes the two
  /// medians unrelated, and this bound rejects it without relying
  /// on the per-element fit alone.
  static const double _maxUnitRatio = 2;

  bool _fits() {
    final markDurations =
        _buffer.where((e) => e.isOn).map((e) => e.durationMs).toList()..sort();
    if (markDurations.length < minMarksToLock) return false;

    final unitMark = markDurations[markDurations.length ~/ 2]; // median
    if (unitMark <= 0) return false;

    // Video measurement is asymmetric: auto-exposure settling and
    // threshold hysteresis systematically lengthen marks and shorten
    // gaps (measured ~1.3x on the reference recordings), so spaces
    // are fitted against a space-derived unit, not the mark unit.
    // Long spaces are excluded from that estimate — mixing
    // intra-character and inter-character gaps risks a median that
    // matches neither.
    final spaceDurations =
        _buffer
            .where((e) => !e.isOn && e.durationMs <= (5 * unitMark) / 2)
            .map((e) => e.durationMs)
            .toList()
          ..sort();
    final unitSpace = spaceDurations.length >= 3
        ? spaceDurations[spaceDurations.length ~/ 2]
        : unitMark;
    if (unitSpace <= 0) return false;

    final unitRatio = unitMark / unitSpace;
    if (unitRatio < 1 / _maxUnitRatio || unitRatio > _maxUnitRatio) {
      return false;
    }

    final maxOutliers = (_buffer.length * _maxOutlierFraction).floor();
    var outliers = 0;
    for (final e in _buffer) {
      final unit = e.isOn ? unitMark : unitSpace;
      final ratio = e.durationMs / unit;
      if (!e.isOn && ratio > 5) continue; // a long pause proves nothing
      final fits = [1, 3].any((c) {
        final target = c * unit;
        final allowed = (target * tolerance).clamp(
          minAbsoluteSlackMs,
          double.infinity,
        );
        return (e.durationMs - target).abs() <= allowed;
      });
      if (!fits) {
        outliers++;
        if (outliers > maxOutliers) return false;
      }
    }
    return true;
  }

  /// Locks — flushing the buffer and passing everything after it
  /// through unfiltered — whether because a clean fit was found, the
  /// content was classified as too fast to safely gate, or patience
  /// ran out.
  void _bypass() {
    _locked = true;
    _buffer
      ..forEach(onElement)
      ..clear();
  }

  /// Emits whatever is buffered, locked or not, so a stream that
  /// never satisfies the fit still reaches the decoder in full rather
  /// than being silently dropped. Call at the end of a transmission.
  void flush() {
    _buffer
      ..forEach(onElement)
      ..clear();
  }

  /// Clears all state.
  void reset() {
    _buffer.clear();
    _locked = false;
    _isSlow = null;
    _attempts = 0;
  }
}
