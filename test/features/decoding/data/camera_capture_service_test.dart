import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';
import 'package:simply_morse/features/decoding/domain/models/video_frame.dart';

import '../../../helpers/fake_camera_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraCaptureImpl', () {
    late CameraCaptureImpl capture;

    setUp(() {
      capture = CameraCaptureImpl();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'),
            (methodCall) async {
              if (methodCall.method == 'availableCameras') {
                return <dynamic>[];
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'),
            null,
          );
    });

    test('can be instantiated', () {
      expect(capture, isNotNull);
    });

    test('controller is null before initialization', () {
      expect(capture.controller, isNull);
    });

    test('isActive is false initially', () {
      expect(capture.isActive, isFalse);
    });

    test('isInitialized is false initially', () {
      expect(capture.isInitialized, isFalse);
    });

    test('isHighFrameRate is false initially', () {
      expect(capture.isHighFrameRate, isFalse);
    });

    test('stop can be called without initialization', () async {
      await capture.stop();
      // Should not throw
      expect(capture.isActive, isFalse);
    });

    test('hasPermission returns false when camera unavailable', () async {
      final result = await capture.hasPermission();
      // In test env, no cameras available, so should return false
      expect(result, isFalse);
    });

    test('initialize does not throw when no cameras available', () async {
      await capture.initialize();
      // Should complete without throwing
      expect(capture.controller, isNull);
      expect(capture.isInitialized, isFalse);
    });
  });

  group('CameraCaptureImpl frame downsampling (per-cell max)', () {
    // A separate top-level group: it drives CameraCaptureImpl via a
    // FakeCameraPlatform (CameraPlatform.instance), not the
    // MethodChannel mock the 'CameraCaptureImpl' group above uses —
    // keeping them in separate groups means neither setUp/tearDown
    // pair runs for the other's tests.
    late CameraPlatform originalCameraPlatform;
    late FakeCameraPlatform fakePlatform;
    late CameraCaptureImpl capture;

    setUp(() async {
      originalCameraPlatform = CameraPlatform.instance;
      fakePlatform = FakeCameraPlatform(previewSize: const Size(320, 240));
      CameraPlatform.instance = fakePlatform;

      capture = CameraCaptureImpl();
      await capture.initialize();
    });

    tearDown(() {
      CameraPlatform.instance = originalCameraPlatform;
    });

    test('a bright pixel off the strided sample grid is not lost', () async {
      expect(capture.isInitialized, isTrue);

      // 320x240 source (a typical ResolutionPreset.low buffer),
      // downsampled to 80x60 — a 4x4 source block per output cell.
      // Fill it with a dark background and light exactly one pixel,
      // NOT at (0, 0) — the block's top-left corner, which is the
      // one pixel a strided point-sample would read — so only a
      // full per-cell scan (max or mean) can find it.
      const srcWidth = 320;
      const srcHeight = 240;
      final bytes = Uint8List(srcWidth * srcHeight);
      bytes.fillRange(0, bytes.length, 20);
      bytes[2 * srcWidth + 2] = 250; // row 2, col 2 — inside the
      // 4x4 block for output cell (0, 0), off its top-left corner.

      VideoFrame? received;
      capture.startImageStream((frame) => received ??= frame);

      fakePlatform.emitFrame(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 0),
          planes: [CameraImagePlane(bytes: bytes, bytesPerRow: srcWidth)],
          width: srcWidth,
          height: srcHeight,
        ),
      );
      await pumpEventQueue();

      expect(received, isNotNull);
      // Output cell (0, 0) is luminance[0] (row-major, 80 wide).
      // The bright pixel must survive into it — a point-sample
      // would instead report the dark background at (0, 0).
      expect(received!.luminance[0], greaterThan(0.9));
    });

    test('the surrounding background stays dark', () async {
      const srcWidth = 320;
      const srcHeight = 240;
      final bytes = Uint8List(srcWidth * srcHeight);
      bytes.fillRange(0, bytes.length, 20);
      bytes[2 * srcWidth + 2] = 250;

      VideoFrame? received;
      capture.startImageStream((frame) => received ??= frame);

      fakePlatform.emitFrame(
        CameraImageData(
          format: const CameraImageFormat(ImageFormatGroup.yuv420, raw: 0),
          planes: [CameraImagePlane(bytes: bytes, bytesPerRow: srcWidth)],
          width: srcWidth,
          height: srcHeight,
        ),
      );
      await pumpEventQueue();

      // A neighboring cell whose 4x4 block never touches the lit
      // pixel — max-of-block must not bleed brightness sideways.
      expect(received!.luminance[1], closeTo(20 / 255, 0.01));
    });
  });
}
