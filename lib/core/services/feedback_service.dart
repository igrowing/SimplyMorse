/// Abstract interface for haptic and audio feedback.
///
/// Provides haptic feedback for button presses and
/// important UI interactions.
abstract interface class FeedbackService {
  /// Light impact feedback (button taps).
  Future<void> lightImpact();

  /// Medium impact feedback (start/stop actions).
  Future<void> mediumImpact();

  /// Heavy impact feedback (transmission start).
  Future<void> heavyImpact();

  /// Selection click feedback (sliders, dropdowns).
  Future<void> selectionClick();

  /// Vibration pattern for transmission completion.
  Future<void> success();
}
