/// Abstract interface for audio capture from a microphone.
///
/// Implementations live in the data layer (e.g. using the
/// `record` package on mobile, or a web audio API stub on
/// web). The domain layer depends only on this interface.
abstract interface class AudioCapture {
  /// Starts capturing audio and returns a stream of sample
  /// buffers.
  ///
  /// Each buffer contains mono 16-bit PCM samples normalized
  /// to the range [-1, 1] as doubles.
  Stream<List<double>> start();

  /// Stops capturing audio.
  Future<void> stop();

  /// Whether capture is currently active.
  bool get isActive;

  /// Checks whether the microphone permission has been
  /// granted.
  Future<bool> hasPermission();
}
