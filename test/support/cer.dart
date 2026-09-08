/// Character error rate (CER) helpers for decoder accuracy tests.
///
/// The recording tests assert on *how much* of the expected text was
/// recovered rather than on loose `contains` checks, so that a small
/// accuracy improvement or regression is visible as a number.
library;

import 'dart:math';

/// Levenshtein edit distance between [a] and [b].
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = min(min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final tmp = prev;
    prev = cur;
    cur = tmp;
  }
  return prev[b.length];
}

/// Character error rate of [decoded] against [expected], in the range
/// 0.0 (perfect) to 1.0+ (worse than emitting nothing).
double characterErrorRate(String decoded, String expected) {
  if (expected.isEmpty) return decoded.isEmpty ? 0 : 1;
  return editDistance(decoded, expected) / expected.length;
}

/// Formats a one-line accuracy report for test output.
String cerReport(String label, String decoded, String expected) {
  final d = editDistance(decoded, expected);
  final pct = (d / expected.length * 100).toStringAsFixed(1);
  return '  $label CER=$pct% ($d/${expected.length}) "$decoded"';
}
