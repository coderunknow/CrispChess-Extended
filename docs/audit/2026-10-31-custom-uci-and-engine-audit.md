# Audit — custom UCI engine integration and engine correctness

**Date:** 2026-10-31
**Branch:** `arena/6eac624a-scrispchess-extended`
**Base commit:** `0d01798daf9661076675f8505b4cc6995a6529da` (`main`, single squashed commit)
**Repository:** `coderunknow/ScrispChess-Extended` (the task named
`CrispStrobe/CrispChess`; the checkout provided is this repository, and all work
was done on it)
**Tags / releases before this work:** none. No git tag existed and
`gh release list` was empty.

---

## 0. Verification environment — read this first

This audit was carried out in a sandbox with the following hard limits. They
determine what is *verified* and what is only *implemented*.

| Capability | Status |
|---|---|
| Dart / Flutter SDK | **Absent.** `dart` and `flutter` are not installed |
| `pub.dev` (dependency resolution) | **Unreachable** (connection refused) |
| `storage.googleapis.com` (the only official Flutter/Dart SDK host) | **Unreachable** |
| GitHub Actions (to run CI as the verification vehicle) | **No workflows registered for this repository** (`/actions/workflows` → `total_count: 0`, `/actions/runs` → 0) despite 12 workflow files; the token cannot read or change Actions permissions (`403`) |
| Local compilation / `flutter analyze` / `flutter test` / `flutter build` | **Not possible** |

Consequences, stated plainly:

- **No test in this repository was executed.** Not the pre-existing 67 test
  files, and not the new ones.
- **No platform build was executed** — not Windows, Linux, macOS, Android, iOS
  or Web.
- **No runtime verification of any engine** (built-in, Stockfish, Lc0,
  Frozenight, Lynx, Maia3, ChessMamba, searchless, LM, custom UCI) was possible.

What *was* done to compensate, and what it proves:

1. **Full source audit by reading**, with every claim below traceable to a
   specific file and line region, before the change.
2. **Syntax validation with a real Dart grammar.** `tree-sitter-dart` was
   installed from PyPI and every Dart file in `lib`, `test`, `integration_test`,
   `bin` and `test_driver` is parsed. Baseline before any edit: 229 files, no
   syntax errors. After every edit round the same check was re-run. This
   catches syntax regressions only — **it does not type-check**.
   Reproduce with `python3 tool/dev/parse_check.py`.
3. **Manual type review** of each change against its call sites and imports.

Anything below marked *not verified* was not, in fact, verified. Where a claim
rests on reading the code, it is described as such.

---

## 1. Defect inventory

Severity: **P0** critical (feature broken / data integrity), **P1** major,
**P2** moderate, **P3** polish. "Regression test" names the test added in this
change; **none of them have been run in this environment** (see §0).

### P0-1 — A custom engine that failed to initialise was persisted as working

- **File:** `lib/engines/generic_uci_engine.dart` (`initialize`),
  `lib/screens/engine_manager_screen.dart` (`_addEngine`)
- **Observed (by reading):** `initialize()` wrapped everything in
  `try { … } catch (e) { _stateNotifier.value = EngineState.error; }` and then
  returned normally. `_addEngine` does `try { await engine.initialize();
  … _store.add(result); } catch (e) { … }` — the catch could never run, so a
  wrong path, a non-executable file, or a binary that is not a chess engine was
  saved and only failed on the first move of a game.
- **Expected:** the failure reaches the caller; nothing is stored.
- **Root cause:** error swallowed at the bottom of the call stack, with state
  mutation used as a substitute for propagation.
- **Fix:** `initialize()` rethrows after setting `error` and tearing the
  process down; documented in `ChessEngine.initialize`.
- **Regression test:** `test/generic_uci_init_test.dart` →
  "a missing binary throws and leaves the engine in error",
  "a binary that is not executable throws".

### P0-2 — The UCI handshake timeout produced a "ready" engine

- **File:** `lib/engines/generic_uci_engine.dart`
- **Observed:** `await ready.future.timeout(const Duration(seconds: 10),
  onTimeout: () => debugPrint('[UCI] Handshake timeout…'));` — after the log
  line the method continued to send options, then set `EngineState.ready`.
- **Expected:** an engine that never answers `uci` is an error.
- **Fix:** the timeout throws `TimeoutException`; the process is killed. The
  handshake timeout is now a constructor parameter (default 10 s) so the test
  does not have to wait ten seconds.
- **Regression test:** "an engine that never answers `uci` times out and is not
  ready".

### P0-3 — An engine dying *during* the handshake was reported as ready

- **File:** `lib/engines/generic_uci_engine.dart`
- **Observed:** stdout's `onDone` completed the `ready` completer so the caller
  would not hang. Nothing distinguished "closed after `uciok`" from "closed
  without it", so the code fell through to `EngineState.ready` for a process
  that had already exited.
- **Fix:** `_handshakeComplete` flag; when stdout ends without `uciok` the
  death is reported as `EngineProcessDiedException` (with exit code and stderr
  tail).
- **Regression test:** "an engine that dies during the handshake reports the
  death".

### P0-4 — User-added engines could not be selected anywhere

- **Files:** `lib/screens/settings_screen.dart`, `lib/screens/chess_game_screen.dart`,
  `lib/screens/engine_match_screen.dart`, `lib/engines/engine_factory.dart`
- **Observed:** three unrelated engine lists. Settings built a hard-coded
  `_availableEngines` that never read `EngineProfileStore`; the match screen had
  its own `_engineNames`; `createEngine(name)` resolved by display name and fell
  back to `DartEngine` for anything it did not recognise. `createEngineFromProfile`
  existed but had **no caller outside the Engine Manager's probe**. The game
  screen's switch logic compared `_engineService.engineName` (a display name).
- **Expected:** an engine added in the Engine Manager is selectable and playable,
  and an unknown engine is reported rather than replaced.
- **Fix:** new `lib/engines/engine_registry.dart` — stable ids
  (`builtin:<name>`, `custom:<profile id>`), one `createEngineForId()` used by
  settings, play, hints, multi-engine analysis and matches, and
  `EngineUnavailableException` instead of silent substitution. The selection is
  persisted as `engineId` (with the legacy `engine` name kept in sync for
  backward compatibility and display).
- **Regression test:** `test/engine_registry_test.dart` (ids, lookup,
  resolution of a deleted profile, legacy name migration).

### P0-5 — Profiles were addressed by list position

- **File:** `lib/services/engine_profile_store.dart`, `lib/screens/engine_manager_screen.dart`
- **Observed:** `update(int index, …)` / `remove(int index)`. Deleting an entry
  renumbers the ones after it, so a subsequent edit wrote over a different
  engine, and the id-less selection in preferences pointed at whatever had moved
  into the old slot.
- **Fix:** `EngineProfile` gains an immutable `id` (generated on creation,
  backfilled and written back for profiles saved by earlier versions);
  `update(profile)` / `remove(id)` / `byId(id)` operate on identity.
- **Regression test:** `test/engine_profile_store_test.dart` → "updates by id,
  not by position", "profiles saved without an id are migrated and rewritten".

### P0-6 — A corrupt profile store made the Engine Manager unusable

- **File:** `lib/services/engine_profile_store.dart`
- **Observed:** `jsonDecode(json) as List` followed by `as String` casts and
  direct map access. A single unreadable entry threw out of the `profiles`
  getter, which is called from `_loadProfiles()` in the manager's `initState`.
- **Fix:** tolerant decode — unreadable entries dropped, unreadable JSON yields
  an empty list, duplicate ids deterministically repaired, migrated list written
  back. The screens also catch storage failures rather than taking the screen
  down.
- **Regression test:** "a corrupt store yields an empty list instead of
  throwing", "unreadable entries are dropped, readable ones kept", "duplicate
  ids are repaired so a delete is unambiguous".

### P1-1 — Evaluation inverted on every Black-to-move position

- **Files:** `lib/engines/generic_uci_engine.dart`, `lib/engines/stockfish_engine.dart`,
  `lib/engines/lynx_engine.dart`
- **Observed:** `EvalInfo.score` is documented (and consumed by the eval bar,
  the chart, the analysis panel and `chess_game_screen` comments) as "pawns,
  from White's perspective". All three engines emitted the UCI `score cp`
  unchanged, and UCI defines it from the side to move. With Black to move the
  bar showed the opposite of the engine's opinion.
- **Expected:** White's perspective everywhere.
- **Fix:** the side to move is read from the position command
  (`positionCommandIsWhiteToMove`, new in `uci_position.dart`) and the score is
  negated when Black is to move, including mate scores.
- **Regression test:** "White to move: +1.00 for White is +1.00", "Black to
  move: +1.00 for Black is -1.00 for White", "a mate score is flipped the same
  way".

### P1-2 — Stockfish dropped forced-mate evaluations entirely

- **File:** `lib/engines/stockfish_engine.dart`
- **Observed:** `if (cp != null && d != null)` — a line carrying only
  `score mate` (no `cp`) emitted nothing, so the eval froze exactly on mating
  positions.
- **Fix:** mate scores are parsed and mapped to a large magnitude, then
  perspective-converted.

### P1-3 — Restarting a crashed engine rebuilt the engine selected at start-up

- **Files:** `lib/services/engine_service.dart`, `lib/screens/chess_game_screen.dart`
- **Observed:** `EngineService.rebuildEngine` is captured in the constructor by
  `switchEngine`, but `switchEngine(newEngine)` replaced only `_engine`. After
  switching engines, a crash restored the *previous* engine while the UI still
  named the new one.
- **Fix:** `rebuildEngine` is reassignable and `switchEngine` takes a
  `rebuilder`; the game screen supplies one that reads the current selection,
  strength, variant and backend at the moment of the rebuild.
- **Regression test:** none — this needs a widget-level test of the game screen;
  recorded as *not verified*.

### P1-4 — Matches and tournaments never disposed their engines

- **Files:** `lib/services/engine_match_service.dart`,
  `lib/screens/engine_match_screen.dart`
- **Observed:** `EngineMatchService.dispose()` and `TournamentService.dispose()`
  close the event stream and stop flag only. The screen disposed the services,
  not the engines, so every match left its engine processes running — the
  orphan-process failure mode. (Neither service owns its engines: the
  tournament reuses them across pairings, so disposing them inside
  `EngineMatchService` would break the tournament.)
- **Fix:** the screen records the engines it creates and disposes them when the
  screen is closed or a new match starts; the two services document that they
  do not own engines.

### P1-5 — Switching engines disposed an engine mid-search

- **File:** `lib/services/engine_service.dart`
- **Observed:** `switchEngine` cancelled the analysis subscription and disposed
  immediately, without `stop()`, leaving a process waiting for a `bestmove`
  nobody would read.
- **Fix:** `stop()` before `dispose()`, analysis subscription awaited and
  nulled, restart budget reset.

### P1-6 — The hint-engine setting was never persisted and never took effect

- **Files:** `lib/services/preferences_service.dart`, `lib/screens/chess_game_screen.dart`
- **Observed:** `hintEngine` existed in `GameState` and in the settings UI but
  had no preference key, so it reset to `'same'` on every launch. The hint
  engine is held in `_hintSlot ??= EngineSlot(...)`, created once, so changing
  the setting had no effect until the app was restarted.
- **Fix:** `PreferencesService.hintEngine` added, loaded at start-up, saved on
  change; the slot is disposed when the setting changes. The hint path now
  resolves the name (including a user-added engine's name) to an id.

### P2-1 — UCI option list accumulated duplicates

- **File:** `lib/engines/generic_uci_engine.dart`
- **Observed:** `options` is a field that the handshake appends to; a second
  `initialize()` on the same instance doubled it.
- **Fix:** cleared before each handshake; `initialize()` is idempotent while
  `ready`.
- **Regression test:** "initialising twice does not duplicate the option list".

### P2-2 — Option editors reset the caret on every keystroke

- **File:** `lib/screens/engine_manager_screen.dart`
- **Observed:** `TextEditingController(text: …)` constructed inside `build`,
  i.e. recreated on every `setState`.
- **Fix:** one controller per option, created lazily, disposed with the screen.

### P2-3 — A combo option whose saved value is no longer advertised crashed the dialog

- **File:** `lib/screens/engine_manager_screen.dart`
- **Observed:** `DropdownButton(value: currentValue)` where `currentValue` need
  not be one of `comboValues`; `DropdownButton` asserts on that in debug and
  renders blank in release. Same pattern in the hint-engine dropdown
  (`lib/screens/settings_screen.dart`) and the match screen's engine dropdown.
- **Fix:** the value is validated against the items and falls back to no
  selection (or "same as opponent", or the first engine).

### P2-4 — Multi-engine analysis discarded every result when one engine failed

- **File:** `lib/screens/chess_game_screen.dart`
- **Observed:** one `try` around the whole loop; on the first failure the outer
  `catch` disposed the `MultiEngineService`, destroying the engines that had
  started fine. (`MultiEngineService.addEngine` already isolated initialisation
  failures; the caller did not.)
- **Fix:** per-engine try/catch, failed engines named in a single snackbar, the
  rest keep analysing. Custom engines are offered in the picker at all.

### P2-5 — Custom engines were missing from the hint and match lists

- **Files:** `lib/screens/settings_screen.dart`, `lib/screens/engine_match_screen.dart`
- **Fix:** both lists are built from the union of built-ins and loaded profiles.

### P2-6 — The web `GenericUciEngine` returned a new state notifier per call

- **File:** `lib/engines/generic_uci_engine_web.dart`
- **Observed:** `ValueNotifier<EngineState> get stateNotifier => ValueNotifier(…)`
  — listeners attach to a thrown-away object, so state changes are never seen.
- **Fix:** a single field.

### P3-1 — `@override` duplicated on `processLabel`

- **File:** `lib/engines/generic_uci_engine.dart` — removed.

---

## 2. Deliberately not changed

- **`createEngine(name)` keeps its silent fallback for an unknown name when it
  is called directly.** That is its documented historical behaviour and
  `test/engine_contract_test.dart` asserts it. It is no longer how a *saved
  selection* is resolved: `createEngineForId` calls `createEngineOrNull` and
  throws `EngineUnavailableException` for an unrecognised `builtin:` id, so a
  persisted engine id can no longer be silently replaced by a different engine.
  Nothing in the app calls `createEngine` with a name it did not construct from
  a canonical built-in id.
- **`engine_match_service._playGame`'s move parsing** passes
  `'promotion': null` for ordinary moves. `uci_position.dart` deliberately omits
  the key instead. Without the `chess` package sources available offline this
  could not be shown to be a defect, so it was left alone rather than changed
  on suspicion.
- **iOS/Android/macOS deployment configuration, signing, store metadata.** Out
  of reach without those toolchains, and not touched.

## 3. Platform matrix — claims and their basis

| Platform | Custom UCI support | Basis | Verification |
|---|---|---|---|
| Linux | Yes (any executable) | `dart:io` `Process.start` | **Not verified** — no build, no run |
| macOS | Yes for direct builds; App Store sandbox limits to app-container binaries | same, plus sandbox rules | **Not verified** |
| Windows | Yes, full path to `.exe` | same | **Not verified** |
| Android | Yes for app-private paths; Android 10+ blocks executing files from shared storage | same | **Not verified** |
| iOS | Documented as unavailable in practice: only app-signed code executes | platform rule | **Not verified** |
| Web | Not offered (`customEnginesSupported == false`); the manager button is hidden and `createEngineForId` throws | `kIsWeb` guard, unchanged from before | **Not verified** |

The README states these the same way. No platform is claimed as tested.

## 4. Versioning decision

`pubspec.yaml` says `version: 2.3.1+17`. The repository has **no tags and no
releases**, and its version history runs 2.2.0 → 2.3.0 → 2.3.1.

- `v1.0.0-dev1` would be a **downgrade** from 2.3.1 and would collide with the
  documented progression, so it was not used.
- The version was **left at 2.3.1+17**. A bump or a tag asserts that a
  particular source state was built and released; nothing here was built.

The version to use once a verified build exists: **2.3.2-dev1** (minor-internal
development milestone continuing 2.3.x), with the build number incremented
(`+18`) when the artifact is produced, and a tag `v2.3.2-dev1` on the verified
merge commit. This is recorded so the decision is not re-litigated later, and
so no conflicting identity is published now.

## 5. What still has to happen before a release

1. Run, on a machine with Flutter and `pub.dev` (or with Actions enabled on the
   repository): `flutter pub get`, `flutter analyze --no-fatal-infos
   --no-fatal-warnings`, `flutter test`, and `flutter build` for each of
   web/linux/windows/android/ios/macos.
2. Fix whatever those report — in particular, the changes here have been
   type-reviewed but **not compiled**.
3. Re-run the new engine tests; the timing-sensitive ones (0.1 s sleeps in the
   fake engines) may need widening on slow CI runners.
4. Only then merge, tag `v2.3.2-dev1`, and publish a pre-release.

## 6. Files changed

| File | Change |
|---|---|
| `lib/engines/engine_registry.dart` | **new** — ids, lookup, resolution, `createEngineForId`, `EngineUnavailableException` |
| `lib/engines/generic_uci_engine_stub.dart` | stable profile id, tolerant JSON, `displayName`, detected identity |
| `lib/engines/generic_uci_engine.dart` | init error propagation, handshake timeout/death, option reset, identity, eval perspective, teardown |
| `lib/engines/generic_uci_engine_web.dart` | stable notifier, `displayName` |
| `lib/engines/uci_position.dart` | `positionCommandIsWhiteToMove` |
| `lib/engines/lynx_engine.dart`, `lib/engines/stockfish_engine.dart` | eval perspective; Stockfish mate scores |
| `lib/services/engine_profile_store.dart` | id-based API, migration, tolerant decode |
| `lib/services/preferences_service.dart` | `engineId`, `hintEngine` |
| `lib/services/engine_service.dart` | reassignable rebuilder, safe switch |
| `lib/screens/engine_manager_screen.dart` | id-based edit/remove, no persistence on failure, option controllers/combo guard |
| `lib/screens/settings_screen.dart` | registry-backed selector incl. custom engines, id persistence, hint list |
| `lib/screens/chess_game_screen.dart` | id-based play/switch/hint/multi-engine, explicit fallback, rebuilder |
| `lib/screens/engine_match_screen.dart` | custom engines in matches/tournaments, engine disposal, failure reporting |
| `test/engine_registry_test.dart`, `test/engine_profile_store_test.dart`, `test/generic_uci_init_test.dart` | **new** — see §1 |
| `tool/dev/parse_check.py` | **new** — tree-sitter syntax check used during this audit |
| `README.md`, `CHANGELOG.md` | documentation of the above |

---

## 7. Release verification log

| Step | Result |
|---|---|
| Branch `arena/6eac624a-scrispchess-extended` pushed | `65dac93` (`feat(engines): finish custom UCI integration…`) |
| Pull request | [#1](https://github.com/coderunknow/ScrispChess-Extended/pull/1), open, not merged |
| GitHub Actions on the PR head | **none.** `/actions/runs` → `total_count: 0`; `/actions/workflows` → `total_count: 0` although 12 workflow files are present. The token cannot read or set Actions permissions (`403 Resource not accessible by integration`), so Actions could not be enabled |
| Check runs on `65dac93` | `Kilo Code Review` → **fail** ("could not run — your account is out of credits"); Qodo → **paused** ("trial has ended"); CodeRabbit → **skipped** ("repository has fewer than 10 stars") |
| Merge | **withheld** — the merge gate requires passing tests and builds, and none could be run |
| Tag | **not created** (no tag existed before; creating one would assert a verified artifact) |
| GitHub pre-release | **not created** |
| Version | unchanged: `2.3.1+17` |

Because every available verification channel was unavailable, the honest
classification of this change is: **implemented, syntax-checked, and manually
reviewed — not unit-tested, not built, and not runtime-tested.**

---

## 8. Second audit round — adversarial re-review of this change

The first round was audited by reading the files that the change touched. This
round re-read the same change looking for the same *classes* of defect applied
elsewhere, and for defects the fix itself could have introduced. Everything below
was found in code written or touched by this change, except where stated.

The environment did not change: still no Flutter/Dart toolchain, still no
GitHub Actions. Every claim below is therefore still "implemented and
syntax-checked", except where a test is named — and no test could be executed
here, so even those are unverified until someone runs `flutter test`.

### P1-7 — The evaluation inversion was only half fixed

- **Files:** `lib/engines/stockfish_downloadable_engine.dart`,
  `lib/engines/stockfish_web_engine.dart`, `lib/engines/lynx_web_engine.dart`,
  `lib/engines/lc0_engine.dart`
- **Observed:** P1-1 fixed the perspective for `GenericUciEngine`,
  `StockfishEngine` (the process one) and `LynxEngine`. Three more UCI text
  parsers were left emitting the raw side-to-move score, and one neural engine
  emitted a side-to-move value:
  - `stockfish_downloadable_engine.dart` — the Stockfish that **iOS actually
    runs** (stockfish.js inside WebKit) and the native download path;
  - `stockfish_web_engine.dart` — the browser build, which also had no
    `score mate` handling at all (P1-2 in another file);
  - `lynx_web_engine.dart` — the WASM Lynx;
  - `lc0_engine.dart` — `NnEval.value` is documented in `lc0_dart/mcts.dart` as
    the expected outcome *from the side to move*, and this build emitted it
    directly while its own web counterpart (`lc0_web_engine.dart`) already
    converted. The two builds of the same engine disagreed about the sign of
    every Black-to-move position.
- **Expected:** `EvalInfo.score` in pawns from White's perspective, everywhere.
- **Fix:** each parser reads `positionCommandIsWhiteToMove(...)` at the same
  point it sends the position (inside the coordinator/serialization lock, so a
  queued search cannot describe a different position by the time it runs) and
  negates `score cp`, `score mate` and the Lc0 value when Black is to move.
  Mate is parsed in both Stockfish parsers now.
- **Verification:** `stockfish_web_engine.dart` and `lynx_web_engine.dart`
  import `dart:js_interop`/`dart:ui_web` and cannot be loaded by a VM test, so
  the sign decision was moved into `positionCommandIsWhiteToMove`, which is
  tested. The call sites themselves are reviewed, not executed — stated plainly
  rather than counted as verified.
- **Regression test:** `test/uci_position_test.dart` → group
  `positionCommandIsWhiteToMove`, including an oracle cross-check against the
  FEN the command describes.
- **Not covered by a test:** the four parsers themselves.

### P1-8 — Switching engines sent the options to the engine that had just been disposed

- **File:** `lib/screens/chess_game_screen.dart`
- **Observed:** `_engineService.switchEngine(...)` was called without `await`,
  immediately followed by `_applyEngineOptions()`. `switchEngine` awaits
  `_analysisSubscription.cancel()` before it swaps engines, so the options went
  to the **old** engine — or, once it had been swapped, to the new one before
  its process existed. Either way `Hash`, `Threads` and `UCI_Chess960` were
  never delivered after a switch, and for a Chess960 game the missing variant
  flag means the engine reads the castling rights wrong.
  `_engineId` was also assigned *before* the switch, so a new engine that failed
  to start left the app showing it as selected.
- **Fix:** one `_switchEngineTo(id)` path that awaits the switch, records the id
  only if the engine started, applies options after it did, and — when it did
  not — rebuilds the previous engine and puts it back, saying so. The
  "Switch to Built-in" action on the failure snackbar uses the same path.
- **Depends on:** `EngineService.initialize()`/`switchEngine()` now return
  whether the engine started (`Future<bool>`); the failure is still emitted as
  `EngineErrorEvent` for the UI.
- **Regression test:** `test/engine_service_test.dart` → group
  `EngineService.switchEngine` (reports success, reports a failed start, and
  reports success again after a recovery).
- **Not covered by a test:** the screen path itself.

### P1-9 — Two user-added engines with the same name crashed the settings screen

- **File:** `lib/screens/settings_screen.dart`
- **Observed:** the hint-engine dropdown was keyed by **display name**
  (`(profile.displayName, profile.displayName)`), while the engine dropdown next
  to it was already keyed by id. Two profiles may legitimately share a name —
  and a profile named `Stockfish` collided with the real one — producing two
  identical `DropdownButton` values, which asserts.
- **Fix:** the hint list is built from `_availableEngines`, so it is keyed by id
  and cannot drift from the main selector; a saved display name is migrated to
  an id when the screen builds; the value's label is looked up rather than
  printed raw.
- **Regression test:** `looksLikeEngineId` (registry test group) — the
  "is this persisted value an id or a legacy name" decision the migration rests
  on. The widget itself is not covered by a test.

### P2-7 — An unknown `builtin:` id silently played as the built-in engine

- **Files:** `lib/engines/engine_factory.dart`, `lib/engines/engine_registry.dart`
- **Observed:** `createEngineForId('builtin:X')` called `createEngine('X')`,
  whose documented behaviour is to fall back to `DartEngine` for an unknown
  name. A saved id naming an engine that does not exist therefore produced a
  working engine and a screen that displayed the missing one — the same class of
  defect this change set out to remove, left in the one place that resolved ids.
- **Fix:** `createEngineOrNull` (same switch, no fallback) plus an explicit
  `case 'Built-in'`; the registry throws `EngineUnavailableException` when it
  returns null. `createEngine` keeps its fallback for the callers that rely on
  it, and its existing test still asserts it.
- **Regression test:** "an unknown built-in id is reported, not silently
  replaced"; "createEngineOrNull tells \"no such engine\" from \"built-in\"".

### P2-8 — Disposal could be undone by a state write

- **File:** `lib/engines/generic_uci_engine.dart`
- **Observed:** three ways for a dead engine to be reported alive:
  - `stop()` set `EngineState.ready` unconditionally, so calling it on a
    disposed engine (or one that had just failed) turned it back into a ready
    engine with no process behind it;
  - an `initialize()` still in flight when `dispose()` ran set `error` (or
    `ready`) afterwards, resurrecting a disposed engine;
  - `_handleLine` could add to the eval controller after `dispose()` closed it.
- **Fix:** `stop()` only moves `thinking → ready`; state writes go through
  `_setState`, which is a no-op once disposed; a handshake that finishes after
  disposal tears the process down and throws; the eval controller is checked
  before adding.
- **Regression test:** "stop() does not resurrect a disposed engine",
  "initialising a disposed engine throws instead of spawning".

### P2-9 — Two concurrent `initialize()` calls started two processes

- **File:** `lib/engines/generic_uci_engine.dart`
- **Observed:** the Engine Manager probes an engine and the screen that selects
  it starts the same one; both saw a state that was not `ready` and both ran the
  handshake. One process was left with no reader — alive until the app exited,
  holding the binary open.
- **Fix:** the in-flight attempt is stored and awaited by later callers; it is
  cleared on completion, including on failure, so a retry is still possible.
- **Regression test:** "two initialise calls at once start one process" (counts
  the process's own start marker in a log), "a retry after a failed initialise
  is allowed".

### P2-10 — The Engine Manager could call `setState` after it was disposed

- **File:** `lib/screens/engine_manager_screen.dart`
- **Observed:** `_loadProfiles()` awaits `SharedPreferences`, then calls
  `setState` with no `mounted` check — popping the screen quickly threw
  "setState() called after dispose".
- **Fix:** guarded. (Pre-existing, surfaced while reviewing the new code path
  that adds a profile and reloads.)

### P2-11 — The side to move was derived from a replay that can fail

- **File:** `lib/engines/uci_position.dart`
- **Observed:** `positionCommandIsWhiteToMove` replayed the move list through
  `package:chess` and read the turn out of the resulting FEN. `_playUci` stops at
  the first move it cannot reproduce; any such move — a variant castling
  notation, a promotion written differently — left the helper reporting the
  *previous* side to move, which inverts the evaluation, the exact bug it was
  added to prevent.
- **Fix:** derived from the parity of the move list instead: every legal move
  passes the turn, so no move has to be reproducible for the answer to be right.
  Cheaper, too (no FEN parsing per call).
- **Regression test:** the oracle cross-check above, plus explicit
  Black-to-move FEN cases.

### P3-2 — A repaired duplicate profile id changed on every read

- **File:** `lib/services/engine_profile_store.dart`
- **Observed:** a duplicate id was repaired by constructing a new profile, which
  generated a random id. Every read of the same stored JSON produced a different
  id, so an edit addressed an id no later read would ever produce — until a
  rewrite happened to land first.
- **Fix:** the repaired id is derived from the original id and the position, so
  every read agrees.

### Evaluation perspective after both rounds

Traced at the source, for every engine that produces an evaluation:

| Engine | Convention at the source | Result |
|---|---|---|
| `dart_engine.dart` (built-in) | `crisp_chess_engine`, negamax | converted ✓ (round 2, see P1-10) |
| `GenericUciEngine` | UCI, side to move | converted ✓ (round 1) |
| `StockfishEngine` | UCI, side to move | converted ✓ (round 1) |
| `LynxEngine` | UCI, side to move | converted ✓ (round 1) |
| `stockfish_downloadable_engine.dart` | UCI, side to move | converted ✓ (round 2) |
| `stockfish_web_engine.dart` | UCI, side to move | converted, mate added ✓ (round 2) |
| `lynx_web_engine.dart` | UCI, side to move | converted ✓ (round 2) |
| `lc0_engine.dart` | `NnEval.value`, side to move | converted ✓ (round 2) |
| `lc0_web_engine.dart` | already White-relative | unchanged ✓ |
| `maia3_dart_engine.dart` | win probability, White encoding | unchanged ✓ |
| `searchless_engine.dart` | `whiteToMove ? p : -p` | unchanged ✓ |
| `chessmamba_engine.dart` | `mambaValueToPawns(..., whiteToMove:)` | unchanged ✓ |
| `frozenight_engine.dart` (Rust FFI) | `frozenight_get_score` → `eval_to_cp(SearchInfo.eval)`, negamax | converted ✓ (round 2, see P1-10) |
| `frozenight_web_engine.dart` | `frozenightGetEval`, same search | converted ✓ (round 2, see P1-10) |

### P1-10 — The built-in engine and Frozenight inverted the evaluation

- **Files:** `lib/engines/dart_engine.dart`, `lib/engines/frozenight_engine.dart`,
  `lib/engines/frozenight_web_engine.dart`
- **Observed:** the same omission as P1-7 in three more places, including the
  two most visible engines in the app:
  - `dart_engine.dart` — the **built-in engine**, the default opponent on a
    fresh install. Both `analyze()` paths (isolate and web) emitted
    `result.score / 100` unchanged.
  - `frozenight_engine.dart` — `frozenight_get_score() / 100`, and it is the
    default Black side in engine-versus-engine matches.
  - `frozenight_web_engine.dart` — the same with `frozenightGetEval()`.
- **Evidence:** both are negamax searches, read at the source rather than
  assumed:
  - `crisp_chess_engine` (`lib/src/search.dart`, `_searchRoot`):
    `final score = -_alphaBeta(depth - 1, -beta, -alpha, 1);`, maximising over
    negated child scores.
  - `frozenight` (`Cargo.toml` → git `CrispStrobe/frozenight`, `main`):
    `Searcher::qsearch` computes `let v = -self.qsearch(...)`, `search_moves`
    maximises over those, and a mated side to move returns `-Eval::MATE`; that
    value is what reaches `SearchInfo.eval`.

  Both are therefore relative to the side to move — the ordinary engine
  convention, the same one UCI prints as `score cp`.
- **Fix:** each `analyze()` records `positionCommandIsWhiteToMove(positionCommand)`
  and negates when Black is to move, as the other parsers now do.
- **Verification:** none of the three can be exercised here — `dart_engine`
  needs the isolate worker or a browser, Frozenight needs the FFI library built
  and its WASM bundle downloaded. Implemented, syntax-checked and reviewed, not
  executed. The existing `dart_engine` analysis tests all use `position
  startpos` (White to move), so they neither covered this nor broke when the
  sign changed — which is exactly why it was never noticed.

### A limitation of the perspective fix, recorded rather than hidden

All six parsers keep the side to move in an instance field, set at the point the
position is sent. That is correct for the way this app drives engines — one
search at a time, and analysis is cancelled before a move request — but it is
not per-search state: two searches genuinely overlapping on one engine instance
could read the other's colour. Fixing that properly means threading the colour
through the search coordinator into `EvalInfo` construction, which is a larger
change than this audit; it is recorded here instead of being claimed as solved.

The five engines that already converted are the evidence for the convention: an
engine that reports a human eval in *pawns* on this app is expected to convert,
and the ones that did not were the outliers.

### Additional regression tests added this round

| File | What it covers |
|---|---|
| `test/uci_position_test.dart` | `positionCommandIsWhiteToMove`, with a FEN oracle cross-check |
| `test/engine_service_test.dart` | `switchEngine` reporting whether the new engine started |
| `test/engine_registry_test.dart` | unknown `builtin:` id throws; `looksLikeEngineId` |
| `test/engine_contract_test.dart` | `createEngineOrNull` vs the documented fallback |
| `test/generic_uci_init_test.dart` | post-handshake lifecycle: no resurrection, one process for concurrent starts, retry after failure |

### Release-verification log — second round

| Step | Result |
|---|---|
| Commit | `d1d3e4a` (`fix(engines): complete the eval-perspective fix and close review findings`), on top of `65dac93` and `a72a225` |
| Pull request | [#1](https://github.com/coderunknow/ScrispChess-Extended/pull/1) — open, `MERGEABLE`, head `d1d3e4a` |
| Syntax check | `python3 tool/dev/parse_check.py` → 233 Dart files, 0 errors (tree-sitter; **not** `dart analyze`) |
| Unit tests | **not run** — no Dart/Flutter SDK, and no way to install one (`pub.dev`, `storage.googleapis.com` unreachable) |
| Builds | **not run** — same reason |
| GitHub Actions | **none.** `/actions/runs` → `total_count: 0`; the token cannot read or set Actions permissions |
| Automated reviewers | Kilo: out of credits; Qodo: trial ended; CodeRabbit: repository under 10 stars |
| Merge | **withheld** — the gate is a passing test suite and build, and neither could be run |
| Tag / pre-release | **not created** — would point at an unverified commit |
| Version | unchanged: `2.3.1+17` |

The release is withheld for the reason the directive itself gives: a release
must not point at a commit whose tests and builds have never been run. The work
is complete and pushed; what is missing is a machine that can run `flutter test`
and `flutter build`.

---

## 9. CI/CD findings from the second round

- **`ci.yml` inherited the repository's default token permissions.** Every job
  reads the repository and builds; artifact uploads use the artifacts API and
  need nothing from `GITHUB_TOKEN`. Added `permissions: contents: read` at the
  workflow level. The workflow still parses (checked with PyYAML: 14 jobs).
- **`release.yml`'s web fallback tested for a directory, not a build.** The WASM
  step is `continue-on-error` with a JS fallback guarded by
  `[ ! -d "build/web" ]`. A WASM build that fails *after* creating the directory
  leaves it half-written, so the guard would pass, the fallback would be
  skipped, and the release would tar an incomplete build. It now checks for
  `main.dart.js`/`main.dart.wasm`, the same test `ci.yml` already used.
- **Not changed, recorded instead:** `deploy-web.yml` has no `permissions` block
  (a Pages deploy wants `pages: write` / `id-token: write`). Adding it could
  break a deploy that cannot be exercised here, so it is left as a finding.
- The `continue-on-error` uses that remain in `ci.yml` are on optional native
  cross-builds and the WASM attempt, each followed by a step that fails if no
  artifact was produced; none of them sits on the analyze/test gate.

---

## 10. Third round — execution evidence, a real engine, and the CodeRabbit review

This round was asked to establish working behaviour rather than to re-read
code. What could be executed was executed; what could not is listed with the
exact reason and the exact remedy.

### 10.1 The toolchain question, answered with probes rather than assumption

| Probe | Result |
|---|---|
| `command -v dart flutter pub dartaotruntime fvm` | nothing |
| `find / -maxdepth 6 \( -name dart -o -name flutter -o -name dart-sdk \)` | only `linux/flutter` and `windows/flutter` — this project's own platform folders, not an SDK |
| `ls /opt /usr/local` | yarn, gcc, node — no Dart |
| `curl https://storage.googleapis.com` | **000** (unreachable) |
| `curl https://download.flutter.io` | **000** |
| `curl https://pub.dev`, `https://api.pub.dev` | **000** |
| `api.github.com/repos/dart-lang/sdk/releases` | `count 0` — no release assets exist to download |
| `api.github.com/repos/flutter/flutter/releases` | 7 releases, **0 assets on every one** |
| `pypi.org/pypi/dart-sdk/json` | **404** — no such package |
| `github.com`, `api.github.com`, `registry.npmjs.org`, `pypi.org` | 200 |

So the SDK is not obtainable here by any route that could be *verified*: the
official hosts are unreachable, and the GitHub projects that publish Dart and
Flutter do not attach SDK binaries to their releases. The remaining candidates
are third-party re-packages on npm/PyPI, which cannot be checked against a
published checksum from this sandbox (`storage.googleapis.com`, which serves
them, is blocked) — installing one would be exactly the "arbitrary prebuilt
binary" this audit was told to avoid. **`flutter pub get`, `flutter analyze`,
`flutter test` and every platform build remain unexecutable here.**

### 10.2 A real UCI engine was built and used

Stockfish 11 was fetched from `codeload.github.com/official-stockfish/Stockfish`
(tag `sf_11`, the last classical-eval release, so it needs no network at build
time) and compiled with `make -j2 build ARCH=x86-64` — **exit 0**, a 397 KB
binary. Everything below was produced by talking to it.

**Protocol facts the parsers depend on, measured:**

| Question | Measured answer |
|---|---|
| Is `score cp` relative to the side to move? | Yes. White up a queen, White to move → `score cp 1330`; the same imbalance with **Black to move** → `score cp 1329` **positive**, i.e. from Black's point of view. Converting that to White's must negate it. |
| Is `score mate` the same convention? | Yes. `7k/5K2/8/8/8/8/8/6R1 w` → `score mate 1`; the mirror `6r1/8/8/8/8/8/5k2/7K b` → `score mate 1` again, positive for the mover. |
| Does `stop` still produce `bestmove`? | Yes, and **16 `info` lines arrive between `stop` and `bestmove`** — the measurement behind §10.3. |
| What does `bestmove` look like? | `bestmove e2e4 ponder e7e6` — a `ponder` field follows, so only field 1 may be read as the move. |
| How are promotions spelled? | `bestmove a7a8q` — one lowercase letter, matching `PieceType.name` and `uci_position.dart`'s promotion handling. |
| Can a second `go` while one is running confuse the caller? | Yes — two queued searches produce two `bestmove` lines. A harness that took the first match in its buffer re-used the *previous* `bestmove` and got an illegal move, reproducing the exact defect `UciSearchCoordinator` exists to prevent. |

**A whole game, driven the way the app drives an engine.** The harness mirrors
`chess_game.dart`'s `positionCommand` (`position startpos moves …`, or
`position fen … moves …`), `uciGoCommand` (`go movetime <ms>`) and
`thinkTimeForLevel` (`200 + level*90` ms), re-sending the full move list every
ply as `generic_uci_engine.bestMove` does:

| Run | Result |
|---|---|
| `startpos`, level 10 (1100 ms/move), 40 plies | 40 plies played, **every move legal** (checked against `python-chess`), slowest move 1110 ms against the 1100 ms budget, engine exited 0 |
| `position fen r3k2r/pppq1ppp/2npbn2/4p3/4P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 0 1`, level 6, 20 plies | 20 plies, every move legal, slowest 750 ms against 740 ms, exited 0 |
| `position fen r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 4`, level 8, 20 plies | 20 plies, every move legal, first move `c6a5` by Black (the FEN's side to move), slowest 929 ms against 920 ms, exited 0 |

This is protocol-level evidence, not application evidence: the Dart code that
would send those same commands was never executed.

### 10.3 P2-12 — the evaluation perspective was still a race

- **Files:** `lib/engines/uci_search_coordinator.dart` plus every engine that
  mixes it in — `generic_uci_engine.dart`, `lynx_engine.dart`,
  `stockfish_engine.dart`, `stockfish_downloadable_engine.dart`,
  `stockfish_web_engine.dart`; `frozenight_engine.dart` and
  `frozenight_web_engine.dart`; `lynx_web_engine.dart`.
- **Observed:** the side to move was stored in an instance field that the
  caller set *before* asking for the search. `startSearch` begins by draining
  the previous search — `stop`, then wait for its `bestmove` — and the
  measurement above shows a real engine emits ~16 `info` lines during that
  window. Those lines belong to the **previous** position but were converted
  with the **new** position's colour, so the eval bar flickered to the opposite
  sign on every search that replaced another. Recorded as a "known limitation"
  in §8; the instruction for this round was not to leave a reachable race
  documented when it can be fixed.
- **Fix:** the colour travels with the search. `startSearch(..., whiteToMove:)`
  stores it *after* the drain, and exposes it as `searchWhiteToMove` for the
  `info` handler. The five coordinator engines no longer keep a field.
  `frozenight_*` compute it as a local inside the `analyze` generator (one value
  per stream, nothing can change it underneath), and `lynx_web_engine` passes it
  as a parameter to `_parseInfoLine` inside its serialization lock.
- **Regression test:** "an eval still arriving from the stopped search keeps its
  colour" (`test/generic_uci_init_test.dart`) — two searches back to back
  through a fake engine that pauses on `go`: the first eval must stay `+1.00`
  (White to move) even though the second search, for a Black-to-move position,
  has already been requested.

### 10.4 CodeRabbit review of 33e74d0 — reconciled

The review completed on commit `33e74d0` (check run `CodeRabbit` →
`completed / success`, 01:44Z) with four findings. All four were checked against
the code and all four were **valid**:

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | The audit doc still claimed `createEngine`'s fallback reaches `builtin:` ids, and still said duplicate ids are "regenerated" | valid (stale doc) | Both statements corrected in §0/§1 (P0-6) and §2 |
| 2 | `EngineManager._loadProfiles` read `_store.profiles` instead of `load()`, so ids of legacy entries were not the ids later reads produce | valid | `_loadProfiles` uses `load()`; **and** the root cause fixed: an id-less entry now gets a *derived* id (`legacyEngineProfileId`) instead of a random one, and every store mutation goes through `load()` |
| 3 | `_removeEngine` built its confirmation from `profile.name`, which is empty when the user let the engine's `id name` stand in | valid | Uses `displayName`, like the list tile and the success snackbar |
| 4 | The README claimed missing binaries are "reported in the selector and skipped by matches", and a licensing sentence had a dangling "They" | valid | Claim replaced with what the code does (the path is not probed until the engine starts); the MIT sentence moved to the GPL-3.0 note where "They" has a referent |

Because the fixes change code, `33e74d0`'s review is **stale for the new
commit** — a fresh review is required and was requested.

### 10.5 Every score producer, enumerated

`EvalInfo.score` is documented as **pawns, from White's perspective**
(`lib/engines/chess_engine.dart:26`). Every class that can emit one:

| Producer | What it produces | POV it is measured in | Converted? |
|---|---|---|---|
| `DartEngine` (built-in, `dart_engine.dart`, both the search and the static path) | negamax score | **side to move** | yes, negated |
| `GenericUciEngine` (`generic_uci_engine.dart`) | UCI `score cp` / `score mate` | side to move (measured, §10.2) | yes, both kinds |
| `StockfishEngine`, `StockfishDownloadableEngine`, `StockfishWebEngine` | as UCI | side to move | yes, both kinds |
| `LynxEngine`, `LynxWebEngine` | as UCI | side to move | yes, both kinds |
| `FrozenightEngine` (FFI), `FrozenightWebEngine` | engine score | side to move (verified in the upstream C++: `qsearch` negates children, a mated side is `-MATE.add_time(ply)`) | yes, both kinds |
| `Lc0Engine`, `Lc0WebEngine` | WDL from `lc0` | side to move | yes |
| `ChessMambaEngine` | as UCI | side to move | yes |
| `ChessLmEngine` | constant 0 (no numeric eval) | — | n/a |
| `SearchlessEngine` (`searchless_engine.dart:224`) | logistic of win probability | **side to move**, negated at the yield | **yes** |
| `Maia3DartEngine` (`maia3_dart_engine.dart:282`) | WDL value head | **side to move** — the board is mirrored into the model when Black is to move, and the policy's move is mirrored back | **was not** — see below |

`Maia3DartEngine` was the one producer that emitted the mover's value
unconverted: on a Black-to-move position the eval bar showed Black's
probability of winning as White's. It is outside PR #1's diff (the file is
untouched by this branch), so this is a pre-existing defect, not a regression of
the change; it is fixed here because a known inverted eval in a selectable
engine would otherwise be left standing. The conversion is `1 - p` on a
Black-to-move position, which is exact: `win + 0.5*draw` for one side is
`loss + 0.5*draw` for the other.

**Not proven by execution.** The Maia3 conclusion comes from the code's own
mirroring (`_legalLogits` mirrors the lookup move and comments that the model
"always sees white POV") and from `1 - p` being the correct identity; the model
cannot be run here (weights are multi-hundred-megabyte downloads from a host
this sandbox cannot reach). The conversion is therefore reasoned, not measured —
unlike the UCI engines, whose convention was measured against a real binary.

### 10.6 Correction to §9: the `deploy-web.yml` permissions finding is withdrawn

Re-read against the file, the claim in §9 is wrong on both counts:

- `deploy-web.yml` **does** have a `permissions` block — `contents: write`, at
  job level, present at the base commit `0d01798` and unchanged by this branch.
- It does not use `actions/deploy-pages` at all. The Pages step force-pushes a
  built tree to the `gh-pages` branch, which needs `contents: write` and nothing
  else. `pages: write` / `id-token: write` would only be required by the
  artifact-based deploy this workflow does not use, so **adding them would have
  been wrong**, not merely unverifiable. No change made; the earlier note is
  superseded by this one rather than edited away.

Two CI observations are recorded and **not** changed, because both pre-date this
PR and neither can be exercised here:

- The Pages step is guarded by `if: ${{ !cancelled() }}`, which is true for a
  failed job as well as a successful one. If the Flutter build fails after
  creating `build/web`, the step still publishes that incomplete tree to the
  live `gh-pages` site. `if: success()` would be the correct guard; changing it
  is a behaviour change to a deployment path that cannot be run from here.
- `flutter build web --release --wasm` is attempted first and falls back to the
  JS build, but the fallback is a separate command in an `if … else` block; both
  leave output in `build/web`, so the "Log build type" step infers the variant
  from which file exists afterwards. That is sound, but it means a WASM build
  that *succeeds* while emitting `main.dart.js` only would be misreported.

All twelve workflow files still parse as YAML (PyYAML): `ci.yml` 14 jobs,
`release.yml` 9, `ios-release.yml` 2, and one each in the other nine.

### 10.7 Reviewer state, pinned to the head commit

Each row is the check run GitHub attaches to that exact SHA, not a memory of an
earlier report.

| Head SHA | CodeRabbit check run | Meaning |
|---|---|---|
| `33e74d0` | `completed / success` (01:44:22Z), 4 inline findings | reviewed; all four findings valid and fixed |
| `c18147f` | `completed / skipped` (01:47:33Z, zero duration) | not reviewed |
| `24a330f` | `completed / skipped` (01:48:02Z) | not reviewed |
| `4acce67` | `completed / skipped` (01:49:13Z) | not reviewed |

`skipped` is not `success` and was not treated as one. The cause was requested
rather than inferred: `@coderabbitai review` on the PR drew an explicit
`⚠️ Action not completed — Review rate limited.` reply from CodeRabbit
(01:49:53Z), with the note that it "is an incremental review system and does not
re-review already reviewed commits". So the four findings raised against
`33e74d0` were fixed, but **the commits that fix them carry no independent
review**. The other agents remain unavailable or exhausted (Kilo
`action_required`, Qodo paused, Copilot out of quota), and GitHub Actions still
produces no runs for this repository (0 check runs on any commit that is not a
third-party app's).

### 10.8 What the third round did not establish

- No Dart or Flutter process was executed: no `pub get`, no `analyze`, no test
  run, no build, no app launch.
- The engine parsers were exercised only through their protocol inputs
  (measured), never through their own code paths.
- UI behaviour (engine shown as active before initialisation, stale eval bars,
  error banners) remains code-reviewed only.

---

## 11. Fourth round — why CI never ran, and what could still be executed

Objective for this round: unblock real CI, then run the gates against the exact
head. Head throughout: `a366106c1f7df1d7a4c111076650b25b8a1d5630`.

### 11.1 The root cause, with evidence

`.github/workflows/ci.yml` exists on `main` (blob `3c4b916`, 10,602 bytes) and on
this branch, and it declares `push: branches: [main]`, `pull_request: branches:
[main]` and `workflow_dispatch:`. The trigger is **not** the problem. These are
the measurements:

| Probe | Result |
|---|---|
| `GET /repos/…/actions/workflows` | **`{"total_count":0,"workflows":[]}`** — no workflow is registered, not even as `disabled_manually` |
| `GET /repos/…/actions/runs` | **`total_count: 0`** |
| …`&event=push` / `pull_request` / `workflow_dispatch` / `schedule` | **0 / 0 / 0 / 0** |
| `GET https://github.com/coderunknow/ScrispChess-Extended/actions` | renders “**0 workflow runs** — There are no workflow runs yet.” |
| `GET …/actions/workflows/ci.yml` (web) | **404** — an unregistered workflow |
| Check runs on the base commit `0d01798` | **0** — GitHub's own CI check has never appeared on any commit |
| Check runs on `a366106` | only third-party apps (CodeRabbit, Kilo) |
| Parent `CrispStrobe/CrispChess` `/actions/workflows` | **13 workflows, every one `active`** — the same files, upstream |
| PR #1 | exists since `2026-10-31T01:16:33Z`, base `main` — the `pull_request` event has existed for hours |
| Fork metadata | `fork: true`, public, `created_at 2026-10-31T00:47:32Z`, `archived:false`, `disabled:false` |

A valid workflow file on the default branch, a live pull request against that
default branch, and a repository that lists **zero** workflows and has produced
**zero** runs for every event that could fire. The files are fine — they are
`active` in the upstream repository they came from. What is missing is the
repository-level switch: **GitHub does not run workflows in a fork until the
fork's owner enables them**, and this fork has never had them enabled or
registered.

The trigger theory is excluded by the fourth row: `workflow_dispatch` is not a
pattern-matched trigger, and it produces nothing either. So are the YAML theory
(all twelve files parse with PyYAML and every path they reference exists — §11.3)
and the path-filter theory (`paths-ignore` suppresses a run for a matching
*push*; it cannot suppress `pull_request` or `workflow_dispatch`).

**This credential cannot fix it.** Every endpoint that reads or writes the
repository's Actions settings refuses it:

| Endpoint | Result |
|---|---|
| `GET /actions/permissions` | `403 Resource not accessible by integration` |
| `GET /actions/permissions/workflow` | `403` |
| `GET /actions/permissions/selected-actions` | `403` |
| `GET /branches/main/protection` | `403` (so it is the app's `administration` grant, not this endpoint) |
| `POST /actions/workflows/ci.yml/dispatches` | `403` (the app also lacks `actions: write`, so it cannot even ask for a run) |
| `gh auth status` | installation token — `X-OAuth-Scopes` is empty |

`GET /repos/…` reports `permissions.admin: true`, but that is the app's own
grant summary; the administration endpoints say what is actually callable.

**The one action that unblocks every remaining gate** is performed in the
browser by the fork owner, and takes seconds:

1. `https://github.com/coderunknow/ScrispChess-Extended/settings/actions`
2. *Actions permissions* → **Allow all actions and reusable workflows** → **Save**.
3. If the Actions tab shows *“Workflows aren't being run on this forked
   repository”*, press **I understand my workflows, go ahead and enable them**.
4. Then re-run this round's gate step: opening/re-synchronising PR #1 (or
   `workflow_dispatch` on `ci.yml` for this branch) starts all 14 jobs.

Nothing in this repository needs to change for that to work; the workflow file
is already correct and already covers this branch.

### 11.2 What could still be executed here, and was

The first step of the `analyze` job does not need Flutter, so it can be run
exactly as CI runs it:

```
$ python3 -m unittest discover -s tools/tests -v
...
Ran 19 tests in 0.153s
OK
```

**19/19 passed** at `a366106`. They cover the release tooling that the App Store
jobs depend on (`verify_macos_app.py`, version handling in `pubspec.yaml`,
attach-only build selection, ad-hoc signing).

Pre-flight for the jobs that cannot run here — every path `ci.yml` names, checked
at this head: `tool/perf/tournament.dart`, `tools/tests`, `tools/verify_macos_app.py`,
`pubspec.yaml`, `analysis_options.yaml`, `native/frozenight/Cargo.toml`,
`native/frozenight-wasm/Cargo.toml` — **all present**. So when Actions is
enabled, the workflow will not fail on a missing file.

Re-probed this round, including the official mirrors, so the "no SDK"
conclusion is not an artefact of one blocked host: `storage.flutter-io.cn`
(**000**), `storage.flutter-io.cn/flutter_infra_release/releases/releases_linux.json`
(**000**), `pub.flutter-io.cn` (**000**), `dl.google.com` (**000**),
`storage.googleapis.com` (**000**), `download.flutter.io` (**000**),
`static.rust-lang.org` (**000**). A filesystem-wide sweep
(`find / -xdev` for `dart`, `flutter`, `dart-sdk*`, `flutter_linux*`, plus
`~/.pub-cache`, `/usr/lib/dart`, `/snap`) finds **nothing** outside this
project's own platform folders. Bootstrapping is closed too: the Dart SDK has to
be built with a bootstrap SDK from `storage.googleapis.com`, and Rust needs a
bootstrap `rustc` from `static.rust-lang.org` — both blocked.

Still unavailable, for the reasons already proved in §10.1: no Dart or Flutter
SDK anywhere on the filesystem or reachable from it; `cargo`, `rustc` and
`wasm-pack` are not installed either, so the seven Frozenight jobs cannot be
built here (and `sh.rustup.rs` is outside the reachable host set).

### 11.3 Gate matrix for `a366106`

| Gate | Command | Result |
|---|---|---|
| YAML validity | PyYAML over all 12 workflow files | **PASS** (14 jobs in `ci.yml`) |
| Dart syntax | `python3 tool/dev/parse_check.py` | **PASS** — 234 files, tree-sitter-dart |
| Release tooling | `python3 -m unittest discover -s tools/tests -v` | **PASS** — 19/19 |
| `flutter pub get` | — | **BLOCKED** — no SDK, no `pub.dev` |
| `flutter analyze` | — | **BLOCKED** — same |
| `flutter test` | — | **BLOCKED** — same |
| Engine tournament (`flutter test tool/perf/tournament.dart`) | — | **BLOCKED** — same |
| Frozenight Linux/macOS/Windows/WASM/iOS/Android builds | `cargo build --release` | **BLOCKED** — no Rust toolchain |
| Android / iOS / macOS / Linux / Web builds | `flutter build …` | **BLOCKED** — no SDK |
| Real-engine protocol (external harness, Stockfish 11) | `python3 /tmp/protocol_game.py` | **PASS** — 3 games, 80 plies, all legal (§10.2) |
| GitHub Actions (`ci.yml`, 14 jobs) | — | **BLOCKED** — 0 workflows registered, 0 runs (§11.1) |

No Dart source was changed in this round, so nothing above is a regression of a
previous pass; the round exists to establish, or refuse to establish, the CI
evidence.

### 11.4 Independent review of the final head

Asked twice. `@coderabbitai review` at `a366106` (01:57:20Z) was answered
`⚠️ Action not completed — Review rate limited`, the same as at 01:49:48Z; the
check run is `completed / neutral`, not `success`. Kilo remains
`action_required`, Copilot reported insufficient quota, Qodo is paused. The four
findings CodeRabbit did raise at `33e74d0` are fixed (§10.4) but the commits
after that point carry no independent review, and nothing here pretends
otherwise.

---

## 12. Fifth round — final audit

Head at the start of this round: `c8e2d04` (local = remote = PR head). The
round re-validated the previous report rather than reading it, then audited the
full PR delta again.

### 12.1 Claims of the previous report, re-checked

| Claim | How it was checked | Result |
|---|---|---|
| Head is `c8e2d04`, PR #1 open, base `main` | `git rev-parse`, `git ls-remote`, `GET /pulls/1` | **confirmed** |
| `c8e2d04` is code-identical to `a366106` | `git diff --stat a366106 c8e2d04` | **confirmed** — 1 file, 138 insertions, the audit document only |
| 0 workflows registered, 0 runs | `GET /actions/workflows`, `/actions/runs`, plus per-event queries | **confirmed** (see §12.5 for what it does and does not prove) |
| Python release tooling passes | `python3 -m unittest discover -s tools/tests -v` | **confirmed** — 19/19 |
| Portions of the previous round were documentation-only | `git log`, per-commit diffs | **confirmed** |

### 12.2 New review feedback (both from the repository owner, 02:08Z)

Two P2 findings were posted after the previous report and both were verified
against the code. Both are **valid**, and the first is more serious than
reported.

**F1 — a search abandoned on timeout can answer the *next* request.**
`abandonSearch()` and the quiesce timeout both called `finishSearch(null)`,
which cleared `_running`/`_awaited` without the engine ever having sent its
`bestmove`. The next `startSearch` then saw an idle engine, sent `position` +
`go`, and registered a waiter — which the *abandoned* search's `bestmove`
completed, with a move computed for the previous position. That is the exact
defect `UciSearchCoordinator` exists to prevent, reachable again through the
timeout path. The reported impact (inverted eval while the late `info` lines
arrive) is the milder half of it.

- **Fix:** the coordinator counts `bestmove` lines it is still owed
  (`_owedBestMoves`). `abandonSearch()` and the quiesce timeout record a debt;
  `finishSearch` swallows the answer that settles it instead of handing it to
  whatever search is running, and `quiesceSearch` waits (bounded) for the debt
  before the next `position` is sent, so `_searchWhiteToMove` is still not
  overwritten while the old search is talking.
- **Deliberate limit:** if the engine ignores `stop` for the whole timeout it is
  wedged, and the debt is dropped rather than kept. Keeping it would stall every
  later search *and* swallow the first real answer, leaving the game with no
  move — worse than the race it protects against. The residual window (a
  wedged engine, older `info` lines) is the pre-existing race, on that
  connection only.
- **Teardown:** `dispose()`/`onProcessLost()` now call `resetSearches()`, which
  clears the debt — a restarted connection must not have its first answer
  swallowed.
- **Regression tests:** four, in `test/uci_search_coordinator_test.dart`
  (`abandoned searches`): the owed answer is not handed to the next request; the
  eval perspective stays with the abandoned search until it answers; a wedged
  engine neither stalls the next search nor has it eaten; a restarted
  connection inherits no debt.
  A pre-existing test in that file — *"a search that never answers is dropped so
  the next one can run"* — caught the first version of this fix, which kept the
  debt forever and would have hung the next search. The design was changed, not
  the test.

**F2 — a superseded switch could leave the selection and the running engine
different.** `_switchEngineTo` captured `previousId` and wrote `_engineId` and
the preference when `switchEngine` returned, with nothing checking whether a
later selection had been made meanwhile. Because `EngineService` now queues
switches in request order, the rollback of a *failed* switch is queued behind a
switch requested later — so the rollback disposes the engine the user picked and
starts the old one, while the screen and the saved preference name the new one.
Reachable by tapping **Switch to Built-in** on the failure snackbar while a
switch is still in flight, or by returning from Settings during one.

- **Fix:** `EngineService.switchRequestCount`, incremented synchronously by
  `switchEngine`. `_switchEngineTo` keeps the number its own call received and
  returns early — before recording the selection, before queueing a rollback,
  and before showing the failure message — when the count has moved on.
- **Regression test:** `test/engine_service_test.dart` — *"a superseded switch
  can tell from the request count"* — asserts the count is bumped synchronously
  (before the queue is reached) and that the older caller can detect it is
  superseded while the newest caller still owns the outcome. The screen-side
  guard itself is verified by source trace only: no test in the repository pumps
  `ChessGameScreen`, and building such a harness was out of scope for this
  round.

### 12.3 Independent audit of the rest of the delta

- `Process.start(profile.path, [])` — no shell, no argv, no `runInShell`; a
  profile path is the only user-controlled input to process creation, and there
  is no argument field to inject through.
- `positionCommandIsWhiteToMove` follows the parity of the move list against the
  base FEN's side to move — no replay, so a move the parser cannot reproduce
  cannot flip it.
- Duplicate-id repair in `EngineProfileStore` is deterministic
  (`id-dup`, `id-dup2`, …), which is what §1 (P0-6) now claims.
- `createEngineOrNull` / `EngineUnavailableException` / `looksLikeEngineId`:
  a persisted id that no longer resolves throws instead of substituting an
  engine.

### 12.4 Verification in this round

| Gate | Result |
|---|---|
| `python3 tool/dev/parse_check.py` (234 files) | **PASS** |
| `python3 -m unittest discover -s tools/tests` | **PASS** — 19/19 |
| PyYAML over 12 workflow files | **PASS** |
| `flutter pub get` / `analyze` / `test` / tournament | **BLOCKED** — no SDK (§10.1, §11.2) |
| `cargo build --release` (Frozenight ×7) | **BLOCKED** — no Rust toolchain |
| Platform builds (6) | **BLOCKED** — no SDK |
| GitHub Actions | **BLOCKED** — no workflow registered (§11.1) |
| Real-engine protocol (Stockfish 11, external harness) | **PASS** — unchanged this round; the coordinator is not on that code path |

No Dart process was executed for this round either, so the two fixes above are
reviewed and covered by tests that will run in CI, not executed here.
