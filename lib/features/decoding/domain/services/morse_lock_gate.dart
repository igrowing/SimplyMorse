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
/// **If it never locks.** How the buffer is released depends on *why*
/// the stream ended. [flush] — a deliberate end of transmission —
/// still emits, so a short or unusual transmission degrades rather
/// than vanishing. [releaseOnSignalLoss] — the decoder abandoning a
/// lock it should never have taken — emits only if the buffer
/// actually fits Morse timing, because a video lock is cheap enough
/// that sensor noise acquires one. The same applies if [maxPatience]
/// sliding attempts pass without a clean fit: rather than lose
/// everything but the tail, the gate gives up gating and lets the
/// buffered content and everything after it through as-is.
///
/// **Sliding never discards.** The window advances by moving its
/// start index over a retained history, so elements slid past are
/// still available for the whole-history fit both release paths run.
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

  /// Every element seen since the last [reset], in order.
  ///
  /// The candidate window is `_history.sublist(_windowStart)` — the
  /// window slides by advancing [_windowStart], never by dropping
  /// elements. Dropping them (the original implementation) meant that
  /// a stream which never found a clean fit lost everything except
  /// the final window: measured on an 8 WPM field capture, 59 of 70
  /// genuine elements were destroyed before [flush] ever ran.
  final List<DecodedElement> _history = [];
  int _windowStart = 0;
  bool _locked = false;
  bool? _isSlow;
  int _attempts = 0;

  /// The elements currently under consideration.
  List<DecodedElement> get _buffer => _history.sublist(_windowStart);

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

    _history.add(element);
    if (_history.length - _windowStart < minElementsToLock) return;

    if (_isSlow == null) {
      _isSlow = _classifySpeed();
      // A window too junk-ridden to read a speed off must not simply
      // be waited on: the junk is a prefix, so slide past it. The
      // speed decision is made once and never revisited, and letting
      // junk make it is unrecoverable — a settling flicker of 66 and
      // 99 ms reads as a 99 ms unit, i.e. "too fast to gate", and the
      // gate then waves the whole transmission through unchecked.
      if (_isSlow == null) {
        if (_spansMoreThanMorseCan(_buffer)) _windowStart++;
        return;
      }
    }
    if (_isSlow == false) {
      _bypass();
      return;
    }

    _attempts++;
    if (_fits(_buffer) || _attempts >= maxPatience) {
      _bypass();
    } else {
      _windowStart++;
    }
  }

  /// Whether the window's marks span a wider range than Morse permits.
  ///
  /// Every Morse mark is 1 or 3 units, so the longest can only be
  /// about 3x the shortest — generously, [_maxMarkSpread] with
  /// measurement dilation. A window spanning far more than that (the
  /// reference junk prefixes span 60x: 66 ms alongside 3993 ms) is not
  /// Morse at any speed, and nothing about sending speed can be read
  /// off it.
  bool _spansMoreThanMorseCan(List<DecodedElement> window) {
    final marks = window.where((e) => e.isOn).map((e) => e.durationMs).toList()
      ..sort();
    if (marks.length < 2 || marks.first <= 0) return false;
    return marks.last / marks.first > _maxMarkSpread;
  }

  /// Widest longest:shortest mark ratio a genuine window can show.
  static const double _maxMarkSpread = 6;

  /// Decides whether sending is slow enough to gate, from the
  /// buffer's provisional unit estimate. Returns null if there still
  /// aren't enough marks to tell.
  bool? _classifySpeed() {
    if (_history.length - _windowStart < minElementsToLock) return null;
    final window = _buffer;
    final marks = window.where((e) => e.isOn).map((e) => e.durationMs).toList()
      ..sort();
    if (marks.length < minMarksToLock) return null;
    // No speed can be read off a window that is not Morse at all.
    if (_spansMoreThanMorseCan(window)) return null;
    final unit = _unitFrom(marks);
    return unit != null && unit >= fastUnitThresholdMs;
  }

  /// Estimates the dit unit from a sorted list of mark durations.
  ///
  /// **Not the median.** A median only lands on a dit when dits
  /// outnumber dahs, and plenty of real text is dah-heavy — measured
  /// on an 8 WPM field capture of "HELLO, WORLD!" the decoder saw 18
  /// dahs to 8 dits, so the median mark *was* a dah, the unit came out
  /// 3x too large, and every genuine dit was then scored as an
  /// outlier. The gate rejected a textbook-clean transmission.
  ///
  /// Instead, split the sorted marks at their largest *relative* gap:
  /// Morse marks are bimodal by construction (1 unit and 3 units), so
  /// the widest ratio step between neighbours is the dit/dah boundary.
  /// The unit is the median of the short cluster. When no convincing
  /// split exists — all dits or all dahs in this window — fall back to
  /// the lower quartile, which is the same robust estimator the
  /// decoder already uses for its WPM readout.
  static double? _unitFrom(List<int> sortedMarks) {
    if (sortedMarks.isEmpty) return null;

    var splitAt = -1;
    var bestRatio = _minDitDahRatio;
    for (var i = 0; i < sortedMarks.length - 1; i++) {
      final lo = sortedMarks[i];
      if (lo <= 0) continue;
      final ratio = sortedMarks[i + 1] / lo;
      if (ratio > bestRatio) {
        bestRatio = ratio;
        splitAt = i;
      }
    }

    final short = splitAt >= 0
        ? sortedMarks.sublist(0, splitAt + 1)
        : sortedMarks;
    final unit = splitAt >= 0
        ? short[short.length ~/ 2].toDouble()
        : sortedMarks[(sortedMarks.length * 0.25).floor()].toDouble();
    return unit > 0 ? unit : null;
  }

  /// Smallest neighbour-to-neighbour ratio in the sorted marks that
  /// counts as the dit/dah boundary.
  ///
  /// Ideal Morse puts dahs at 3x dits, but video measurement dilates
  /// every mark by roughly a frame, which compresses the observed
  /// ratio (measured ~2.3-2.8x on 30 fps captures). 1.8 sits below
  /// that and comfortably above the spread *within* either cluster.
  static const double _minDitDahRatio = 1.8;

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

  bool _fits(List<DecodedElement> window) {
    final markDurations =
        window.where((e) => e.isOn).map((e) => e.durationMs).toList()..sort();
    if (markDurations.length < minMarksToLock) return false;

    final unitMark = _unitFrom(markDurations);
    if (unitMark == null) return false;

    // Video measurement is asymmetric: auto-exposure settling and
    // threshold hysteresis systematically lengthen marks and shorten
    // gaps (measured ~1.3x on the reference recordings), so spaces
    // are fitted against a space-derived unit, not the mark unit.
    // Long spaces are excluded from that estimate — mixing
    // intra-character and inter-character gaps risks a median that
    // matches neither.
    final spaceDurations =
        window
            .where((e) => !e.isOn && e.durationMs <= (5 * unitMark) / 2)
            .map((e) => e.durationMs)
            .toList()
          ..sort();
    final unitSpace = spaceDurations.length >= 3
        ? _unitFrom(spaceDurations) ?? unitMark
        : unitMark;
    if (unitSpace <= 0) return false;

    final unitRatio = unitMark / unitSpace;
    if (unitRatio < 1 / _maxUnitRatio || unitRatio > _maxUnitRatio) {
      return false;
    }

    final maxOutliers = (window.length * _maxOutlierFraction).floor();
    var outliers = 0;
    for (final e in window) {
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

  /// Locks — emitting the current window and passing everything after
  /// it through unfiltered — whether because a clean fit was found,
  /// the content was classified as too fast to safely gate, or
  /// patience ran out.
  void _bypass() {
    _locked = true;
    _emitWindow(moreToCome: true);
  }

  /// Emits the current window and clears the history, after trimming
  /// any junk prefix — see [_trimJunkPrefix]. [moreToCome] is true
  /// when the gate is locking and will keep streaming elements after
  /// this window, false when this is the last of the transmission.
  void _emitWindow({required bool moreToCome}) {
    _trimJunkPrefix(moreToCome: moreToCome);
    for (var i = _windowStart; i < _history.length; i++) {
      onElement(_history[i]);
    }
    _history.clear();
    _windowStart = 0;
  }

  /// Advances the window past a leading run of impossibly long marks.
  ///
  /// No Morse mark is longer than 3 units, so a mark many times the
  /// unit is not Morse at any speed — it is the camera's exposure
  /// settling, a hand steadying the phone, or a sender-side countdown.
  /// Every reference fixture opens with one: marks of 1.3-6.0 s
  /// against units of 50-900 ms, i.e. 14-30 units.
  ///
  /// The fine-grained [_fits] check would reject these, but it only
  /// runs for content slow enough to gate — fast sending bypasses it
  /// entirely (see the class docs), which left the fastest fixtures
  /// with their junk prefix intact. This check is cheap, needs no
  /// tolerance tuning, and is safe at any speed, so it runs on every
  /// emission path.
  ///
  /// The window restarts after the *last* offending mark found, since
  /// the fixtures interleave a few plausible-looking elements with the
  /// junk before real sending begins.
  ///
  /// How far to look depends on what follows. When the gate is
  /// locking, more elements are still streaming in behind this window,
  /// so trimming all of it costs nothing and the whole window is
  /// searched. When this is the final buffer of a transmission there
  /// is nothing behind it, so only the leading [_junkSearchFraction]
  /// is searched — otherwise one late glitch would discard a message
  /// that had already been received.
  void _trimJunkPrefix({required bool moreToCome}) {
    final window = _buffer;
    if (window.isEmpty) return;
    final marks = window.where((e) => e.isOn).map((e) => e.durationMs).toList()
      ..sort();
    // Too few marks to estimate a unit from; trimming against a guess
    // would be worse than leaving the window alone.
    if (marks.length < minMarksToLock) return;
    final unit = _unitFrom(marks);
    if (unit == null) return;

    final limit = unit * _maxMarkUnits;
    final searchEnd = moreToCome
        ? window.length
        : (window.length * _junkSearchFraction).floor();

    // Impossibly long marks (>5 units) are junk at any speed, even
    // interleaved with plausible elements — restart after the last one.
    var lastJunk = -1;
    for (var i = 0; i < searchEnd; i++) {
      final e = window[i];
      if (e.isOn && e.durationMs > limit) lastJunk = i;
    }

    // Additionally, while a whole transmission is still streaming in
    // behind this window (so over-trimming costs a character, not the
    // message), drop a *contiguous* leading run of marks that fit
    // neither 1 nor 3 units — the auto-exposure and hand-settling
    // wobble that opens a handheld capture, whose marks are only a few
    // units long and so clear the >5 bar but are not Morse-timed.
    // Stops at the first mark that fits, so a real element is never
    // trimmed from between two junk ones.
    if (moreToCome) {
      for (var i = 0; i < searchEnd; i++) {
        final e = window[i];
        if (!e.isOn) continue;
        final fits = [1, 3].any((c) {
          final target = c * unit;
          final allowed = (target * tolerance).clamp(
            minAbsoluteSlackMs,
            double.infinity,
          );
          return (e.durationMs - target).abs() <= allowed;
        });
        if (fits) break;
        lastJunk = lastJunk < i ? i : lastJunk;
      }
    }

    if (lastJunk >= 0) _windowStart += lastJunk + 1;
  }

  /// Longest mark, in units, that can still be Morse. The legal
  /// maximum is 3 (a dah); 5 leaves room for measurement dilation
  /// without admitting anything a sender could legitimately produce.
  static const double _maxMarkUnits = 5;

  /// Fraction of the window [_trimJunkPrefix] searches. Junk arrives
  /// before sending starts, so looking past the first half risks
  /// discarding a whole transmission over one late glitch.
  static const double _junkSearchFraction = 0.5;

  /// Releases the buffer at the end of a transmission — the user
  /// stopping, or the stream ending.
  ///
  /// A deliberate end-of-transmission is weak evidence *for* the
  /// content: the operator was pointing the camera at something. So
  /// this still tries [_bestFittingWindow] first, but falls back to
  /// emitting everything rather than dropping a short or unusual
  /// transmission that simply never gave the fit enough to chew on.
  void flush() {
    if (_locked) return;
    _windowStart = _bestFittingWindow() ?? _windowStart;
    _emitWindow(moreToCome: false);
  }

  /// Releases the buffer because the *lock* was lost, not because the
  /// transmission ended.
  ///
  /// Unlike [flush] this emits nothing unless the buffered elements
  /// actually fit Morse timing. Losing a lock is the decoder saying
  /// "there was never a signal here", and a video lock is cheap to
  /// acquire — sensor noise alone clears the variance threshold. On a
  /// field capture with *nothing transmitting*, the gate correctly
  /// refused to lock three separate times, and each time the old
  /// unconditional flush dumped the rejected buffer downstream
  /// anyway, printing "UDEA " out of an empty room. If it did not
  /// prove itself while the lock was alive, it does not get to speak
  /// on the way out.
  void releaseOnSignalLoss() {
    if (_locked) return;
    final start = _bestFittingWindow();
    if (start == null) {
      _history.clear();
      _windowStart = 0;
      return;
    }
    _windowStart = start;
    _emitWindow(moreToCome: false);
  }

  /// Index of the earliest window start whose suffix passes [_fits],
  /// or null when no suffix of the retained history fits.
  ///
  /// Sliding during [add] only ever tested windows ending at the
  /// element that had just arrived; by the end of a transmission the
  /// history holds later elements those windows never saw, so a
  /// window that failed mid-stream can fit once completed.
  int? _bestFittingWindow() {
    for (var start = _windowStart; start < _history.length; start++) {
      if (_history.length - start < minElementsToLock) break;
      if (_fits(_history.sublist(start))) return start;
    }
    return null;
  }

  /// Clears all state.
  void reset() {
    _history.clear();
    _windowStart = 0;
    _locked = false;
    _isSlow = null;
    _attempts = 0;
  }
}
