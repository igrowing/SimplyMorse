/// Repository interface for managing text history persistence.
abstract interface class TextHistoryRepository {
  /// Returns all saved text entries, most recent first.
  Future<List<String>> getAll();

  /// Saves [text] to history. If it already exists, it is moved
  /// to the front. Maximum entries are enforced.
  Future<void> save(String text);

  /// Clears all history entries.
  Future<void> clear();
}
