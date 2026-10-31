# Plan — v2.3.2-dev2: Engine Benchmarking and Performance Lab

Status: implemented in this branch (see `docs/audit/2026-10-31-engine-lab-audit.md`
for what was verified and what was not).

## Starting point (verified)

- `main` = `20bc1b8e670f8d75152a465ec3da094b2fcf2997`, tag `v2.3.2-dev1`.
- Existing pieces: `EngineMatchService` + `TournamentService`
  (`lib/services/engine_match_service.dart`), Bradley–Terry fitting
  (`lib/services/rating_fit.dart`), engine ids (`lib/engines/engine_registry.dart`),
  custom UCI profiles (`lib/services/engine_profile_store.dart`), the perf harness
  (`tool/perf/tournament.dart`), and the `engine-strength` / `engine-latency`
  workflows.
- Gaps found by the reconnaissance (details and evidence in the audit doc):
  - results and standings are keyed by display *name*, not by engine id;
  - any game that ends without checkmate — including one where an engine threw,
    crashed or returned an illegal move — is recorded as `1/2-1/2`;
  - there is no persistence of match/tournament results at all;
  - the tournament re-initialises nothing and mixes every engine it can build
    into one pool regardless of backend;
  - no performance metrics beyond per-move wall time in the CI harness;
  - no benchmark UI: one screen with a board, two dropdowns and a status line.

## Architecture (new code lives in `lib/bench/`)

Nothing in `lib/bench/` depends on a Flutter widget, so the whole benchmark
pipeline is testable without pumping a UI, and the same code serves the app and
`tool/` harnesses.

| File | Responsibility |
|---|---|
| `engine_identity.dart` | Stable identity: engine id, self-reported name/author, platform, backend, binary fingerprint, option digest, cohort key. |
| `benchmark_fingerprint*.dart` | Binary SHA-256 (`dart:io`, cached by size+mtime) or a no-op on web. |
| `benchmark_config.dart` | Presets, custom configuration, validation, workload estimation. |
| `opening_suite.dart` | Built-in opening suites, deterministic matched-pair selection. |
| `game_record.dart` | `GameOutcome`/`ForfeitReason`, `BenchGame`, PGN writer, latency stats. |
| `game_player.dart` | The one game loop (moves, legality, ply cap, failure classification). |
| `elo.dart` | Relative Elo with standard error, confidence interval and a quality grade; component/connectivity reporting. |
| `calibration.dart` | Calibrated Elo from a declared, sourced anchor — or honestly unavailable. |
| `benchmark_plan.dart` | Pairings (round robin / gauntlet), colours, openings, workload. |
| `benchmark_run.dart` | A stored run: config, environment, games, ratings, report rendering, CSV/JSON/PGN export. |
| `benchmark_storage*.dart` | Storage backend: files (native) or `shared_preferences` (web). |
| `benchmark_store.dart` | Run documents: atomic write, schema version + checksum, corruption quarantine, import/export, fingerprint cache. |
| `benchmark_runner.dart` | Executes a plan: engine lifecycle, warm-up, metrics, pause/cancel, adaptive stop. |
| `stability_probe.dart` | Repeated init/search/dispose diagnostics, illegal-move and timeout detection. |
| `benchmark_service.dart` | The three triggers, settings, background progress, notifications. |

Existing code is extended rather than duplicated:

- `EngineMatchService` keeps its public API but plays through
  `game_player.dart` and reports by engine id with explicit outcome kinds.
- `rating_fit.dart` keeps `fitRatings`/`PlayerRating` and gains the extra
  statistics (per-player CI inputs, prior games, component ids) that
  `elo.dart` needs, so there is one fitting implementation, not two.
- `GenericUciEngine` exposes search telemetry (`nodes`, `nps`, `hashfull`,
  `depth`) through the non-breaking `SearchTelemetry` interface, so the Lab can
  report NPS for engines that actually report it and `unavailable` for the rest.

## Persistence decision

Evaluated: `sqflite` (+ `sqflite_common_ffi` for desktop/web), `hive`, `isar`,
and plain documents.

Chosen: **one JSON document per run plus an index**, written atomically, with a
schema version and a SHA-256 checksum per document. Reasons:

- works on all six target platforms without a new native plugin, including web
  (where `shared_preferences` is a small key/value store and there is no
  filesystem);
- a benchmark run is a few thousand games at most — SQLite's advantage
  (indexed queries over millions of rows) is not needed, and the report reads
  the whole run anyway;
- the document *is* the export format, so "export a run" and "store a run" are
  the same code path and an export can be imported back losslessly;
- corruption is detectable (checksum) and recoverable (quarantine) per run
  rather than taking the whole database with it.

No new dependency is required by this choice. `crypto` is promoted from a
transitive dependency to a direct one (already resolved at 3.0.7) for SHA-256.

## Rating methodology

- **Relative Elo**: Bradley–Terry maximum-likelihood fit over every eligible
  game, geometric-mean centred (default 1500, labelled *relative*). Standard
  error from the Fisher information of the log-likelihood, 95% interval
  `rating ± 1.96·SE`, quality grade from games played *and* SE.
- **Calibrated Elo**: relative rating plus the offset implied by a **declared
  anchor** — an engine that is in the benchmark and has a published rating
  whose source, hardware, time control and date are recorded. If the anchor is
  absent from the run, is measured under a different time control, sits in a
  different cohort, or is itself too uncertain, calibrated Elo is reported as
  **unavailable** with the reason. No engine is assigned an invented absolute
  rating.
- Games that are aborted, cancelled, adjudicated by the ply cap, or lost by
  forfeit are **not** fed into the fit; they are counted and reported.

## Verification plan

No Dart/Flutter SDK exists in this sandbox (blocked, as in the previous round).
Mitigations, all of which are run and reported:

1. `tool/dev/parse_check.py` (real tree-sitter Dart grammar) over every source
   file, including the new ones.
2. An independent Python reference implementation of the rating maths
   (`tool/bench/verify_rating_math.py`) that runs the same algorithm used in
   `rating_fit.dart`/`elo.dart` over simulated tournaments and checks
   self-consistency (recovered rating gaps, CI coverage, anchor invariance,
   component detection, prior behaviour). This verifies the *algorithm*; it is
   not evidence that the Dart code runs.
3. `python3 -m unittest discover -s tools/tests` for the release tooling.
4. PyYAML parse of every workflow, plus assertion-level checks that the new
   benchmark workflow's gates reference real inputs.
5. Tests committed for CI to run (`flutter test`), listed in the PR.

Anything that cannot be executed here is reported as NOT RUN / BLOCKED in the
audit doc and the PR, never as passed.

## Implementation status (round six)

Built as planned, with these deviations, each of which is a decision rather than
an omission:

- **No new plugin.** The store writes files through `path_provider` on native
  platforms and `shared_preferences` in a browser (`benchmark_storage_*.dart`),
  both already in the dependency list. A key–value store with a checksummed
  JSON document per run survives a crash without a platform channel.
- **`crypto` became a direct dependency.** `lib/bench` hashes engine binaries
  and configuration digests; leaving it transitive would compile but is a
  `depend_on_referenced_packages` violation.
- **The match screen uses the same game loop.** `lib/services/
  engine_match_service.dart` now plays through `lib/bench/game_player.dart`, so
  forfeit/adjudication/cancellation exist once and the match screen cannot
  report a different result from the Lab for the same game.
- **Ratings moved to `lib/bench/elo.dart`** on top of the existing
  Bradley–Terry fit in `lib/services/rating_fit.dart`; there is still one fit,
  used by both screens. The match screen shows the Lab's intervals and quality
  grades rather than its own bare numbers.
- **Automatic runs are Quick-only and capped** (24 games, 10 minutes, no
  warm-up, fresh seed) and refuse on web or when the binary cannot be
  fingerprinted. Every refusal carries a reason; the reason is shown, not
  logged only.

Verification is reported in the audit, §13. Nothing in this round was executed
under a Dart VM: there is no SDK here.
