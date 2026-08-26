import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:simply_morse/core/services/torch_service.dart';

/// A [TorchService] implementation that uses the screen
/// itself as a visual LED instead of hardware torch.
///
/// Exposes [isFlashing] as a [ValueNotifier<bool>] so the
/// UI can react to on/off state changes in real time.
///
/// Used on web where no physical torch is available.
class ScreenFlashService implements TorchService {
  final ValueNotifier<bool> _isFlashing = ValueNotifier<bool>(false);

  /// Whether the visual LED is currently "on" (flashing).
  ValueNotifier<bool> get isFlashing => _isFlashing;

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<void> enable() async {
    _isFlashing.value = true;
  }

  @override
  Future<void> disable() async {
    _isFlashing.value = false;
  }

  /// Releases the notifier's resources.
  void dispose() => _isFlashing.dispose();
}

/// Whether the screen flash LED emulation is active.
///
/// Returns `true` on web where [ScreenFlashService] is
/// registered instead of the hardware torch.
bool get usesScreenFlash => kIsWeb;
