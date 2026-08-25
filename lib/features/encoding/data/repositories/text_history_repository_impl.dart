import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/data/datasources/local_storage_datasource.dart';
import 'package:simply_morse/features/encoding/domain/repositories/text_history_repository.dart';

/// SharedPreferences-backed implementation of
/// [TextHistoryRepository].
class TextHistoryRepositoryImpl implements TextHistoryRepository {
  TextHistoryRepositoryImpl(this._dataSource);

  final LocalStorageDatasource _dataSource;

  @override
  Future<List<String>> getAll() => _dataSource.getTextHistory();

  @override
  Future<void> save(String text) async {
    final history = await getAll();
    history
      ..remove(text)
      ..insert(0, text);
    if (history.length > AppConstants.maxHistoryEntries) {
      history.removeRange(
        AppConstants.maxHistoryEntries,
        history.length,
      );
    }
    await _dataSource.saveTextHistory(history);
  }

  @override
  Future<void> clear() => _dataSource.clearTextHistory();
}
