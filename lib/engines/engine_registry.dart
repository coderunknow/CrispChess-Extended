/// One way to name, list and build an engine.
///
/// Before this file there were three unrelated notions of "which engine":
///
///  * `createEngine(String name)` — a display name, matched by `switch` on
///    string literals, unknown names silently falling back to the built-in
///    engine;
///  * the engine list in Settings — a hand-written `List<_EngineOption>` that
///    never included engines added through the Engine Manager;
///  * the match screen's own `_engineNames` list, which differed from both.
///
/// A user-added engine could therefore be stored, listed in the Engine Manager
/// and still be unreachable everywhere it mattered — and an unknown name did
/// not fail, it quietly played with a different engine than the one named.
///
/// This file gives every engine a stable id and one lookup used by settings,
/// play, hints, matches and multi-engine analysis:
///
///  * built-in: `builtin:<canonical name>` (the name [createEngine] accepts);
///  * user-added: `custom:<EngineProfile.id>`.
///
/// Display names are for display only — they are neither unique nor stable.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/engine_profile_store.dart';
import 'chess_engine.dart';
import 'chess_lm_engine.dart' show availableChessLmNames;
import 'engine_factory.dart';
import 'searchless_engine.dart' show availableSearchlessSizes;
import 'generic_uci_engine_stub.dart';

/// Prefix for engines that ship with the app.
const String kBuiltInEnginePrefix = 'builtin:';

/// Prefix for engines the user added through the Engine Manager.
const String kCustomEnginePrefix = 'custom:';

/// The engine used when nothing else can be resolved.
const String kFallbackEngineName = 'Built-in';

/// Built-in engines that can play a match or be benchmarked, in the order the
/// pickers show them.
///
/// One list, used by the match screen and by the Engine Lab. The match screen
/// used to keep its own copy: two lists that have to agree is one list too
/// many, and the Lab must not be able to benchmark an arrangement of engines
/// the app cannot otherwise run.
List<String> get builtInMatchEngines => [
      'Built-in',
      'Frozenight',
      'Stockfish',
      'Maia3 Dart',
      'ChessMamba',
      'Lc0',
      for (final size in availableSearchlessSizes) size.engineName,
      ...availableChessLmNames,
    ];

/// Id of the engine used when nothing else can be resolved.
String get fallbackEngineId => builtInEngineId(kFallbackEngineName);

/// Id for a built-in engine, given the canonical name [createEngine] accepts.
String builtInEngineId(String name) => '$kBuiltInEnginePrefix$name';

/// Id for a user-added engine profile.
String customEngineId(EngineProfile profile) =>
    customEngineIdForProfileId(profile.id);

/// Id for a user-added engine, given only its profile id (the form in which it
/// is persisted, so it survives the profile being edited).
String customEngineIdForProfileId(String profileId) =>
    '$kCustomEnginePrefix$profileId';

/// Whether [id] names a user-added engine.
bool isCustomEngineId(String id) => id.startsWith(kCustomEnginePrefix);

/// Whether [value] is an engine id at all (of either kind), as opposed to a
/// display name saved by a build that predates ids.
///
/// Settings that can hold either — the hint engine stored a name — use this to
/// decide which way to resolve a saved value.
bool looksLikeEngineId(String value) =>
    value.startsWith(kBuiltInEnginePrefix) ||
    value.startsWith(kCustomEnginePrefix);

/// The built-in engine name inside [id], or null for a custom engine.
String? builtInNameFromId(String id) =>
    id.startsWith(kBuiltInEnginePrefix)
        ? id.substring(kBuiltInEnginePrefix.length)
        : null;

/// The profile id inside [id], or null for a built-in engine.
String? customProfileIdFromId(String id) => id.startsWith(kCustomEnginePrefix)
    ? id.substring(kCustomEnginePrefix.length)
    : null;

/// Whether this platform can run user-supplied executables at all.
///
/// Web cannot: there is no process to spawn. Everywhere else the Engine
/// Manager offers the feature, and a failing binary is reported rather than
/// hidden — on iOS a downloaded binary cannot be executed unless it is signed
/// with the app, so custom engines there will usually fail to start; that is
/// reported honestly instead of being presented as working.
bool get customEnginesSupported => !kIsWeb;

/// Raised when a selected engine can no longer be built.
///
/// Separate from returning the built-in engine so the UI can say what happened
/// instead of silently playing with a different engine while still showing the
/// old one as selected.
class EngineUnavailableException implements Exception {
  final String engineId;
  final String reason;

  EngineUnavailableException(this.engineId, this.reason);

  @override
  String toString() => 'EngineUnavailableException($engineId): $reason';
}

/// The profile behind a custom engine id, or null when it was removed.
EngineProfile? profileForEngineId(String id, List<EngineProfile> profiles) {
  final profileId = customProfileIdFromId(id);
  if (profileId == null) return null;
  for (final profile in profiles) {
    if (profile.id == profileId) return profile;
  }
  return null;
}

/// A label for [id]. Custom engines keep their user-visible name; a custom id
/// whose profile has gone is labelled so rather than shown as a bare id.
String engineLabelForId(String id, List<EngineProfile> profiles) {
  final builtIn = builtInNameFromId(id);
  if (builtIn != null) return builtIn;
  final profile = profileForEngineId(id, profiles);
  if (profile != null) return profile.displayName;
  return 'Removed engine';
}

/// Builds the engine named by [id].
///
/// Throws [EngineUnavailableException] when the id cannot be honoured — a
/// custom engine that is not supported on this platform, or one whose profile
/// has been deleted — rather than substituting a different engine.
ChessEngine createEngineForId(
  String id, {
  required List<EngineProfile> profiles,
  int? playerElo,
  String? maia3Variant,
  int? hashMb,
  int? threads,
  String lc0Backend = 'auto',
}) {
  final builtIn = builtInNameFromId(id);
  if (builtIn != null) {
    // Not `createEngine`: that one falls back to the built-in engine for a name
    // it does not know, so `builtin:SomeEngineThatNeverExisted` used to be a
    // working selection that quietly played as Built-in while the settings
    // screen showed the other name.
    final engine = createEngineOrNull(
      builtIn,
      playerElo: playerElo,
      maia3Variant: maia3Variant,
      hashMb: hashMb,
      threads: threads,
      lc0Backend: lc0Backend,
    );
    if (engine == null) {
      throw EngineUnavailableException(
          id, 'no built-in engine is named "$builtIn"');
    }
    return engine;
  }

  if (!isCustomEngineId(id)) {
    throw EngineUnavailableException(id, 'not a recognised engine id');
  }
  if (!customEnginesSupported) {
    throw EngineUnavailableException(
        id, 'custom UCI engines cannot run in a browser');
  }
  final profile = profileForEngineId(id, profiles);
  if (profile == null) {
    throw EngineUnavailableException(id, 'the engine profile was removed');
  }
  return createEngineFromProfile(profile);
}

/// What the saved engine selection should be.
///
/// [savedId] is authoritative. Older builds saved only the display name, so
/// [savedName] is used to migrate it — including the case where the name is a
/// user-added engine's name, which is how a custom engine selected before ids
/// existed is kept rather than dropped.
///
/// Falls back to the built-in engine when neither resolves, which is what a
/// fresh install and a deleted custom engine both look like.
String resolveSelectedEngineId({
  String? savedId,
  String? savedName,
  required List<EngineProfile> profiles,
}) {
  if (savedId != null && savedId.isNotEmpty) {
    if (builtInNameFromId(savedId) != null) return savedId;
    if (isCustomEngineId(savedId)) {
      // Keep it only while the profile still exists; otherwise the selection
      // would name an engine that cannot be built.
      if (profileForEngineId(savedId, profiles) != null) return savedId;
      // The chosen profile is gone, and [savedId] is authoritative: a saved id
      // means this build wrote the selection, so the name beside it is only a
      // copy. Matching that name below would hand the app a *different* engine
      // whenever two profiles share a display name — which is exactly the case
      // the ids exist for — and it would do so silently, since nothing fails.
      return fallbackEngineId;
    }
  }

  if (savedName != null && savedName.isNotEmpty) {
    // A name saved without an id predates ids. If it is a built-in engine's
    // name, that is what the user had selected — a user-added engine that was
    // added later and happens to share the label must not take the selection
    // over, which would change which binary starts without anyone choosing it.
    if (isBuiltInEngineName(savedName)) return builtInEngineId(savedName);
    for (final profile in profiles) {
      if (profile.displayName == savedName || profile.name == savedName) {
        return customEngineId(profile);
      }
    }
    return builtInEngineId(savedName);
  }

  return fallbackEngineId;
}

/// Numbers repeated labels so a list that shows only labels can still tell its
/// entries apart: the first of a repeated label becomes `X (1)`, the second
/// `X (2)`, and a label that occurs once is returned unchanged.
///
/// The ids behind these labels are already distinct; this is about what the
/// user can *see*, in the match dropdowns, the tournament chips and the
/// hint-engine list, where two engines called "Stockfish" are one choice too
/// many.
List<String> disambiguateLabels(List<String> labels) {
  final totals = <String, int>{};
  for (final label in labels) {
    totals[label] = (totals[label] ?? 0) + 1;
  }
  final seen = <String, int>{};
  final out = <String>[];
  for (final label in labels) {
    if ((totals[label] ?? 0) > 1) {
      final n = (seen[label] ?? 0) + 1;
      seen[label] = n;
      out.add('$label ($n)');
    } else {
      out.add(label);
    }
  }
  return out;
}

/// The engine selections offered for engine-versus-engine matches.
///
/// Built-in names come from the caller (the match screen owns their ordering),
/// and every user-added profile is appended so custom engines can play too.
List<({String id, String label})> matchEngineChoices(
  Iterable<String> builtInNames,
  List<EngineProfile> profiles,
) {
  final choices = <({String id, String label})>[
    for (final name in builtInNames)
      (id: builtInEngineId(name), label: name),
  ];
  if (customEnginesSupported) {
    for (final profile in profiles) {
      choices.add((id: customEngineId(profile), label: profile.displayName));
    }
  }
  // Collisions are counted across built-ins *and* profiles: a user-added engine
  // called "Stockfish" collides with the built-in one just as badly as with
  // another profile.
  final labels = disambiguateLabels([for (final c in choices) c.label]);
  return [
    for (var i = 0; i < choices.length; i++) (id: choices[i].id, label: labels[i]),
  ];
}

/// Convenience for screens that keep their own store instance.
Future<List<EngineProfile>> loadEngineProfiles(EngineProfileStore store) =>
    store.load();
