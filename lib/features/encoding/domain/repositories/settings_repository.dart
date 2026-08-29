/// Repository interface for managing encoding settings persistence.
abstract interface class SettingsRepository {
  /// Gets the saved speed in words per minute.
  Future<double> getSpeed();

  /// Saves the speed in words per minute.
  Future<void> saveSpeed(double wpm);

  /// Gets the saved tone frequency in Hz.
  Future<double> getTone();

  /// Saves the tone frequency in Hz.
  Future<void> saveTone(double hz);

  /// Gets the saved initial delay in seconds.
  Future<double> getInitialDelay();

  /// Saves the initial delay in seconds.
  Future<void> saveInitialDelay(double seconds);

  /// Gets whether repeat-in-loop is enabled.
  Future<bool> getRepeatLoop();

  /// Saves the repeat-in-loop setting.
  Future<void> saveRepeatLoop(bool enabled);

  /// Gets the delay between repeats in seconds.
  Future<double> getRepeatDelay();

  /// Saves the delay between repeats in seconds.
  Future<void> saveRepeatDelay(double seconds);

  /// Gets the display lit timeout mode
  /// ('system', '3x', or 'always').
  Future<String> getDisplayTimeout();

  /// Saves the display lit timeout mode.
  Future<void> saveDisplayTimeout(String mode);
}
