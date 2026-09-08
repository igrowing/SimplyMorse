import 'dart:async';
import 'dart:typed_data';

import 'package:record_platform_interface/record_platform_interface.dart';

/// Fake [RecordPlatform] for tests — an in-memory recorder whose
/// PCM stream is fed by the test via [emit].
class FakeRecordPlatform extends RecordPlatform {
  final _controller = StreamController<Uint8List>.broadcast();
  final events = <String>[];
  bool permissionGranted = true;

  /// Pushes raw PCM bytes into the recorder's stream.
  void emit(Uint8List data) => _controller.add(data);

  void close() => _controller.close();

  @override
  Future<void> create(String recorderId) async {
    events.add('create');
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    events.add('startStream');
    return _controller.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    events.add('stop');
    await _controller.close();
    return null;
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permissionGranted;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> dispose(String recorderId) async {}

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: 0, max: 0);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async => [];

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  Stream<RecordState> onStateChanged(String recorderId) => const Stream.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}
