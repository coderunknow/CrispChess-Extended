// Stable engine identity: the thing every benchmark result is keyed by.
//
// The regression this covers: results, standings and ratings used to be keyed
// by `ChessEngine.name`, so two custom profiles that share a display name — or
// one profile renamed between runs — merged or split their numbers.
import 'package:crispchess/bench/benchmark_fingerprint.dart' show ExecutableStat;
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/engine_registry.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart' show EngineProfile;
import 'package:flutter_test/flutter_test.dart';

EngineProfile _profile(String id, {String name = 'Stockfish'}) =>
    EngineProfile(id: id, name: name, path: '/engines/$id');

void main() {
  group('identity', () {
    test('saved overrides affect identity and run options take precedence', () {
      EngineIdentity identity(String hash, {Map<String, String> run = const {}}) =>
          EngineIdentity.forCustom(
            profile: EngineProfile(id: 'p', name: 'X', path: '/engine',
                optionOverrides: {'Hash': hash, 'Threads': '2'}),
            detectedName: 'X',
            detectedAuthor: null,
            binarySha256: '1' * 64,
            configuration: run,
          );
      final before = identity('16');
      final after = identity('32');
      expect(after.changeFrom(before), 'configuration changed');
      expect(after.ratingKey, isNot(before.ratingKey));
      final overridden = identity('16', run: {'Hash': '64'});
      expect(overridden.configuration, {'Hash': '64', 'Threads': '2'});
      expect(EngineIdentity.fromJson(after.toJson()).configuration,
          after.configuration);
    });

    test('two profiles with the same display name stay distinct', () {
      final a = EngineIdentity.forCustom(
        profile: _profile('a'),
        detectedName: 'Stockfish 17',
        detectedAuthor: 'the Stockfish developers',
        binarySha256: 'a' * 64,
      );
      final b = EngineIdentity.forCustom(
        profile: _profile('b'),
        detectedName: 'Stockfish 17',
        detectedAuthor: 'the Stockfish developers',
        binarySha256: 'a' * 64,
      );

      expect(a.displayName, b.displayName);
      expect(a.engineId, isNot(b.engineId));
      expect(a.ratingKey, isNot(b.ratingKey));
      // Same binary, same options, but a different profile is a different
      // engine as far as the history is concerned.
      expect(a.matchesVersionOf(b), isFalse);
    });

    test('a renamed profile keeps its identity and its self-reported name', () {
      final original = EngineIdentity.forCustom(
        profile: _profile('p', name: 'My engine'),
        detectedName: 'Ethereal 14.25',
        detectedAuthor: 'Andrew Grant',
        binarySha256: 'b' * 64,
      );
      final renamed = EngineIdentity.forCustom(
        profile: _profile('p', name: 'Ethereal (fast one)'),
        detectedName: 'Ethereal 14.25',
        detectedAuthor: 'Andrew Grant',
        binarySha256: 'b' * 64,
      );

      expect(renamed.engineId, original.engineId);
      expect(renamed.engineName, 'Ethereal 14.25');
      expect(renamed.engineName, original.engineName);
      expect(renamed.matchesVersionOf(original), isTrue);
    });

    test('a changed binary is a changed version', () {
      final before = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'X',
        detectedAuthor: 'Y',
        binarySha256: '1' * 64,
      );
      final after = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'X',
        detectedAuthor: 'Y',
        binarySha256: '2' * 64,
      );

      expect(after.changeFrom(before), 'binary changed');
      expect(after.matchesVersionOf(before), isFalse);
    });

    test('a changed configuration is a changed measurement', () {
      final singleThread = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'X',
        detectedAuthor: 'Y',
        binarySha256: '1' * 64,
        configuration: const {'Threads': '1'},
      );
      final fourThreads = singleThread.withConfiguration(const {'Threads': '4'});

      expect(fourThreads.changeFrom(singleThread), 'configuration changed');
      expect(fourThreads.fingerprint, singleThread.fingerprint);
      expect(fourThreads.engineId, singleThread.engineId);
    });

    test('a binary that cannot be hashed falls back to stat, then unavailable',
        () {
      final withStat = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'X',
        detectedAuthor: 'Y',
        stat: const ExecutableStat(sizeBytes: 1024, modifiedMillis: 42),
      );
      expect(withStat.fingerprintKind, 'stat');
      expect(withStat.fingerprint, 'stat:1024:42');

      final unknown = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'X',
        detectedAuthor: 'Y',
      );
      expect(unknown.fingerprintKind, 'unavailable');
      expect(unknown.fingerprint, 'unavailable');
    });

    test('a built-in fingerprint carries the app build and engine version', () {
      final first = EngineIdentity.forBuiltIn(
          name: 'Frozenight', engineVersion: '1.0', appBuild: '2.3.2+18');
      final second = EngineIdentity.forBuiltIn(
          name: 'Frozenight', engineVersion: '1.0', appBuild: '2.3.3+19');

      expect(first.fingerprint, contains('2.3.2+18'));
      expect(second.fingerprint, contains('2.3.3+19'));
      expect(second.changeFrom(first), 'binary changed');
      expect(first.kind, 'builtin');
      expect(first.engineId, builtInEngineId('Frozenight'));
    });

    test('the cohort key separates platforms and backends', () {
      final builtIn = EngineIdentity.forBuiltIn(
          name: 'Stockfish', engineVersion: '17', appBuild: 'x');
      expect(builtIn.cohortKey, '${builtIn.platform}/${builtIn.backend}');
      // A WASM Stockfish and a native Stockfish must never share a rating pool.
      expect(builtIn.backend, anyOf('wasm', 'native-process'));
    });

    test('JSON round trip keeps every field a report needs', () {
      final identity = EngineIdentity.forCustom(
        profile: _profile('p'),
        detectedName: 'Ethereal',
        detectedAuthor: 'Andrew Grant',
        binarySha256: 'f' * 64,
        advertisedOptions: ['Threads', 'Hash', 'UCI_ShowWDL'],
        configuration: const {'Threads': '2'},
      );
      final restored = EngineIdentity.fromJson(identity.toJson());

      expect(restored.engineId, identity.engineId);
      expect(restored.engineName, identity.engineName);
      expect(restored.author, identity.author);
      expect(restored.fingerprint, identity.fingerprint);
      expect(restored.fingerprintKind, identity.fingerprintKind);
      expect(restored.configurationDigest, identity.configurationDigest);
      expect(restored.advertisedOptionCount, 3);
      expect(restored.configuration, {'Threads': '2'});
      expect(restored.matchesVersionOf(identity), isTrue);
    });

    test('a document from an unknown engine still loads, marked unknown', () {
      final restored = EngineIdentity.fromJson(const {});
      expect(restored.engineId, 'unknown');
      expect(restored.fingerprint, 'unavailable');
      expect(restored.platform, 'unknown');
    });
  });

  group('digest', () {
    test('is deterministic, order-sensitive and 64 hex characters', () {
      // The *callers* sort (see `withConfiguration` and `digestOf`'s use in
      // engine_identity.dart), so the digest itself is a plain hash of the
      // joined parts; hashing is not the place to hide an ordering bug.
      expect(digestOf(['a', 'b']), digestOf(['a', 'b']));
      expect(digestOf(['a', 'b']), isNot(digestOf(['b', 'a'])));
      expect(digestOf(['a=b']), isNot(digestOf(['a=c'])));
      expect(digestOf(['a', 'b']).length, 64);
    });

    test('a configuration digest does not depend on the map order', () {
      final first = EngineIdentity.forBuiltIn(
        name: 'Built-in',
        engineVersion: '1',
        appBuild: 'x',
        configuration: const {'Threads': '2', 'Hash': '64'},
      );
      final second = EngineIdentity.forBuiltIn(
        name: 'Built-in',
        engineVersion: '1',
        appBuild: 'x',
        configuration: const {'Hash': '64', 'Threads': '2'},
      );
      expect(first.configurationDigest, second.configurationDigest);
      expect(first.matchesVersionOf(second), isTrue);
    });
  });
}
