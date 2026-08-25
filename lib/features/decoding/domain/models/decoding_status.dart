/// Status of a decoding session.
enum DecodingStatus {
  /// Not started — no listening has occurred yet.
  idle,

  /// Actively listening / watching for Morse input.
  listening,

  /// User has paused; decoded text is preserved.
  paused,
}
