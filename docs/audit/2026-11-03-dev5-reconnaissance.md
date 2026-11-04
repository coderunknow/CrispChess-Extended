# v2.3.2-dev5 reconnaissance and verification plan

Date: 2026-11-03. Baseline: `09ce48228da30454362e184220c066916169bd92`
(current remote `main`). PR #11 final head:
`428309e2504e073da6d3f3369093e4f534ba39fc`; merged at 07:24:31Z.
Baseline `pubspec.yaml`: `2.3.2-dev4+20`. Dev5 build: 21.

## Existing capabilities retained

- Engine registry with stable built-in/custom IDs and custom UCI profiles.
- Shared initialization coordinator, structured redacted failures, Preflight
  checks and identity/configuration-bound admission.
- Static round-robin/gauntlet plans, colour-reversed openings, legality checks,
  game loop, forfeits, pause/cancel, wall-clock/game caps and partial saves.
- Joint Bradley–Terry fit, observed Fisher standard errors, component detection,
  conservative legacy pairwise bound, relative Elo and gated calibration.
- Checksummed atomic run documents, migration/quarantine, PGN/CSV/JSON/Markdown.
- Model-download consent and several adapter-specific runtime downloads.

## Gaps and concrete source evidence

1. No opponent optimizer: `BenchmarkService._opponentsFor` takes the first three
   custom engines or first two built-ins; no information/cost objective.
2. `BenchmarkConfig.targetStdErr` is a standard-error stop, while the runner
   announces it as “within ±N Elo”; a standard error is not a 95% half-width.
3. No opening-cluster bootstrap or replicate validity accounting. Pairwise
   comparison uses `SE_A + SE_B` when covariance is unavailable (safe upper
   bound, but not the requested joint estimate).
4. `BenchGame` has no cluster/pair identifiers; aborted games store the suite ID
   as `openingId`. Legacy data cannot support honest opening-cluster inference.
5. `BenchmarkRun.enginesCsv()` declares `std_err` twice while emitting one value,
   shifting every later CSV column. Regression test will parse the header/row.
6. Native Stockfish reports installation instructions rather than a download
   requirement. Existing native model/Lynx/Stockfish.js fetchers check existence
   or length but not authenticated content; fixed `.part` names can collide.
7. `customEnginesSupported` excludes web but includes iOS, although iOS cannot
   spawn arbitrary downloaded UCI executables. Candidate filtering must reflect
   the actual sandbox.
8. Calibration stores anchor hardware as text but does not compare it with the
   current host, and does not propagate a published anchor uncertainty.
9. Built-in opening suites contain at most 16 positions; a cluster-bootstrap
   precision claim needs more independent clusters than a quick run can sample.

These are source-level reproductions/inspections, not claims of executed Flutter
tests. Regression tests and exact CI evidence are recorded in the final audit.

## Architecture decisions

Extend existing services; no replacement tournament stack. New pure-Dart
scheduler/statistics modules are consumed by `BenchmarkRunner` and
`BenchmarkService`. Downloads use one metadata/verification/install path and
preserve existing consent. Storage is platform-aware. Additive JSON fields keep
old runs readable; old runs without cluster IDs are explicitly unsuitable for
cluster-bootstrap precision claims.

## Required verification matrix

| Gate | Local sandbox | GitHub Actions |
|---|---|---|
| Dart syntax | tree-sitter parse if dependency installable | Flutter analyzer |
| Unit/widget/regression | SDK absent | full `flutter test` + Lab subset |
| Statistical reference | independent Python harness | same harness, two seeds |
| Real engines | no SDK/binaries initially | pinned Stockfish 16, committed WASM engines, new scheduler smoke |
| Linux | source/static | build, desktop integration, real UCI |
| Windows/macOS | source/static | release-build matrix; runtime only where explicitly tested |
| Android/iOS | source/static | compile/package; no device runtime claim |
| Web | source/static | WASM/JS build; browser cache behavior unit-tested where supported |
| Downloads | local filesystem/integrity tests | official-artifact verification where network permits |
| Release tooling | Python unittest | Python unittest + workflow pin checks |
| Review | independent diff audit | exact-head CodeRabbit if available |

Baseline exact-SHA runs reused: CI 41596124729, Engine Lab 41596124318, secret
scan 41596124146 (all success). Deploy Web 41596124411 failed at deployment;
no deployment is authorized or attempted for dev5.
