// Browser benchmark storage.
//
// `shared_preferences` on web is localStorage: a few megabytes of key/value
// text, which is enough for the run documents this app writes (a run of 600
// games is a few hundred kilobytes). Keys are namespaced so a benchmark
// document can never collide with a player preference.
library;

import 'package:shared_preferences/shared_preferences.dart';

import 'benchmark_storage_base.dart';

/// Prefix for every document this storage owns.
const String kBenchmarkStoragePrefix = 'benchmark.';

/// Suffix for the last known-good copy of a document.
const String kBenchmarkStorageBackupSuffix = '#backup';

/// Storage in `shared_preferences` (localStorage on web).
class PrefsBenchmarkStorage implements BenchmarkStorage {
  SharedPreferences? _prefs;

  @override
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _instance() async {
    await init();
    return _prefs!;
  }

  @override
  Future<String?> read(String key) async {
    final prefs = await _instance();
    return prefs.getString('$kBenchmarkStoragePrefix$key');
  }

  @override
  Future<String?> readBackup(String key) async {
    final prefs = await _instance();
    return prefs.getString('$kBenchmarkStoragePrefix$key'
        '$kBenchmarkStorageBackupSuffix');
  }

  @override
  Future<void> write(String key, String value) async {
    final prefs = await _instance();
    final storageKey = '$kBenchmarkStoragePrefix$key';
    final existing = prefs.getString(storageKey);
    if (existing != null && existing.isNotEmpty) {
      await prefs.setString('$storageKey$kBenchmarkStorageBackupSuffix', existing);
    }
    await prefs.setString(storageKey, value);
  }

  @override
  Future<void> restore(String key, String value) async {
    final prefs = await _instance();
    await prefs.setString('$kBenchmarkStoragePrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    final prefs = await _instance();
    await prefs.remove('$kBenchmarkStoragePrefix$key');
    await prefs.remove('$kBenchmarkStoragePrefix$key'
        '$kBenchmarkStorageBackupSuffix');
  }

  @override
  Future<List<String>> keys(String prefix) async {
    final prefs = await _instance();
    final result = <String>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(kBenchmarkStoragePrefix)) continue;
      if (key.endsWith(kBenchmarkStorageBackupSuffix)) continue;
      final stripped = key.substring(kBenchmarkStoragePrefix.length);
      if (stripped.startsWith(prefix)) result.add(stripped);
    }
    result.sort();
    return result;
  }
}

/// The storage this platform uses.
BenchmarkStorage createDefaultBenchmarkStorage() => PrefsBenchmarkStorage();
