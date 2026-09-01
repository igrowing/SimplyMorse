import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simply_morse/core/constants/app_constants.dart';
import 'package:simply_morse/features/encoding/data/datasources/local_storage_datasource.dart';
import 'package:simply_morse/features/encoding/data/repositories/text_history_repository_impl.dart';

void main() {
  late LocalStorageDatasource dataSource;
  late TextHistoryRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dataSource = LocalStorageDatasource();
    await dataSource.init();
    repository = TextHistoryRepositoryImpl(dataSource);
  });

  group('TextHistoryRepositoryImpl', () {
    group('getAll', () {
      test('returns empty list when no history exists', () async {
        final history = await repository.getAll();
        expect(history, isEmpty);
      });

      test('returns saved entries', () async {
        await repository.save('Hello');
        await repository.save('World');

        final history = await repository.getAll();
        expect(history, hasLength(2));
        // Most recent is first
        expect(history[0], 'World');
        expect(history[1], 'Hello');
      });
    });

    group('save', () {
      test('adds new text to the front', () async {
        await repository.save('SOS');
        final history = await repository.getAll();

        expect(history, hasLength(1));
        expect(history.first, 'SOS');
      });

      test('moves existing text to front without duplicate', () async {
        await repository.save('Alpha');
        await repository.save('Bravo');
        await repository.save('Alpha');

        final history = await repository.getAll();
        expect(history, hasLength(2));
        expect(history.first, 'Alpha');
        expect(history[1], 'Bravo');
      });

      test('preserves order of other entries on re-save', () async {
        await repository.save('A');
        await repository.save('B');
        await repository.save('C');

        // Re-save B — should move to front, A and C stay in order
        await repository.save('B');

        final history = await repository.getAll();
        expect(history, equals(['B', 'C', 'A']));
      });

      test('enforces maximum history entries limit', () async {
        // Save more than maxHistoryEntries unique texts
        for (var i = 0; i < AppConstants.maxHistoryEntries + 5; i++) {
          await repository.save('text_$i');
        }

        final history = await repository.getAll();
        expect(
          history.length,
          AppConstants.maxHistoryEntries,
        );
      });

      test('keeps most recent entries when limit exceeded', () async {
        for (var i = 0; i < AppConstants.maxHistoryEntries + 3; i++) {
          await repository.save('text_$i');
        }

        final history = await repository.getAll();
        // The last 3 saved texts should be at the front
        // (most recent first, reversed order of insertion)
        const maxIdx = AppConstants.maxHistoryEntries + 2;
        expect(history[0], 'text_$maxIdx');
        expect(history[1], 'text_${maxIdx - 1}');
        expect(history[2], 'text_${maxIdx - 2}');
      });

      test('handles empty string', () async {
        await repository.save('');
        final history = await repository.getAll();

        expect(history, hasLength(1));
        expect(history.first, '');
      });
    });

    group('clear', () {
      test('removes all entries', () async {
        await repository.save('One');
        await repository.save('Two');
        await repository.save('Three');

        await repository.clear();
        final history = await repository.getAll();

        expect(history, isEmpty);
      });

      test('does nothing when history is already empty', () async {
        await repository.clear();
        final history = await repository.getAll();
        expect(history, isEmpty);
      });

      test('allows saving after clear', () async {
        await repository.save('Before');
        await repository.clear();
        await repository.save('After');

        final history = await repository.getAll();
        expect(history, hasLength(1));
        expect(history.first, 'After');
      });
    });

    group('persistence', () {
      test('data survives new datasource instance', () async {
        await repository.save('Persisted');

        // Create a new datasource and repository from the same
        // SharedPreferences mock
        final newDataSource = LocalStorageDatasource();
        await newDataSource.init();
        final newRepo = TextHistoryRepositoryImpl(newDataSource);

        final history = await newRepo.getAll();
        expect(history, hasLength(1));
        expect(history.first, 'Persisted');
      });
    });
  });
}
