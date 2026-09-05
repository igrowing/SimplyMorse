import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/widgets.dart';

/// Minimal [CameraPlatform] fake that lets a real [CameraController]
/// reach `isInitialized == true` with a chosen preview size, and
/// optionally stream fake frames through `startImageStream`, without
/// a real camera or platform channel.
///
/// Only the calls `CameraCaptureImpl` actually makes are implemented:
/// [availableCameras], [createCamera], [initializeCamera] /
/// [onCameraInitialized], [setExposureMode], and — when a test calls
/// [emitFrame] — [supportsImageStreaming] / [onStreamedFrameAvailable].
/// Everything else keeps [CameraPlatform]'s default "unimplemented"
/// behavior — add an override here if a test starts exercising more
/// of the surface.
class FakeCameraPlatform extends CameraPlatform {
  FakeCameraPlatform({required this.previewSize});

  /// Reported preview size, in SENSOR (landscape) orientation — the
  /// space `CameraController.value.aspectRatio` is computed from.
  final Size previewSize;

  static const _cameraId = 1;

  final _initializedController =
      StreamController<CameraInitializedEvent>.broadcast();

  // Never closed and never emits — CameraController does
  // `.first.then(...)` on this without awaiting it, and `.first`
  // on a stream that closes without an event (e.g. Stream.empty())
  // throws a StateError, which then surfaces as an unhandled
  // async error in tests.
  final _errorController = StreamController<CameraErrorEvent>.broadcast();

  final _frameController = StreamController<CameraImageData>.broadcast();

  /// Pushes a fake frame to whoever is streaming via
  /// `CameraController.startImageStream`.
  void emitFrame(CameraImageData frame) => _frameController.add(frame);

  @override
  Future<List<CameraDescription>> availableCameras() async => [
    const CameraDescription(
      name: 'fake',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async => _cameraId;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    // CameraController subscribes to onCameraInitialized(cameraId).first
    // before calling initializeCamera, so this event is delivered to a
    // listener that is already attached.
    _initializedController.add(
      CameraInitializedEvent(
        cameraId,
        previewSize.width,
        previewSize.height,
        ExposureMode.auto,
        false,
        FocusMode.auto,
        false,
      ),
    );
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initializedController.stream;

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      _errorController.stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {}

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) => _frameController.stream;

  @override
  Future<void> dispose(int cameraId) async {
    await _initializedController.close();
    await _errorController.close();
    await _frameController.close();
  }
}
