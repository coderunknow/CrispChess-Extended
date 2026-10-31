/// Key/value documents for the benchmark history, without a platform.
///
/// The interface is deliberately tiny: three operations and a key listing. The
/// native implementation writes files (atomically, with the previous version
/// kept as `.bak`); the browser one uses `shared_preferences`, because a
/// browser has no filesystem. Both are good enough for a few hundred runs of a
/// few thousand games, and neither needs a new native plugin on six platforms.
library;

/// A place to keep benchmark documents.
abstract class BenchmarkStorage {
  /// Prepares the storage. Safe to call more than once.
  Future<void> init();

  /// The document stored under [key], or null.
  Future<String?> read(String key);

  /// The last known-good copy of [key], or null when the backend keeps none.
  ///
  /// This exists so the store can recover a document whose primary copy failed
  /// its checksum: reading the primary, failing, and deleting both files is how
  /// a corrupt update used to destroy the last valid history. Backends without
  /// a recovery copy return null, and the store reports corruption instead of
  /// pretending it recovered.
  Future<String?> readBackup(String key) async => null;

  /// Stores [value] under [key], atomically where the platform allows it.
  ///
  /// Implementations keep the previous value as the recovery copy.
  Future<void> write(String key, String value);

  /// Puts a known-good document back without rotating the recovery copy.
  ///
  /// Recovery used to go through [write], which first copies the current —
  /// corrupt — primary over `.bak`. The store had just archived those bad
  /// bytes, so nothing was lost irrecoverably, but the good second copy was
  /// replaced by garbage: one more corruption and the run would be gone. A
  /// restore writes the primary only.
  Future<void> restore(String key, String value) => write(key, value);

  /// Removes [key]; missing keys are not an error.
  Future<void> delete(String key);

  /// Every key that starts with [prefix].
  Future<List<String>> keys(String prefix);
}

/// In-memory storage, for tests and for the (unlikely) case where neither
/// platform backend can be created.
class MemoryBenchmarkStorage implements BenchmarkStorage {
  final Map<String, String> _documents = {};

  @override
  Future<void> init() async {}

  @override
  Future<String?> read(String key) async => _documents[key];

  /// The in-memory backend keeps no second copy, so there is nothing to
  /// recover; it reports that rather than inventing one.
  @override
  Future<String?> readBackup(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    _documents[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _documents.remove(key);
  }

  @override
  Future<List<String>> keys(String prefix) async => [
        for (final key in _documents.keys)
          if (key.startsWith(prefix)) key
      ];
}
