import 'package:flutter/foundation.dart' show kIsWeb;

import 'chess_engine.dart';
import 'dart_engine.dart';
import 'generic_uci_engine.dart'
    if (dart.library.js_interop) 'generic_uci_engine_web.dart';
import 'lc0_engine.dart' if (dart.library.js_interop) 'lc0_web_engine.dart';

// Conditional imports: web gets *_web_engine.dart, native gets the stub/FFI version.
// Both files export the same class names.
import 'stockfish_engine.dart'
    if (dart.library.js_interop) 'stockfish_web_engine.dart';

import 'frozenight_engine.dart'
    if (dart.library.js_interop) 'frozenight_web_engine.dart';

import 'maia3_dart_engine.dart'; // pure Dart, one implementation for every platform
import 'chessmamba_engine.dart'; // Dart + ONNX; native runtime where available
import 'chess_lm_engine.dart'; // language-model bot zoo
import 'ghost_engine.dart'; // plays like you: your openings, then Maia at your rating
import 'searchless_engine.dart'; // DeepMind's searchless transformers

import 'lynx_engine.dart'
    if (dart.library.js_interop) 'lynx_web_engine.dart';

/// Create a [ChessEngine] by name.
///
/// Falls back to the built-in engine for a name this app does not know. That is
/// the historical behaviour and [createEngineOrNull] exists for every caller
/// that would rather be told: resolving a *saved* selection through this
/// function is how a name that no longer exists silently became a different
/// engine than the one asked for.
///
/// All engines are either MIT-licensed or downloaded separately
/// (GPL engines run via JS runtime / separate process, never linked).
ChessEngine createEngine(String name, {
  int? playerElo,
  String? maia3Variant,
  int? hashMb,
  int? threads,
  String lc0Backend = 'auto',
}) =>
    createEngineOrNull(
      name,
      playerElo: playerElo,
      maia3Variant: maia3Variant,
      hashMb: hashMb,
      threads: threads,
      lc0Backend: lc0Backend,
    ) ??
    DartEngine();

/// Create a [ChessEngine] by name, or null when no engine has that name.
///
/// Unlike [createEngine] this never substitutes another engine, so a caller
/// that has to be truthful about which engine it built — anything resolving a
/// saved id or a user's choice — can refuse instead.
ChessEngine? createEngineOrNull(String name, {
  int? playerElo,
  String? maia3Variant,
  int? hashMb,
  int? threads,
  String lc0Backend = 'auto',
}) {
  switch (name) {
    case 'Built-in':
      return DartEngine(); // MIT, built-in
    case 'Stockfish':
      return StockfishEngine(variantId: maia3Variant); // Downloaded from CDN
    case 'Frozenight':
      return FrozenightEngine(); // MIT/Apache-2.0
    // 'Maia3' is the retired JS-bridge engine; kept as an alias so a stale
    // saved preference still gets a working Maia3. See
    // PreferencesService.migrateEngineName.
    case 'Maia3' || 'Maia3 Dart':
      return Maia3DartEngine(
        variantId: maia3Variant ?? '5m',
        playerElo: playerElo ?? 1500,
      ); // MIT (pure Dart)
    case 'ChessMamba':
      return ChessMambaEngine(); // MIT, weights downloaded on first use
    case ghostEngineName:
      return GhostEngine(); // built from the player's own games
    case 'Lc0':
      return Lc0Engine(
        variantId: maia3Variant,
        backend: lc0Backend,
      ); // GPL-3.0, downloaded separately
    case 'Lynx':
      // On web the id picks the WASM build (fast/AOT or small/interpreter);
      // on native it is ignored.
      return LynxEngine(variantId: maia3Variant); // MIT
    default:
      final sl = searchlessSizeNamed(name);
      if (sl != null) return SearchlessEngine(sl); // Apache-2.0 / CC BY 4.0
      final lm = chessLmSpecNamed(name);
      if (lm != null) return ChessLmEngine(lm); // MIT / Apache-2.0 models
      return null;
  }
}

/// Whether [name] is one of the engines that ship with the app.
///
/// The same dispatch as [createEngineOrNull], without building anything:
/// resolving a *saved* name has to prefer a built-in over a user-added engine
/// that happens to share its label, and constructing every candidate just to
/// see whether it exists would do work — and start downloads — for a question
/// about a string.
bool isBuiltInEngineName(String name) => switch (name) {
      'Built-in' ||
      'Stockfish' ||
      'Frozenight' ||
      'Maia3' ||
      'Maia3 Dart' ||
      'ChessMamba' ||
      ghostEngineName ||
      'Lc0' ||
      'Lynx' =>
        true,
      _ => searchlessSizeNamed(name) != null || chessLmSpecNamed(name) != null,
    };

/// Create a [ChessEngine] from a user-added engine profile.
///
/// Only available on native platforms (not web).
ChessEngine createEngineFromProfile(EngineProfile profile) {
  if (kIsWeb) throw UnsupportedError('Custom engines not available on web');
  return GenericUciEngine(profile);
}
