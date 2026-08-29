import 'package:simply_morse/features/encoding/data/datasources/local_storage_datasource.dart';
import 'package:simply_morse/features/encoding/domain/repositories/settings_repository.dart';

/// SharedPreferences-backed implementation of
/// [SettingsRepository].
class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._dataSource);

  final LocalStorageDatasource _dataSource;

  @override
  Future<double> getSpeed() => _dataSource.getSpeed();

  @override
  Future<void> saveSpeed(double wpm) => _dataSource.saveSpeed(wpm);

  @override
  Future<double> getTone() => _dataSource.getTone();

  @override
  Future<void> saveTone(double hz) => _dataSource.saveTone(hz);

  @override
  Future<double> getInitialDelay() => _dataSource.getInitialDelay();

  @override
  Future<void> saveInitialDelay(double seconds) =>
      _dataSource.saveInitialDelay(seconds);
}
