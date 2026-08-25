import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

/// The lifecycle state of a Morse transmission.
enum TransmissionStatus {
  idle,
  transmitting,
  completed,
}

/// Immutable snapshot of the transmission state.
@immutable
class TransmissionState extends Equatable {
  const TransmissionState({
    this.status = TransmissionStatus.idle,
    this.currentCharIndex = -1,
  });

  final TransmissionStatus status;

  /// Index of the character currently being transmitted.
  /// -1 when not transmitting or completed.
  final int currentCharIndex;

  bool get isTransmitting => status == TransmissionStatus.transmitting;
  bool get isCompleted => status == TransmissionStatus.completed;

  TransmissionState copyWith({
    TransmissionStatus? status,
    int? currentCharIndex,
  }) {
    return TransmissionState(
      status: status ?? this.status,
      currentCharIndex: currentCharIndex ?? this.currentCharIndex,
    );
  }

  @override
  List<Object?> get props => [status, currentCharIndex];
}
