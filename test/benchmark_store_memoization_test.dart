import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:crispchess/bench/benchmark_fingerprint.dart' show ExecutableStat;
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/benchmark_storage.dart';
import 'package:crispchess/bench/benchmark_storage_io.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';

/// Counts reads per storage key so a test can prove a cache hit without
/// touching private state.
class CountingStorage implements BenchmarkStorage {
  final BenchmarkStorage inner;
  final Map<String, int> reads = {};

  CountingStorage(this.inner);

  @override
  Future<void> init() => inner.init();

  @override
  Future<String?> read(String key) async {
    reads[key] = (reads[key] ?? 0) + 1;
    return inner.read(key);
  }

  @override
  Future<String?> readBackup(String key) async => inner.readBackup(key);

  @override
  Future<void> write(String key, String value) async {
    await inner.write(key, value);
  }

  @override
  Future<void> restore(String key, String value) async {
    await inner.restore(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await inner.delete(key);
  }

  @override
  Future<List<String>> keys(String prefix) async => inner.keys(prefix);
}

/// Regression tests for the dev6 cache memoization.
///
/// The Engine Manager open path used to decode `fingerprints.json` and
/// `identities.json` from disk on every call — several times per open, on
/// every visit. The memo must hold across reads, refresh on writes and
/// invalidate when the file changes on disk.
void main() {
  late Directory temp;
  late CountingStorage counting;
  late BenchmarkStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('store-memo-');
    counting = CountingStorage(
        FileBenchmarkStorage(rootOverride: temp, directoryName: 'benchmark'));
    store = BenchmarkStore(storage: counting);
    await store.init();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  Future<File> writeBinary(String name, List<int> bytes) async {
    final file = File('${temp.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  test('repeated profile fingerprints hit the memo, not the disk',
      () async {
    final binary = await writeBinary('engine.bin', List.filled(4096, 7));
    final profile = EngineProfile(id: 'prof-1', name: 'E', path: binary.path);

    final first = await store.fingerprintForProfile(profile.id, profile.path);
    expect(first.sha256, isNotNull);
    final readsAfterFirst =
        (counting.reads['fingerprints'] ?? 0) + (counting.reads['fingerprints.bak'] ?? 0);
    expect(readsAfterFirst, greaterThan(0));

    final second = await store.fingerprintForProfile(profile.id, profile.path);
    expect(second.sha256, first.sha256);
    expect(second.stat, first.stat);
    final readsAfterSecond =
        (counting.reads['fingerprints'] ?? 0) + (counting.reads['fingerprints.bak'] ?? 0);
    expect(readsAfterSecond, readsAfterFirst,
        reason: 'a second identical read must be served from memory');
  });

  test('repeated knownIdentities hits the memo, and a copy is returned',
      () async {
    final binary = await writeBinary('engine2.bin', List.filled(2048, 3));
    final profile = EngineProfile(id: 'prof-2', name: 'E2', path: binary.path);
    final fingerprint =
        await store.fingerprintForProfile(profile.id, profile.path);
    final identity = <String, dynamic>{
      'engineId': 'custom:${profile.id}',
      'displayName': profile.displayName,
      'engineName': profile.displayName,
      'engineVersion': '',
      'kind': 'custom',
      'platform': 'test',
      'backend': 'custom-uci',
      'fingerprint': 'sha256:${fingerprint.sha256}',
      'fingerprintKind': 'sha256',
    };
    await store.storage.write('identities', jsonEncode({
      'custom:${profile.id}': identity,
    }));

    final first = await store.knownIdentities();
    expect(first, contains('custom:${profile.id}'));
    final readsAfterFirst =
        (counting.reads['identities'] ?? 0) + (counting.reads['identities.bak'] ?? 0);

    final second = await store.knownIdentities();
    expect(second.keys, first.keys);
    final readsAfterSecond =
        (counting.reads['identities'] ?? 0) + (counting.reads['identities.bak'] ?? 0);
    expect(readsAfterSecond, readsAfterFirst);

    // A mutation of the returned map must not reach the memo.
    second['mutated'] = first.values.first;
    final third = await store.knownIdentities();
    expect(third, isNot(contains('mutated')));
  });

  test('the native-library fingerprint caches and invalidates on change',
      () async {
    final binary = await writeBinary('frozenight.dll', List.filled(8192, 42));

    final first = await store.fingerprintForNativeLibrary(binary.path);
    expect(first.sha256, isNotNull);
    final readsAfterFirst = (counting.reads['nativelibs'] ?? 0);
    expect(readsAfterFirst, greaterThan(0));

    final second = await store.fingerprintForNativeLibrary(binary.path);
    expect(second.sha256, first.sha256);
    expect(counting.reads['nativelibs'], readsAfterFirst,
        reason: 'unchanged library: memo hit, no disk read');

    // Replacing the binary (new size) invalidates the entry: the next lookup
    // re-hashes and re-reads the cache document.
    await binary.writeAsBytes(List.filled(4096, 42), flush: true);
    final third = await store.fingerprintForNativeLibrary(binary.path);
    expect(third.sha256, isNot(first.sha256));
    expect(third.stat!.sizeBytes, 4096);
  });

  test('a stat change invalidates the profile fingerprint cache', () async {
    final binary = await writeBinary('engine3.bin', List.filled(1024, 1));
    final profile = EngineProfile(id: 'prof-3', name: 'E3', path: binary.path);
    final first = await store.fingerprintForProfile(profile.id, profile.path);

    // Same content, later mtime: the stat-based key changes, the file is
    // re-hashed, and the digest must stay correct.
    final later = DateTime.now().add(const Duration(days: 1));
    await File(binary.path).setLastModified(later);
    final second = await store.fingerprintForProfile(profile.id, profile.path);
    expect(second.sha256, first.sha256,
        reason: 'same bytes still hash the same');
    expect(second.stat!.modifiedMillis, isNot(first.stat!.modifiedMillis));
  });

  test('an ExecutableStat survives a JSON round trip', () {
    const stat = ExecutableStat(sizeBytes: 1234, modifiedMillis: 5678);
    final restored = ExecutableStat.fromJson(stat.toJson());
    expect(restored, stat);
  });
}
