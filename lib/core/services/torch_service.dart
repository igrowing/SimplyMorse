// Conditional import — picks IO implementation on mobile,
// stub on platforms without torch hardware (web).
import 'package:simply_morse/core/services/torch_service_stub.dart'
    if (dart.library.io) 'package:simply_morse/core/services/torch_service_io.dart'
    as impl;

/// Abstract interface for torch/flashlight control.
abstract interface class TorchService {
  /// Whether the device has a torch available.
  Future<bool> get isAvailable;

  /// Turns the torch on.
  Future<void> enable();

  /// Turns the torch off.
  Future<void> disable();
}

/// Creates the platform-appropriate torch service.
TorchService createTorchService() => impl.createTorchService();
