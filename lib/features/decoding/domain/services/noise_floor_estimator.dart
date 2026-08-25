/// Adaptive noise floor estimator using a running median.
///
/// Tracks the background energy level over a rolling window
/// so the on/off threshold adapts to varying ambient noise.
class NoiseFloorEstimator {
  NoiseFloorEstimator({this.windowSize = 30})
    : assert(windowSize > 0, 'windowSize must be positive');

  final int windowSize;

  final List<double> _values = [];

  /// Current estimated noise floor (median of recent values).
  double get noiseFloor => _median();

  /// Number of samples currently stored.
  int get length => _values.length;

  /// Whether enough data has been collected for a reliable
  /// estimate.
  bool get isReady => _values.length >= 5;

  /// Updates the estimate with a new energy value.
  void update(double value) {
    _values.add(value);
    if (_values.length > windowSize) {
      _values.removeAt(0);
    }
  }

  /// Clears all stored values.
  void reset() {
    _values.clear();
  }

  double _median() {
    if (_values.isEmpty) return 0;
    final sorted = List<double>.from(_values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isEven
        ? (sorted[mid - 1] + sorted[mid]) / 2
        : sorted[mid];
  }
}
