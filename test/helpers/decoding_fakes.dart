import 'dart:async';

import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';
import 'package:simply_morse/features/decoding/domain/services/audio_capture.dart';
import 'package:simply_morse/features/decoding/domain/services/camera_capture.dart';

/// Fake audio capture that emits samples via a stream controller.
class FakeAudioCapture implements AudioCapture {
  FakeAudioCapture({this.hasPermissionValue = true});

  final bool hasPermissionValue;
  final _controller = StreamController<List<double>>.broadcast();
  bool _isActive = false;

  @override
  Stream<List<double>> start() {
    _isActive = true;
    return _controller.stream;
  }

  @override
  Future<void> stop() async {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  Future<bool> hasPermission() async => hasPermissionValue;

  void emit(List<double> samples) => _controller.add(samples);
  void close() => _controller.close();
}

/// Fake camera capture for video decoding tests.
class FakeCameraCapture implements CameraCapture {
  FakeCameraCapture({
    this.hasPermissionValue = true,
    this.isHighFrameRateValue = true,
  });

  final bool hasPermissionValue;
  final bool isHighFrameRateValue;

  bool _isActive = false;
  bool _isInitialized = false;
  void Function(VideoFrame frame)? _onFrame;

  @override
  Future<bool> hasPermission() async {
    if (hasPermissionValue) _isInitialized = true;
    return hasPermissionValue;
  }

  @override
  Future<void> initialize() async {
    _isInitialized = true;
  }

  @override
  void startImageStream(void Function(VideoFrame frame) onFrame) {
    _isActive = true;
    _onFrame = onFrame;
  }

  @override
  Future<void> stop() async {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  bool get isInitialized => _isInitialized;

  @override
  bool get isHighFrameRate => isHighFrameRateValue;

  void emit(VideoFrame frame) => _onFrame?.call(frame);
}
