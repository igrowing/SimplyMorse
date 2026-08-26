import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';
import 'package:simply_morse/core/services/screen_flash_service.dart';

void main() {
  group('ScreenFlashService', () {
    late ScreenFlashService service;

    setUp(() {
      service = ScreenFlashService();
    });

    tearDown(() {
      service.dispose();
    });

    test('isAvailable returns true', () async {
      expect(await service.isAvailable, isTrue);
    });

    test('isFlashing starts as false', () {
      expect(service.isFlashing.value, isFalse);
    });

    test('enable sets isFlashing to true', () async {
      expect(service.isFlashing.value, isFalse);

      await service.enable();

      expect(service.isFlashing.value, isTrue);
    });

    test('disable sets isFlashing to false', () async {
      await service.enable();
      expect(service.isFlashing.value, isTrue);

      await service.disable();

      expect(service.isFlashing.value, isFalse);
    });

    test('toggling enable then disable transitions correctly', () async {
      await service.enable();
      expect(service.isFlashing.value, isTrue);

      await service.disable();
      expect(service.isFlashing.value, isFalse);

      await service.enable();
      expect(service.isFlashing.value, isTrue);

      await service.disable();
      expect(service.isFlashing.value, isFalse);
    });

    test('isFlashing is a ValueNotifier<bool>', () {
      expect(service.isFlashing, isA<ValueNotifier<bool>>());
    });

    test('multiple enable calls keep value true', () async {
      await service.enable();
      await service.enable();
      await service.enable();

      expect(service.isFlashing.value, isTrue);
    });

    test('multiple disable calls keep value false', () async {
      await service.enable();
      await service.disable();
      await service.disable();

      expect(service.isFlashing.value, isFalse);
    });

    test('enable/disable notifies listeners', () async {
      var notificationCount = 0;
      service.isFlashing.addListener(() {
        notificationCount++;
      });

      await service.enable();
      expect(notificationCount, 1);

      await service.disable();
      expect(notificationCount, 2);
    });
  });

  group('usesScreenFlash', () {
    test('returns false in test environment', () {
      // kIsWeb is false in the test environment
      expect(usesScreenFlash, isFalse);
    });
  });
}
