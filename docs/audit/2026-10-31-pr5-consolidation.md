# PR #5 — consolidating the Engine Lab (audit and decision record)

Date: 2026-10-31
Branch: `consolidation/engine-lab-pr5` (also pushed as
`arena/d77cd611-scrispchess-extended`, same tree)
Sources: PR #3 (`6344129`) and PR #4 (`b4ec77a`), both branched from
`main` @ `20bc1b8`
Status: ready for review

---

## 1. What this branch is

PR #3 and PR #4 build the same feature twice. Both add an Engine Lab that
benchmarks engines and keeps the results. Both add rating maths, a benchmark
runner, a game loop, engine identity, and a place to store runs. They disagree
about almost every name, and each one contains work the other needs.

This branch is not a merge of the two diffs. It starts from `origin/main`, takes
PR #3's architecture as the base — it is the larger, more complete of the two,
and its model of a game already distinguishes a forfeit from a draw — and then:

* keeps every feature from PR #4 that PR #3 lacks (see §3);
* fixes the defects both PRs carry, and the ones their combination creates;
* deletes the duplication instead of reconciling it with adapters, so each
  subsystem has exactly one implementation;
* makes the result compile and pass its own tests, which neither PR did at its
  head commit.

## 2. One implementation per subsystem

| Subsystem | Kept | Dropped from the other PR | Why |
|---|---|---|---|
| Benchmark plan and schedule | `lib/bench/benchmark_plan.dart` (PR #3) | PR #4's inline schedule | The plan is a first-class object: it can be estimated before it runs, replayed, and tested without an engine. |
| Game loop | `lib/bench/game_player.dart` (PR #3) | PR #4's `_playGame` | PR #3's loop classifies failures and stops on a cap; PR #4's still had "ended without mate ⇒ draw". |
| Runner | `lib/bench/benchmark_runner.dart` (PR #3) | PR #4's `engine_lab_runner` | Pause/resume/cancel, partial saves and drainable engines exist only here. |
| Rating maths | `lib/services/rating_fit.dart` (PR #4) | PR #3's copy of the same maths | PR #4's version is the same solver plus a `dart test` suite that runs without Flutter; `lib/bench/elo.dart` stays as the reporting layer (intervals, quality, connectivity). |
| Storage | `lib/bench/benchmark_store.dart` + `benchmark_storage_{base,io,web}.dart` (PR #3) | PR #4's `EngineLabStore` | PR #3's store has schema versioning, checksums, an index, quarantine and additive import. PR #4's filesystem atomicity (tmp → fsync → rename) was folded into `FileBenchmarkStorage`, and its `.bak` idea was already there. |
| Engine identity | `lib/bench/engine_identity.dart` (PR #3) | PR #4's `engine_fingerprint*.dart` | PR #3's identity carries platform, backend, advertised options, applied configuration, and the fingerprint kind (SHA-256, stat, or built-in build id). |
| Match/tournament service | `lib/services/engine_match_service.dart` (PR #3's model) | PR #4's name-keyed rewrite | The Lab and the match screen now share one game loop; identity is the engine id, never the display name. |
| Presets, gauntlet, warm-ups, seeds, repetitions | benchmark config + plan | — | All preserved; the config carries them and the plan honours them. |

Removed in the process: PR #4's `engine_lab_store.dart`, `engine_lab_runner.dart`,
`engine_lab_storage_native.dart`, `engine_fingerprint.dart` and its duplicate
game loop; PR #3's second copy of the rating solver.

## 3. Features preserved from both PRs

Every item below is reachable from the UI and exercised by a test or by
`flutter analyze` (which type-checks every call site).

From PR #3:

* presets (Quick / Standard / Accurate / Custom), round robin and gauntlet with
  an explicit reference engine, warm-up games, colour balancing, opening suites,
  ply cap, game cap, wall-clock cap, seed;
* live board, per-game progress, pause / resume / cancel, partial results saved
  during a run;
* Bradley–Terry ratings fitted over all games, centred on the run, with a 95%
  interval, a quality grade and connectivity warnings;
* calibrated Elo only with a complete, declared, budget-compatible anchor;
* forfeit / aborted / adjudicated / cancelled as distinct outcomes, kept out of
  the fit;
* per-engine latency percentiles, nodes, NPS, depth;
* stability diagnostics;
* durable history: one document per run, schema version, checksum, quarantine
  of unreadable documents, import without overwriting;
* exports: PGN per game, CSV per game and per engine, JSON (one run or all),
  Markdown report;
* automatic benchmarks after adding an engine and after a binary change, with a
  reason for every decision including refusals.

From PR #4:

* SHA-256 binary fingerprints with a size+mtime fallback marked as the weaker
  signal, and a cache keyed on profile id that invalidates on size/mtime change
  (so the version-change trigger notices a replaced binary);
* `drainSearch` / `SearchDrainableEngine`, so a stopped UCI search cannot answer
  the next one;
* atomic native writes (temp file, flush, rename) and a `.bak` copy;
* web storage through `shared_preferences`, namespaced away from player
  preferences;
* presets/shape of the engine Lab store's additive import (kept as behaviour,
  not as a second module);
* `flutter_bootstrap.js` web entrypoint and build-time validation of the
  entrypoint the page actually loads;
* `tools/release_version.py` accepting Flutter prerelease versions
  (`2.3.2-dev2+18`), used by the macOS App Store upload;
* the workflow hardening (input handling, least-privilege permissions,
  artefact honesty) and its extension to the sibling workflows that had the same
  defect.

## 4. Defects: status of every finding

Statuses: **FIXED** (changed in this branch, with a test where one is possible),
**ALREADY FIXED** (fixed on `main` or by the PR that was adopted),
**INVALID** (the finding does not describe this code), **BLOCKED** (cannot be
fixed or verified here, with the reason), **OPEN**.

### PR #3 findings

| # | Finding | Status | Evidence |
|---|---|---|---|
| 3.1 | Colour-swapped games share an opening, so opening and colour are confounded | FIXED | `PlannedGame.gameInPairing` + `openingForGame`; `test/bench_plan_test.dart` asserts both colours of a pairing face the same line and that a repetition samples a different one. |
| 3.2 | `maxDuration` is only checked between games, so one long game ignores it | FIXED | Deadline `Timer` stops the engines mid-search; `GameStop.durationLimit` records the game as aborted and ends the run. `test/bench_runner_test.dart` proves an in-flight search is stopped and the game is not rated. |
| 3.3 | Warm-up games are played outside `maxGames` | FIXED | `effectiveWarmUpGames` / `effectiveRecordedGameCap` are used by the planner, the estimator, validation and the UI; two games are kept for evidence. Tests cover cap < warm-ups and cap exactly at the warm-up count. |
| 3.4 | `repetitions` is stored, shown and ignored | FIXED | The plan replays the schedule once per repetition with a mixed seed; totals, estimate and cap count every repetition. Tests assert the game count and the seed behaviour. |
| 3.5 | `estimateWorkload` disagrees with what the runner plays | FIXED | One set of helpers; `BenchmarkPlan.estimate()` derives the estimate from the plan itself, and a test asserts the two agree. |
| 3.6 | A corrupt document is deleted together with its `.bak` | FIXED | `readBackup` on the storage interface, archive-then-recover in the store; `test/bench_store_test.dart` covers recovery, both copies corrupt, newer schema, checksum mismatch. |
| 3.7 | Duplicated `if (_cancelled)` in the runner loop | FIXED | Removed. |
| 3.8 | `engine_lab_screen.dart:1328` estimates a round robin under a gauntlet | INVALID | The screen computes pairings per format (`_selected.length - 1` for a gauntlet) and the dialog now quotes the same `WorkloadEstimate` the runner will honour. |
| 3.9 | `deleteRun` erases both copies | INVALID | Deleting a run must delete its recovery copy: otherwise "delete" leaves the bytes on disk. The index and the identity cache are deliberately kept. |
| 3.10 | The Engine Lab screen does not compile | FIXED | `EngineProfile` was never imported; the diagnostics tab used a `StabilityCheck`/`StabilityReport` API that does not exist; five localisation keys (`engineLabPaused`, `copied`, `engineLabImportEmpty`, `engineLabImported`, `engineLabImportRenamed`) were never added. Found by CI, not by review. |
| 3.11 | PR #3's own test suite never passed at its head | FIXED | Two calibration tests got the cohort refusal before the anchor-specific one; `match_result_test` carried expectations from before scores were summed per engine. Both addressed (see §6). |

### PR #4 findings

| # | Finding | Status | Evidence |
|---|---|---|---|
| 4.1 | A depth and a time control are both sent, so the time control is a lie | FIXED | `MatchConfig.depthPerMove` is nullable, `MatchConfig.timed` clears it, `effectiveDepth` refuses a hand-written combination; `test/match_config_test.dart` and the existing `uciGoCommand` tests pin it down. |
| 4.2 | `engine_match_service` keys results by display name and defaults to a draw | INVALID for this tree | PR #4 replaced PR #3's service; this branch keeps PR #3's id-keyed model with explicit outcomes. The two findings about that file (`:149`, `:418`) describe PR #4's own rewrite, which is not here. |
| 4.3 | `engine-strength.yml` interpolates workflow inputs into shell source | FIXED | Inputs arrive through `env`, with a numeric check. The same defect existed in `appstore-screenshots.yml`, `engine-latency.yml`, `lc0-oracle.yml` and `web-bundles.yml` and is closed the same way. |
| 4.4 | `engine-strength.yml` claims it uploaded a log whether or not one exists | FIXED | The summary is conditional on the file, and the artefact carries the benchmark metadata. |
| 4.5 | `release_version.py` mishandles prerelease versions | FIXED | Duplicate-then-parse, with `tools/tests/test_macos_release.py` covering `2.3.2-dev2+18`; the macOS upload now reads the version from it rather than from a `sed`. |
| 4.6 | `deploy-web.yml` / `release.yml` treat a half-built web bundle as success | FIXED | Both validate the entrypoint the page actually loads (`main.dart.wasm` + bootstrap, or `main.dart.js` + bootstrap). |
| 4.7 | `web/index.html` loads `main.dart.js` unconditionally | FIXED | Boots through `flutter_bootstrap.js`. |
| 4.8 | `engine_lab_store.dart:35`, `engine_lab_storage_native.dart`, `engine_lab_screen.dart:239` | INVALID for this tree | Those modules are not in this branch; the behaviour they protect (schema, atomic write, `.bak`, depth/time precedence) is implemented and tested in the modules that are. |
| 4.9 | `generic_uci_engine.dart:234` (option overrides sent before `isready`) | ALREADY FIXED | `initialize()` sends `isready` and waits for `readyok` before reporting ready; the comment there says why. |
| 4.10 | `CHANGELOG.md` claims that did not match the code | FIXED | The changelog section is rewritten to describe what this branch does, including the two caps and the recovery path. |
| 4.11 | Least privilege: workflows without a `permissions:` block | FIXED | `ios-release.yml` declares `contents: read`; `web-bundles.yml` no longer asks for pull-request write it does not use. |

### Defects found while consolidating (not in either review)

| # | Defect | Status | Evidence |
|---|---|---|---|
| 5.1 | Recovery from `.bak` went through `write`, which copies the corrupt primary over `.bak` first, destroying the last good copy | FIXED | `BenchmarkStorage.restore` writes the primary only; a file-backend test asserts the recovery copy survives. |
| 5.2 | A run whose engine failed to start reported `stopReason: completed` | FIXED | The runner sets `engine failure` when it records an aborted game; covered by the failed-handshake and three-forfeits tests. |
| 5.3 | `stop()` on a disposed or errored engine reported it `ready` | ALREADY FIXED (generic) / FIXED (Lynx) | The generic engine defers `ready` to the matching `bestmove`; native and web Lynx keep the `thinking → ready` transition and nothing else. `test/generic_uci_init_test.dart` covers the disposed case. |
| 5.4 | A profile's saved `Skill Level` was overwritten by the strength slider | FIXED | `test/generic_uci_go_test.dart` drives a real UCI script and asserts the profile value wins. |
| 5.5 | A failed handshake threw out of the match service instead of producing a forfeit | FIXED | `MatchConfig`-level init failures are recorded per engine and reported as forfeits with `ForfeitReason.handshakeFailure`; `TournamentEnginesUnavailable` tells the screen. |
| 5.6 | Cancelling during one handshake still started the next engine | FIXED | Both the runner and the tournament check the flag before the next `initialize()`; the runner test asserts the second engine is never started. |
| 5.7 | CSV cells starting with `=`, `+`, `-`, `@`, tab or CR are executed by spreadsheets | FIXED | `_csvEscape` prefixes an apostrophe; tests cover all six triggers. |
| 5.8 | Self-play games entered the standings | FIXED | Excluded from the fit instead of throwing. |
| 5.9 | Lynx is built by the factory but missing from the one built-in engine list | FIXED | `builtInMatchEngines` includes it, so the Lab and the match screen can both offer it. |
| 5.10 | `BenchmarkConfig.copyWith` takes factories for nullable fields; a caller passed a value | FIXED | `AutoBenchmarkSettings.toConfig` passes `maxGames: () => maxGames`. |
| 5.11 | `engine is SearchTelemetry ? engine : null` has the engine's static type, not the interface's | FIXED | Explicit casts at the three sites. |
| 5.12 | `engine is! SearchDrainableEngine` does not promote: Dart promotes only to a subtype | FIXED | Explicit cast in `drainEngine`. This one line stopped seven test files from loading. |
| 5.13 | A local named after the method it calls shadowed it (`candidates()`) | FIXED | Renamed, with a comment. |
| 5.14 | `gamesPlayed` counted only rated games | FIXED | Counts what the name says, excluding games that never reached the board (`aborted`). |

## 5. Validation

Commands actually run, in an environment without a Flutter SDK (see §7 for what
that blocks). CI-parity results come from the `Lab diagnostics` workflow, which
runs the same gates as `ci.yml` and posts their output as a PR comment.

| Gate | Command | Result |
|---|---|---|
| Dart parse (note: not type analysis) | `python3 tool/dev/parse_check.py` | 273 files, no syntax errors |
| Localisation keys | `python3 tool/dev/l10n_add_keys.py --check` | 168 Engine Lab keys present |
| Python tooling | `python3 -m unittest discover -s tools/tests` | 19 tests, OK |
| Rating maths | `python3 tool/bench/verify_rating_math.py --trials 60` | 25 checks passed |
| Workflow YAML | `python3 -c "yaml.safe_load(...)"` over `.github/workflows/*.yml` | all parse |
| Workflow shell | `bash -n` on every `run:` block in the diagnostics workflow | clean |
| Whitespace | `git diff --check` | clean |
| Type analysis | `flutter analyze --no-fatal-infos --no-fatal-warnings` (CI parity) | **exit 0** — `Lab diagnostics`; the exact SHA and run link are in the pull-request description, because this file cannot name a commit that must exist before it can be written |
| Unit/widget tests | `flutter test` (CI parity) | **exit 0** — same run |
| Engine Lab gate | `Engine Lab` workflow (plan tests, rating maths reference, localisation) | **success** — same SHA |
| Application builds | `CI`: Build Android, iOS, Linux, macOS, Web (WASM) | **success** — same SHA |
| Engine builds | `CI`: Frozenight for Android arm64, Linux, Windows, WASM, iOS, macOS | **success** — same SHA |
| Windows application build | — | **BLOCKED** — `ci.yml` has no Windows *application* job (only the Windows engine build); not claimed |
| macOS/iOS release upload | `macos-appstore.yml`, `ios-release.yml` | **NOT RUN** — release-triggered; not claimed |

Earlier commits of this branch failed these gates, and the failures are what
drove the last fixes: the imported PR #3 code did not type-check at all (§4,
3.10), and two of PR #3's own tests encoded behaviour its code no longer had.
Each result above belongs to one commit, named in the pull request; a green run
on an earlier commit is never used as evidence for a later one.

## 6. Two judgement calls worth reviewing

**Calibration refusal order.** A run can fail calibration for several reasons at
once. The anchor's own problems are reported first (absent, too uncertain, wrong
budget), then a mixed-platform run. A mixed run still never produces a published
number; the change only decides which sentence the user reads. It also makes
PR #3's existing calibration tests pass, which they did not.

**`gamesPlayed` semantics.** The field counts every game an engine took part in
except an aborted one — an aborted game never reached the board. Rated games can
be derived (`GameResult.isRated`), and the report prints both. The older test
asserted the rated-only count; it now asserts the distinction explicitly.

## 7. What is not proven here

* **No Flutter SDK in this environment.** `flutter pub get`, `flutter analyze`,
  `flutter test`, `flutter build web`, and every platform build (`apk`, `ipa`,
  `linux`, `windows`, `macOS`) run only in CI. This audit therefore relies on the
  diagnostics workflow for type analysis and tests, and reports platform builds
  from the CI runs of the exact head SHA — never from a previous commit.
* **No real engine binaries.** The engine tests use small shell scripts that
  speak UCI (so what is asserted is what went over stdin) and a scripted
  `ChessEngine` (so the runner's loop, forfeits and deadline are the real ones).
  Nothing here measures the strength of Stockfish or Lynx, and nothing in this
  branch publishes a rating.
* **Automated review.** CodeRabbit was configured on PR #4 and reviewed
  `22c97206`; on a draft PR it deliberately does not review, which is the state
  of PR #5 (its one comment says so). Codex answered on PR #4 (`b4ec77a`,
  `ee781f77`, `a197424` and four follow-ups) and on PR #3 only at `216ca6e`,
  which is not that PR's head. No automatic-review mechanism was assumed to work
  for a new branch; none was triggered against this SHA.
