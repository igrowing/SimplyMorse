/// Debug log callback for recorder lifecycle events — the audio
/// counterpart of the camera side's capture-event callback.
/// Timestamps are wall-clock ms.
typedef DebugAudioCaptureEventCallback =
    void Function({
      required int timestampMs,
      required String event,
      int? dtMs,
      String? detail,
    });

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

  /// Optional debug hook for recorder lifecycle events.
  ///
  /// Set by the composition layer; the capture implementation
  /// reports permission checks, start configuration, buffer
  /// arrivals (with wall-clock dt), and stop here. Buffer rows
  /// make stream stalls and sample drops visible as timeline
  /// holes — problems the decoder itself cannot see.
  DebugAudioCaptureEventCallback? get onDebugEvent;
  set onDebugEvent(DebugAudioCaptureEventCallback? callback);
}
