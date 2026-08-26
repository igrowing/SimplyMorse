import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/features/decoding/data/camera_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CameraCaptureImpl', () {
    late CameraCaptureImpl capture;

    setUp(() {
      capture = CameraCaptureImpl();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/camera'),
            (MethodCall methodCall) async {
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
}
