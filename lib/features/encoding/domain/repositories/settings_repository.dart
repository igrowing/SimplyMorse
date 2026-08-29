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
}
