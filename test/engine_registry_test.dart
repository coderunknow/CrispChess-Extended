// Engine identity: built-in engines and user-added engines named the same way.
//
// The point of these ids is that a user-added engine can be selected, played
// against, used for hints and entered into a match without any of those paths
// having to guess from a display name — which is neither unique nor stable, and
// which `createEngine` silently mapped to the built-in engine when it did not
// recognise it.
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/engine_registry.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';

EngineProfile _profile(String name, {String? id, String? path}) => EngineProfile(
      id: id,
      name: name,
      path: path ?? '/opt/chess/$name',
    );

void main() {
  group('ids', () {
    test('a built-in id round-trips to its name', () {
      final id = builtInEngineId('Stockfish');
      expect(id, 'builtin:Stockfish');
      expect(builtInNameFromId(id), 'Stockfish');
      expect(customProfileIdFromId(id), isNull);
      expect(isCustomEngineId(id), isFalse);
    });

    test('a custom id carries the profile id, not the display name', () {
      final profile = _profile('My Engine', id: 'abc123');
      final id = customEngineId(profile);
      expect(id, 'custom:abc123');
      expect(customProfileIdFromId(id), 'abc123');
      expect(builtInNameFromId(id), isNull);
      expect(isCustomEngineId(id), isTrue);
    });

    test('two profiles with the same name get different ids', () {
      final first = _profile('Stockfish', path: '/opt/a/stockfish');
      final second = _profile('Stockfish', path: '/opt/b/stockfish');
      expect(first.id, isNot(second.id));
      expect(customEngineId(first), isNot(customEngineId(second)));
    });

    test('a profile keeps its id when copied', () {
      final profile = _profile('Foo', id: 'stable');
      expect(profile.copyWith(name: 'Bar').id, 'stable');
    });

    test('a profile without an id gets a fresh, unique one', () {
      final a = _profile('A');
      final b = _profile('B');
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id));
    });
  });

  group('profile lookup', () {
    final dead = _profile('Gone', id: 'gone');
    final other = _profile('Other', id: 'other');

    test('finds the profile behind a custom id', () {
      expect(profileForEngineId(customEngineId(dead), [dead, other]), dead);
    });

    test('returns null for a built-in id', () {
      expect(profileForEngineId(builtInEngineId('Lynx'), [dead]), isNull);
    });

    test('returns null when the profile was removed', () {
      expect(profileForEngineId('custom:missing', [dead]), isNull);
    });

    test('labels', () {
      final profiles = [dead];
      expect(engineLabelForId(builtInEngineId('Built-in'), profiles),
          'Built-in');
      expect(engineLabelForId(customEngineId(dead), profiles), 'Gone');
      expect(engineLabelForId('custom:missing', profiles), isNotEmpty);
    });

    test('displayName falls back from a blank name to the detected one', () {
      final profile = EngineProfile(
        name: '',
        path: '/usr/bin/foo',
        detectedName: 'Detected 1.0',
      );
      expect(profile.displayName, 'Detected 1.0');
    });
  });

  group('resolveSelectedEngineId', () {
    final custom = _profile('My Engine', id: 'mine');

    test('a built-in id is kept as-is', () {
      expect(
        resolveSelectedEngineId(
            savedId: builtInEngineId('Lc0'), profiles: [custom]),
        builtInEngineId('Lc0'),
      );
    });

    test('a custom id with a live profile is kept', () {
      expect(
        resolveSelectedEngineId(
            savedId: customEngineId(custom), profiles: [custom]),
        customEngineId(custom),
      );
    });

    test('a custom id whose profile is gone falls back to the built-in', () {
      expect(
        resolveSelectedEngineId(savedId: 'custom:deleted', profiles: [custom]),
        fallbackEngineId,
      );
    });

    test('a legacy saved name is migrated, including a custom engine name', () {
      // Old builds stored only the display name. A user who had a custom
      // engine selected used to land back on the built-in engine.
      expect(
        resolveSelectedEngineId(savedName: 'My Engine', profiles: [custom]),
        customEngineId(custom),
      );
      expect(
        resolveSelectedEngineId(savedName: 'Lynx', profiles: [custom]),
        builtInEngineId('Lynx'),
      );
    });

    test('nothing saved resolves to the built-in engine', () {
      expect(resolveSelectedEngineId(profiles: const []), fallbackEngineId);
    });
  });

  group('createEngineForId', () {
    test('builds a built-in engine', () {
      final engine = createEngineForId(fallbackEngineId, profiles: const []);
      expect(engine.name, 'Built-in');
      engine.dispose();
    });

    test('an unknown built-in id is reported, not silently replaced', () {
      // `createEngine` historically answered an unknown name with the built-in
      // engine, so this id used to build a working engine while the settings
      // screen went on showing a name that does not exist.
      expect(
        () => createEngineForId('builtin:NoSuchEngine', profiles: const []),
        throwsA(isA<EngineUnavailableException>()),
      );
      expect(
        () => createEngineForId('builtin:', profiles: const []),
        throwsA(isA<EngineUnavailableException>()),
      );
    });

    test('an unknown custom id is reported, not silently replaced', () {
      expect(
        () => createEngineForId('custom:missing', profiles: const []),
        throwsA(isA<EngineUnavailableException>()),
      );
    });

    test('the fallback id names the built-in engine', () {
      expect(builtInNameFromId(fallbackEngineId), 'Built-in',
          reason: 'kFallbackEngineName and fallbackEngineId must agree');
      expect(DartEngine().name, 'Built-in');
    });
  });

  group('looksLikeEngineId', () {
    test('accepts both id kinds', () {
      expect(looksLikeEngineId(builtInEngineId('Lynx')), isTrue);
      expect(looksLikeEngineId(customEngineIdForProfileId('abc')), isTrue);
    });

    test('rejects the names saved by older builds', () {
      // The hint-engine setting used to store a display name; telling the two
      // apart is what lets it be migrated instead of dropped.
      expect(looksLikeEngineId('Lynx'), isFalse);
      expect(looksLikeEngineId('same'), isFalse);
      expect(looksLikeEngineId(''), isFalse);
    });
  });

  group('matchEngineChoices', () {
    test('lists built-ins then user-added engines', () {
      final custom = _profile('Mine', id: 'm1');
      final choices = matchEngineChoices(['Built-in', 'Lynx'], [custom]);
      expect(choices.map((c) => c.id).toList(), [
        builtInEngineId('Built-in'),
        builtInEngineId('Lynx'),
        customEngineId(custom),
      ]);
      expect(choices.last.label, 'Mine');
    });
  });
}
