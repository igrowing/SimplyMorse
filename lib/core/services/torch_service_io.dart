import 'package:simply_morse/core/services/torch_service.dart';
import 'package:torch_light/torch_light.dart';

/// IO implementation of [TorchService] using the torch_light
/// package.
class TorchServiceIO implements TorchService {
  @override
  Future<bool> get isAvailable => TorchLight.isTorchAvailable();

  @override
  Future<void> enable() => TorchLight.enableTorch();

  @override
  Future<void> disable() => TorchLight.disableTorch();
}

/// Factory used by the conditional import in torch_service.dart.
TorchService createTorchService() => TorchServiceIO();
