// Persistence of user-added engine profiles.
//
// Profiles used to be addressed by their index in the saved list. Removing one
// renumbered every later entry, so an edit could write over a different
// engine, and the engine selection saved in preferences kept pointing at the
// old position. These cover the id-based API and the migration of data written
// by that older version.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';
import 'package:crispchess/services/engine_profile_store.dart';

const _key = 'uci_engine_profiles';

EngineProfile _profile(String name, String path, {String? id}) =>
    EngineProfile(id: id, name: name, path: path);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and reloads a profile with its id', () async {
    final store = EngineProfileStore();
    await store.init();

    final profile = _profile('Stockfish', '/usr/bin/stockfish');
    await store.add(profile);

    final reloaded = await EngineProfileStore().load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.id, profile.id);
    expect(reloaded.single.name, 'Stockfish');
    expect(reloaded.single.path, '/usr/bin/stockfish');
  });

  test('updates by id, not by position', () async {
    final store = EngineProfileStore();
    await store.init();
    final first = _profile('First', '/a');
    final second = _profile('Second', '/b');
    await store.add(first);
    await store.add(second);

    // Delete the first, then edit the second. With index-based updates this
    // wrote the edit over whichever profile had moved into index 0.
    await store.remove(first.id);
    final edited = second.copyWith(name: 'Renamed');
    expect(await store.update(edited), isTrue);

    final reloaded = await EngineProfileStore().load();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.name, 'Renamed');
    expect(reloaded.single.path, '/b');
  });

  test('updating an unknown profile reports it instead of inventing one',
      () async {
    final store = EngineProfileStore();
    await store.init();
    expect(await store.update(_profile('Ghost', '/nope', id: 'gone')), isFalse);
    expect(await EngineProfileStore().load(), isEmpty);
  });

  test('removing an unknown id is a no-op', () async {
    final store = EngineProfileStore();
    await store.init();
    final profile = _profile('Kept', '/a');
    await store.add(profile);
    expect(await store.remove('nope'), isFalse);
    expect(await EngineProfileStore().load(), hasLength(1));
  });

  test('option overrides survive a round trip', () async {
    final store = EngineProfileStore();
    await store.init();
    await store.add(EngineProfile(
      name: 'With options',
      path: '/a',
      optionOverrides: {'Hash': '256', 'Threads': '4'},
      detectedName: 'Real Engine 2.0',
      detectedAuthor: 'someone',
      optionCount: 12,
    ));

    final profile = (await EngineProfileStore().load()).single;
    expect(profile.optionOverrides, {'Hash': '256', 'Threads': '4'});
    expect(profile.detectedName, 'Real Engine 2.0');
    expect(profile.detectedAuthor, 'someone');
    expect(profile.optionCount, 12);
  });

  test('profiles saved without an id are migrated and rewritten', () async {
    // Exactly what the previous version wrote.
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        {'name': 'Legacy', 'path': '/usr/bin/legacy', 'options': <String, String>{}},
      ]),
    });

    final loaded = await EngineProfileStore().load();
    expect(loaded, hasLength(1));
    expect(loaded.single.id, isNotEmpty);

    // The id is persisted, so it is stable from here on.
    final raw = (await SharedPreferences.getInstance()).getString(_key)!;
    expect(raw, contains('"id"'));

    final second = await EngineProfileStore().load();
    expect(second.single.id, loaded.single.id);
  });

  test('a corrupt store yields an empty list instead of throwing', () async {
    SharedPreferences.setMockInitialValues({_key: 'not json at all'});
    expect(await EngineProfileStore().load(), isEmpty);
  });

  test('unreadable entries are dropped, readable ones kept', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        {'name': 'Good', 'path': '/good'},
        'nonsense',
        {'name': 'No path', 'path': ''},
      ]),
    });

    final loaded = await EngineProfileStore().load();
    expect(loaded, hasLength(1));
    expect(loaded.single.name, 'Good');
  });

  test('duplicate ids are repaired so a delete is unambiguous', () async {
    SharedPreferences.setMockInitialValues({
      _key: jsonEncode([
        {'id': 'same', 'name': 'One', 'path': '/one'},
        {'id': 'same', 'name': 'Two', 'path': '/two'},
      ]),
    });

    final loaded = await EngineProfileStore().load();
    expect(loaded, hasLength(2));
    expect(loaded[0].id, isNot(loaded[1].id));
  });

  test('adding a profile with an existing id is rejected', () async {
    final store = EngineProfileStore();
    await store.init();
    final profile = _profile('Once', '/a', id: 'fixed');
    await store.add(profile);
    await expectLater(store.add(profile), throwsArgumentError);
  });

  // An entry saved without an id used to be given a *random* one on every read,
  // and only `load()` wrote the migrated list back — so code that read the
  // store directly held ids that no later read reproduced, and `remove(id)` /
  // `update(profile)` matched nothing and silently did nothing. The fallback id
  // is now derived from the entry, and every mutation goes through `load()`.
  group('a store written by an older version (no ids)', () {
    const legacy = [
      {'name': 'Old Engine', 'path': '/usr/bin/old'},
      {'name': 'Older Engine', 'path': '/usr/bin/older'},
    ];

    test('remove() works on the id that load() reported', () async {
      SharedPreferences.setMockInitialValues(
          {_key: jsonEncode(legacy)});
      final store = EngineProfileStore();

      final profiles = await store.load();
      expect(profiles, hasLength(2));

      expect(await store.remove(profiles.first.id), isTrue,
          reason: 'the id load() handed out has to be actionable');
      final after = await EngineProfileStore().load();
      expect(after.map((p) => p.path), ['/usr/bin/older']);
    });

    test('update() works on the id that load() reported', () async {
      SharedPreferences.setMockInitialValues(
          {_key: jsonEncode(legacy)});
      final store = EngineProfileStore();

      final profiles = await store.load();
      final edited = profiles.first.copyWith(path: '/opt/moved');

      expect(await store.update(edited), isTrue);
      final after = await EngineProfileStore().load();
      expect(after.first.path, '/opt/moved');
    });

    test('mutating before any explicit load() still finds the entry', () async {
      // The manager screen used to read `profiles` directly, then call
      // `remove(id)` — the id came from a read the store itself could not
      // reproduce.
      SharedPreferences.setMockInitialValues(
          {_key: jsonEncode(legacy)});
      final store = EngineProfileStore();
      await store.init();
      final firstId = store.profiles.first.id;

      expect(await store.remove(firstId), isTrue);
      expect((await EngineProfileStore().load()).single.name, 'Older Engine');
    });
  });
}
