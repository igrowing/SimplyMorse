import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/data/datasources/local_storage_datasource.dart';
import 'package:simply_morse/features/encoding/data/repositories/settings_repository_impl.dart';

void main() {
  late LocalStorageDatasource dataSource;
  late SettingsRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dataSource = LocalStorageDatasource();
    await dataSource.init();
    repository = SettingsRepositoryImpl(dataSource);
  });

  group('SettingsRepositoryImpl', () {
    group('getSpeed', () {
      test('returns default speed when not set', () async {
        final speed = await repository.getSpeed();
        expect(speed, AppConstants.defaultSpeedWpm);
      });

      test('returns saved speed after saveSpeed', () async {
        await repository.saveSpeed(15);
        final speed = await repository.getSpeed();
        expect(speed, 15.0);
      });

      test('returns updated speed after multiple saves', () async {
        await repository.saveSpeed(5);
        expect(await repository.getSpeed(), 5.0);

        await repository.saveSpeed(25);
        expect(await repository.getSpeed(), 25.0);
      });
    });

    group('saveSpeed', () {
      test('persists minimum speed value', () async {
        await repository.saveSpeed(AppConstants.minSpeedWpm);
        expect(
          await repository.getSpeed(),
          AppConstants.minSpeedWpm,
        );
      });

      test('persists maximum speed value', () async {
        await repository.saveSpeed(AppConstants.maxSpeedWpm);
        expect(
          await repository.getSpeed(),
          AppConstants.maxSpeedWpm,
        );
      });

      test('persists fractional speed value', () async {
        await repository.saveSpeed(12.5);
        expect(await repository.getSpeed(), 12.5);
      });
    });

    group('getTone', () {
      test('returns default tone when not set', () async {
        final tone = await repository.getTone();
        expect(tone, AppConstants.defaultToneHz);
      });

      test('returns saved tone after saveTone', () async {
        await repository.saveTone(500);
        final tone = await repository.getTone();
        expect(tone, 500.0);
      });
    });

    group('saveTone', () {
      test('persists minimum tone value', () async {
        await repository.saveTone(AppConstants.minToneHz);
        expect(
          await repository.getTone(),
          AppConstants.minToneHz,
        );
      });

      test('persists maximum tone value', () async {
        await repository.saveTone(AppConstants.maxToneHz);
        expect(
          await repository.getTone(),
          AppConstants.maxToneHz,
        );
      });

      test('persists fractional tone value', () async {
        await repository.saveTone(742.5);
        expect(await repository.getTone(), 742.5);
      });
    });

    group('getInitialDelay', () {
      test('returns default initial delay when not set', () async {
        final delay = await repository.getInitialDelay();
        expect(delay, AppConstants.defaultInitialDelaySec);
      });

      test('returns saved initial delay after saveInitialDelay', () async {
        await repository.saveInitialDelay(5);
        final delay = await repository.getInitialDelay();
        expect(delay, 5.0);
      });
    });

    group('saveInitialDelay', () {
      test('persists zero delay', () async {
        await repository.saveInitialDelay(0);
        expect(await repository.getInitialDelay(), 0.0);
      });

      test('persists maximum delay', () async {
        await repository.saveInitialDelay(
          AppConstants.maxInitialDelaySec,
        );
        expect(
          await repository.getInitialDelay(),
          AppConstants.maxInitialDelaySec,
        );
      });

      test('persists fractional delay', () async {
        await repository.saveInitialDelay(3.5);
        expect(await repository.getInitialDelay(), 3.5);
      });
    });

    test('speed, tone and delay are independent', () async {
      await repository.saveSpeed(20);
      await repository.saveTone(450);
      await repository.saveInitialDelay(10);

      expect(await repository.getSpeed(), 20.0);
      expect(await repository.getTone(), 450.0);
      expect(await repository.getInitialDelay(), 10.0);

      await repository.saveSpeed(10);
      expect(await repository.getSpeed(), 10.0);
      expect(await repository.getTone(), 450.0);
      expect(await repository.getInitialDelay(), 10.0);
    });
  });
}
