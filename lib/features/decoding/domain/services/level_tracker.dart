/// Two-class (mark / space) signal level tracker operating in dB.
library;

import 'dart:math';

/// Tracks the two levels a Morse envelope alternates between — the
/// *mark* (tone present) level and the *space* (background) level —
/// and thresholds between them.
///
/// This replaces the earlier "max-hold peak + gated median noise
/// floor" scheme, which had two structural problems:
///
/// 1. The peak was a maximum with a ~10 s decay, so it could not
///    follow a signal that got *quieter*. In the 1000 Hz reference
///    recording the tone drops 11 dB while the background rises
///    14 dB; the peak stayed high, the threshold stayed above the
///    tone, and alternate dits were dropped.
/// 2. Thresholds were fractions of a *linear* `peak - noise` range,
///    so their meaning changed with SNR. A drift of 11 dB is a
///    constant offset in the log domain but a 12x change in linear
///    amplitude.
///
/// Both levels are exponential moving averages in dB, each updated
/// only by samples that fall on its own side of the current
/// midpoint, so both keep tracking even while the on/off decision is
/// held by hysteresis. The decision threshold is the midpoint with a
/// symmetric [hysteresisDb] band, which removes the mark/space
/// duration bias of the old asymmetric 50 % / 25 % thresholds.
///
/// When the two levels come within [minSeparationDb] the tracker
/// squelches (reports off and [isConfident] is false) — there is no
/// signal worth decoding, only noise.
class LevelTracker {
  LevelTracker({
    this.attackMs = 120,
    this.releaseMs = 150,
    this.hysteresisDb = 2.5,
    this.minSeparationDb = 6.0,
    this.thresholdOffsetDb = 3.0,
    this.noiseMarginDb = 10.0,
    this.maxSpaceDropDb = 8.0,
    this.bootstrapSamples = 100,
  });

  /// Time constant for a level moving *towards* its extreme — the mark
  /// level rising, the space level falling.
  ///
  /// Must be short compared with the shortest element the decoder has
  /// to serve: a dit is 60 ms at 20 WPM, so an attack of tens of
  /// milliseconds would leave the mark level still climbing when the
  /// dit ends. Mutable — see [reconfigure].
  double attackMs;

  /// Time constant for a level relaxing *away* from its extreme.
  ///
  /// Long enough that the two levels stay apart across normal keying,
  /// short enough to follow genuine drift — the 1000 Hz reference
  /// recording loses 11 dB of signal while its background gains 14 dB.
  /// Mutable — see [reconfigure].
  double releaseMs;

  /// Half-width of the symmetric hysteresis band around the midpoint.
  final double hysteresisDb;

  /// Minimum mark-to-space separation for the output to be trusted.
  final double minSeparationDb;

  /// How far below the mark level the decision threshold sits, in dB.
  /// 6 dB is half amplitude — the crossing point of a symmetric rise
  /// and fall, so mark and space durations are measured without bias.
  ///
  /// Placing the threshold at the *midpoint* of the two levels instead
  /// would put it far down the envelope's decay tail whenever the
  /// signal is strong (a 47 dB swing puts the midpoint 23 dB below the
  /// tone), stretching every mark and swallowing the gaps between
  /// them. The offset is capped at half the separation so a weak
  /// signal still thresholds in the middle. Mutable — see [reconfigure].
  double thresholdOffsetDb;

  /// How far above the space level the decision threshold is kept, in
  /// dB, so that background fluctuation cannot trigger marks. Capped
  /// at 60 % of the current separation so a weak but real signal is
  /// still decoded rather than squelched by its own margin.
  final double noiseMarginDb;

  /// Bound, in dB, on how far the space level is allowed to fall below
  /// its value at the start of a single uninterrupted gap. See
  /// `AudioDecoder.maxSpaceDropDb` for the failure this prevents.
  final double maxSpaceDropDb;

  /// Envelope samples collected before the levels are first estimated.
  final int bootstrapSamples;

  static const double _floorDb = -140;
  static const double _eps = 1e-12;

  double? _markDb;
  double? _spaceDb;
  bool _isOn = false;
  final List<double> _bootstrap = [];

  /// Space level as of the start of the current uninterrupted gap, or
  /// null while on (or before the first gap). Anchors [maxSpaceDropDb].
  double? _spaceDbGapAnchor;


  /// Whether both levels have been estimated.
  bool get isReady => _markDb != null;

  /// Current mark (tone) level in dB, or null before bootstrap.
  double? get markDb => _markDb;

  /// Current space (background) level in dB, or null before bootstrap.
  double? get spaceDb => _spaceDb;

  /// Distance between the two levels in dB. 0 until ready.
  double get separationDb => isReady ? _markDb! - _spaceDb! : 0;

  /// The decision threshold.
  ///
  /// Two anchors, whichever is higher:
  /// * [thresholdOffsetDb] below the mark level — the half-amplitude
  ///   crossing, which measures mark and space durations without bias;
  /// * [noiseMarginDb] above the space level — which keeps background
  ///   fluctuation from being read as marks.
  ///
  /// With a strong signal the first dominates and edges are unbiased.
  /// As SNR falls the second takes over and the threshold retreats
  /// towards the tone, trading edge accuracy for noise immunity.
  double get thresholdDb {
    if (!isReady) return 0;
    final fromMark = _markDb! - thresholdOffsetDb;
    final fromSpace = _spaceDb! + min(noiseMarginDb, separationDb * 0.6);
    return max(fromMark, fromSpace);
  }

  /// Whether the levels are far enough apart to trust the decision.
  bool get isConfident => isReady && separationDb >= minSeparationDb;

  /// Current on/off state.
  bool get isOn => _isOn;

  /// Converts a linear envelope amplitude to dB.
  static double toDb(double envelope) =>
      20 * (log(max(envelope, _eps)) / ln10);

  /// Changes the attack/release time constants and the mark-anchor
  /// offset without resetting the tracked levels — for switching to a
  /// speed-appropriate profile once the keying rate is known, without
  /// losing the convergence already reached.
  void reconfigure({
    double? attackMs,
    double? releaseMs,
    double? thresholdOffsetDb,
  }) {
    if (attackMs != null) this.attackMs = attackMs;
    if (releaseMs != null) this.releaseMs = releaseMs;
    if (thresholdOffsetDb != null) this.thresholdOffsetDb = thresholdOffsetDb;
  }

  /// Seeds both levels directly, e.g. from statistics gathered during
  /// the frequency-scanning phase, so tracking starts already
  /// converged instead of spending the first seconds adapting.
  void seed({required double markDb, required double spaceDb}) {
    _markDb = markDb;
    _spaceDb = min(spaceDb, markDb - 0.1);
    _bootstrap.clear();
  }

  /// Seeds from a batch of raw envelope amplitudes by taking an upper
  /// and a lower percentile as the two class levels.
  void seedFromEnvelopes(Iterable<double> envelopes) {
    final dbs = envelopes.map(toDb).where((d) => d > _floorDb).toList()..sort();
    if (dbs.length < 4) return;
    seed(
      markDb: dbs[(dbs.length * 0.85).floor().clamp(0, dbs.length - 1)],
      spaceDb: dbs[(dbs.length * 0.25).floor().clamp(0, dbs.length - 1)],
    );
  }

  /// Feeds one envelope amplitude sampled [dtMs] after the previous
  /// one and returns the on/off decision.
  bool process(double envelope, double dtMs) {
    final db = toDb(envelope);

    if (!isReady) {
      _bootstrap.add(envelope);
      if (_bootstrap.length >= bootstrapSamples) {
        seedFromEnvelopes(_bootstrap);
      }
      return false;
    }

    final mid = (_markDb! + _spaceDb!) / 2;
    final threshold = thresholdDb;

    final wasOn = _isOn;
    if (separationDb >= minSeparationDb) {
      if (!_isOn && db > threshold + hysteresisDb) {
        _isOn = true;
      } else if (_isOn && db < threshold - hysteresisDb) {
        _isOn = false;
      }
    } else {
      _isOn = false;
    }

    if (_isOn) {
      // No cap while on — only a gap's own space level is bounded.
      _spaceDbGapAnchor = null;
    } else if (wasOn) {
      // Just entered a gap: remember where the space level stood, so
      // this gap (however long) can't pull it down without bound.
      _spaceDbGapAnchor = _spaceDb;
    }

    // Assign the sample to a class by the midpoint of the two levels,
    // not by the decision threshold: the threshold sits high on the
    // mark side, so using it here would push envelope tails into the
    // space class and drag the space level up. Fast towards the
    // extreme, slow away from it — a symmetric average would pull both
    // levels towards the middle, including the ramp at every element
    // edge, until they met and the tracker squelched itself.
    final attack = 1 - exp(-dtMs / attackMs);
    final release = 1 - exp(-dtMs / releaseMs);
    if (db >= mid) {
      _markDb = _markDb! + (db - _markDb!) * (db > _markDb! ? attack : release);
    } else {
      var next =
          _spaceDb! + (db - _spaceDb!) * (db < _spaceDb! ? attack : release);
      final anchor = _spaceDbGapAnchor;
      if (anchor != null) next = max(next, anchor - maxSpaceDropDb);
      _spaceDb = next;
    }

    return _isOn;
  }

  /// Clears all state.
  void reset() {
    _markDb = null;
    _spaceDb = null;
    _isOn = false;
    _bootstrap.clear();
    _spaceDbGapAnchor = null;
  }
}
