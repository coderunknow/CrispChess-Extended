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
  an empty list, duplicate ids regenerated, migrated list written back. The
  screens also catch storage failures rather than taking the screen down.
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

- **`createEngine(name)`'s silent fallback for an *unknown built-in name*.**
  `createEngineForId` validates custom ids and throws, but an unrecognised
  `builtin:` id still reaches `createEngine`'s `default:` branch and yields
  `DartEngine`. A canonical list of built-in names does not exist anywhere
  (each screen contributes its own ordering and localised descriptions), and
  inventing one to validate against would have re-created the duplicated list
  this change removes. In practice only values written by this app reach here,
  and they are always produced by `builtInEngineId(...)`. Recorded as a
  remaining limitation rather than papered over.
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
