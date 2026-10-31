/// Persists user-added UCI engine profiles to shared_preferences.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/generic_uci_engine_stub.dart';

/// Storage for [EngineProfile]s.
///
/// Profiles are addressed by [EngineProfile.id] throughout the app. The old
/// API addressed them by list index, which silently retargeted an edit or a
/// delete whenever the list was reordered, and left the saved engine selection
/// pointing at whatever had moved into that slot.
class EngineProfileStore {
  static const _key = 'uci_engine_profiles';
  SharedPreferences? _prefs;

  /// Set when the saved JSON had to be repaired (stale entries dropped or ids
  /// backfilled), so callers can persist the repaired list once.
  bool _needsRewrite = false;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// All saved profiles, oldest first.
  ///
  /// A corrupt or partially corrupt store yields the entries that could be
  /// read instead of throwing: an exception here used to make the Engine
  /// Manager screen fail to open at all, with no way to fix it from the UI.
  List<EngineProfile> get profiles {
    final json = _prefs?.getString(_key);
    if (json == null || json.isEmpty) return [];

    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      debugPrint('[EngineProfileStore] dropping unreadable profile list: $e');
      _needsRewrite = true;
      return [];
    }
    if (decoded is! List) {
      debugPrint('[EngineProfileStore] saved profiles are not a list');
      _needsRewrite = true;
      return [];
    }

    final profiles = <EngineProfile>[];
    final seenIds = <String>{};
    for (final entry in decoded) {
      if (entry is! Map) {
        _needsRewrite = true;
        continue;
      }
      EngineProfile profile;
      try {
        profile = EngineProfile.fromJson(Map<String, dynamic>.from(entry));
      } catch (e) {
        debugPrint('[EngineProfileStore] skipping unreadable profile: $e');
        _needsRewrite = true;
        continue;
      }
      if (profile.path.trim().isEmpty) {
        _needsRewrite = true;
        continue;
      }
      // A duplicate id would make "delete this profile" ambiguous again. The
      // replacement is derived from the id and the position rather than
      // generated, so every read of the same stored JSON agrees on it — a
      // random one changed on each parse and made an edit of the second entry
      // address an id that no read would ever produce again.
      if (seenIds.contains(profile.id)) {
        var repaired = '${profile.id}-dup';
        var n = 2;
        while (seenIds.contains(repaired)) {
          repaired = '${profile.id}-dup${n++}';
        }
        profile = EngineProfile(
          id: repaired,
          name: profile.name,
          path: profile.path,
          optionOverrides: Map.of(profile.optionOverrides),
          detectedName: profile.detectedName,
          detectedAuthor: profile.detectedAuthor,
          optionCount: profile.optionCount,
        );
        _needsRewrite = true;
      }
      seenIds.add(profile.id);
      if (!entry.containsKey('id') || entry['id'] == null) _needsRewrite = true;
      profiles.add(profile);
    }
    return profiles;
  }

  /// Loads the profiles, writing back the migrated list when the saved data
  /// had to be repaired (missing ids from older versions, unreadable entries).
  Future<List<EngineProfile>> load() async {
    await init();
    final list = profiles;
    if (_needsRewrite) {
      _needsRewrite = false;
      await save(list);
    }
    return list;
  }

  EngineProfile? byId(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> save(List<EngineProfile> profiles) async {
    await init();
    final json = jsonEncode(profiles.map((p) => p.toJson()).toList());
    await _prefs!.setString(_key, json);
  }

  /// Adds [profile]. Two profiles may share a path (the same binary with
  /// different option sets) but never share an id.
  Future<void> add(EngineProfile profile) async {
    await init();
    final list = profiles;
    if (list.any((p) => p.id == profile.id)) {
      throw ArgumentError.value(profile.id, 'profile.id', 'already exists');
    }
    list.add(profile);
    await save(list);
  }

  /// Replaces the profile with the same id.
  ///
  /// Returns false when no such profile is stored, which is the case when it
  /// was removed in the Engine Manager while another screen still held it.
  Future<bool> update(EngineProfile profile) async {
    await init();
    final list = profiles;
    final index = list.indexWhere((p) => p.id == profile.id);
    if (index < 0) return false;
    list[index] = profile;
    await save(list);
    return true;
  }

  Future<bool> remove(String id) async {
    await init();
    final list = profiles;
    final index = list.indexWhere((p) => p.id == id);
    if (index < 0) return false;
    list.removeAt(index);
    await save(list);
    return true;
  }

  /// Removes the profile at [index]. Kept for callers that only have a
  /// position; new code should use [remove] with an id.
  Future<void> removeAt(int index) async {
    await init();
    final list = profiles;
    if (index >= 0 && index < list.length) {
      await remove(list[index].id);
    }
  }

  /// Replaces the profile at [index]. Kept for callers that only have a
  /// position; new code should use [update] with a profile.
  Future<void> updateAt(int index, EngineProfile profile) async {
    await init();
    final list = profiles;
    if (index >= 0 && index < list.length) {
      list[index] = profile;
      await save(list);
    }
  }
}
