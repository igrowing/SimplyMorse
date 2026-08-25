import 'package:simply_morse/core/services/torch_service.dart';

/// Stub implementation for platforms without torch hardware.
class TorchServiceStub implements TorchService {
  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<void> enable() async {}

  @override
  Future<void> disable() async {}
}

/// Factory used by the conditional import in torch_service.dart.
TorchService createTorchService() => TorchServiceStub();
