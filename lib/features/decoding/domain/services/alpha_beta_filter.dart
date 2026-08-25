import 'dart:math';

/// A simplified 2D Kalman filter (α-β filter) for tracking
/// a blinking source's position across frames.
///
/// Tracks position and velocity in pixel coordinates.
/// The [alpha] parameter controls position correction
/// strength (higher = follows measurements more closely),
/// [beta] controls velocity estimation (higher = adapts
/// to drift faster but is noisier).
///
/// The [innovation] (last prediction error magnitude) is
/// exposed for adaptive region sizing — a large innovation
/// means the source moved unexpectedly, so the brightness
/// reading region should grow to avoid losing it.
class AlphaBetaFilter {
  AlphaBetaFilter({
    this.alpha = 0.7,
    this.beta = 0.1,
  }) : assert(alpha > 0 && alpha <= 1),
       assert(beta >= 0 && beta <= 1);

  final double alpha;
  final double beta;

  double _x = 0;
  double _y = 0;
  double _vx = 0;
  double _vy = 0;
  double _innovation = 0;
  bool _initialized = false;

  /// Current estimated X position (pixels).
  double get x => _x;

  /// Current estimated Y position (pixels).
  double get y => _y;

  /// Current estimated X velocity (pixels/second).
  double get vx => _vx;

  /// Current estimated Y velocity (pixels/second).
  double get vy => _vy;

  /// Last prediction error magnitude (pixels).
  /// Large values indicate unexpected source movement.
  double get innovation => _innovation;

  /// Whether the filter has been initialized.
  bool get isInitialized => _initialized;

  /// Initializes the filter with a starting position.
  void initialize(double x, double y) {
    _x = x;
    _y = y;
    _vx = 0;
    _vy = 0;
    _innovation = 0;
    _initialized = true;
  }

  /// Predicts the next position using the current velocity
  /// estimate.
  void predict(double dt) {
    if (!_initialized) return;
    _x += _vx * dt;
    _y += _vy * dt;
  }

  /// Updates the filter with a measurement.
  ///
  /// [dt] is the time elapsed since the last update, in
  /// seconds.
  void update(double measuredX, double measuredY, double dt) {
    if (!_initialized) {
      initialize(measuredX, measuredY);
      return;
    }

    final dx = measuredX - _x;
    final dy = measuredY - _y;
    _innovation = sqrt(dx * dx + dy * dy);

    _x += alpha * dx;
    _y += alpha * dy;

    if (dt > 0) {
      _vx += beta * dx / dt;
      _vy += beta * dy / dt;
    }
  }

  /// Resets the filter to the uninitialized state.
  void reset() {
    _x = 0;
    _y = 0;
    _vx = 0;
    _vy = 0;
    _innovation = 0;
    _initialized = false;
  }
}
