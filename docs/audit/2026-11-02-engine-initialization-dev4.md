# 2026-11-02 — Engine initialization contract and Engine Preflight (v2.3.2-dev4)

Owner report: Engine Lab shows **"Stockfish 16: failed — Bad state: initialize
returned with state error"**. Base: `main` at `5ee20cd` (v2.3.2-dev3).
Branch `arena/992e499f-crispchess-extended`, PR #11.

No Dart/Flutter SDK was available in the authoring sandbox. Everything below
marked *executed* ran in GitHub Actions on this repository; run IDs are given so
each claim can be checked. Nothing here is inferred from compilation alone or
from another operating system.

## 1. Root cause (reproduced, not inferred)

Desktop releases do not bundle Stockfish (GPL-3.0 vs. the MIT app). The dev3
built-in adapter (`StockfishEngine`) located a system Stockfish with `which`/
`where`. When that failed, `initialize()` caught the error, set
`state = error` and **returned normally**. `BenchmarkRunner` then found a
non-ready engine and threw a bare `StateError('initialize returned with state
error')` (`benchmark_runner.dart:294` at baseline), which became the Lab text.
The real cause — no Stockfish on the machine — was discarded. Every desktop user
without a system Stockfish hit this. (The dev3 audit saw the same secondary text
for the missing Frozenight DLL; that cause was fixed in dev3. This one is
different.)

### Reproduction (executed)

`.github/workflows/stockfish-rca.yml` runs one harness
(`tool/rca/stockfish_lab_repro_test.dart`: the real `BenchmarkRunner` with
`StockfishEngine` and the built-in Dart engine, no Stockfish installed) against
two trees on the same runners: the baseline `5ee20cd` and the candidate head.
Run **41400637184** (head 225c0c1), all four jobs green:

| Tree | Runner | Lab engine status | Reported reason | Kind / stage |
|---|---|---|---|---|
| baseline 5ee20cd | ubuntu-latest | failed | `Bad state: initialize returned with state error` | — |
| baseline 5ee20cd | windows-latest | failed | `Bad state: initialize returned with state error` | — |
| candidate | ubuntu-latest | failed | `Stockfish 16 could not start: the engine runtime is not installed on this device — No Stockfish executable was found … install it with your package manager (e.g. "sudo apt install stockfish"), or set CRISPCHESS_STOCKFISH_PATH …` | runtimeMissing / resolve-runtime |
| candidate | windows-latest | failed | same, with `winget install Stockfish.Stockfish` / stockfishchess.org | runtimeMissing / resolve-runtime |

The engine still fails on a machine without Stockfish — correctly — but the
report now names the cause and the remedy.

## 2. Initialization contract (P0, all engines)

`lib/engines/engine_initialization.dart` extends the existing
`EngineInitializationException` (not duplicated) with: engine id, requested and
detected version, backend, failure kind, exit code, stderr tail, runtime path,
detail and fallback reason, next to the dev3 fields (engine, version, stage,
platform, cause, stack, library path, symbol, native code, duration).
`toJson(redact: true)` removes home directories, usernames and app container
paths. Failure kinds: the full requested taxonomy plus `downloadRequired` and
`unknown`.

`EngineInitCoordinator` is the single start-up path:

- `initialize()` returns only in `ready`; any failure throws the structured
  exception (a normal return while not ready is converted to `readinessFailed`
  at stage `verify-ready`).
- Concurrent calls share one attempt; a ready engine returns at once; a retry
  after a failure starts fresh; non-retryable failures are returned again.
- `dispose()` during start-up ends `cancelled`, never `ready`, and runs cleanup.
- A legitimate backend fallback (Lc0 ONNX native → Dart) is preserved and
  recorded as the effective backend plus reason; the identity moves the
  measurement into its own cohort (`… (fallback)`).

Adapters moved onto it: Stockfish native, Stockfish iOS (stockfish.js in
WebKit), Stockfish web worker, Lynx native and web, custom UCI
(`GenericUciEngine`), Lc0 native and web, Maia3, ChessMamba, Ghost, searchless,
Chess LM. Custom-UCI behaviour (handshake, options, profiles) is unchanged apart
from failures now being structured.

Stockfish runtime resolution (`resolveStockfishRuntime`): explicit path or
`CRISPCHESS_STOCKFISH_PATH` (authoritative: missing → `binaryMissing`, not
executable → `permissionDenied`) → Android asset → iOS (`unsupportedPlatform`
for the process adapter) → `PATH` → well-known install locations → otherwise
`runtimeMissing` with a platform-specific install hint. No `id name` →
`protocolError`. The detected version is reported, never relabelled as 16.

### Additional defect found: unhandled "Broken pipe"

The fake-process tests showed that writing to an engine that has already exited
(wrong architecture, missing DLL, not a UCI engine) raised an unhandled async
`Broken pipe` from `stdin.done`. `UciProcessLifecycle.watchProcess` now handles
`stdin.done` errors for the current process only, and `sendUci` in the custom-UCI
and Lynx adapters catches write errors (paths redacted). The failure is reported
as `processExited` with exit code and stderr tail.

### Real-engine finding: shared analysis stream (test defect, not product)

The genuine Stockfish 16 job first failed `real_uci_engine_test.dart` "mate for
the side to move uses the same perspective as centipawns" (expected `< -100`,
got `999`) — this test had never run in CI before. Cause: the test asked
`analyze(whiteMate).first` and then immediately `analyze(blackMate).first` on
one engine. The analysis stream is shared, and by design (asserted by
`generic_uci_init_test` "an eval still arriving from the stopped search keeps
its colour") the late `info` lines of the search being stopped are delivered,
converted with their own position's colour. Stockfish 16 is fast enough that
White's remaining `mate 1` lines (+999 for White, correct for that position)
were still queued, and `.first` of the second request picked one up. The cp
tests for both colours passed in the same run, which rules out a sign error.
The test now drains the first search (`drainSearch()`) before the second
position; the assertion is unchanged.

## 3. Engine Preflight (P1)

`lib/bench/engine_preflight.dart`, `lib/screens/engine_preflight_screen.dart`,
service methods in `benchmark_service.dart`.

- Steps: platform, runtime, initialization, readiness, identity, options, first
  search, legal move (validated with the game's own move application), cleanup.
- Statuses: passed, warning, failed, unsupported, notInstalled, timedOut,
  cancelled (and skipped for steps not reached).
- Downloads only after explicit consent; declining → notInstalled, nothing
  downloaded.
- Results are bound to engine identity/fingerprint, platform/backend,
  benchmark configuration digest and app build; any change makes them stale.
- Gate: only passed engines, or warning engines whose warnings were explicitly
  accepted, are admitted; every other engine is listed with its reason
  ("not checked", "result is out of date: …", "warnings not reviewed",
  status). Continue requires two admitted engines and, if anything is left out,
  an explicit review checkbox. `BenchmarkService.createRunner` refuses
  non-admitted engines for manual runs as well (defence in depth).
- A gauntlet whose reference engine is not admitted stops with a message; it is
  never silently re-centred on another engine.
- Per-engine cards, step chips, expandable diagnostics, copy diagnostics,
  retry, cancel. EN + DE strings; `tool/dev/l10n_add_keys.py --check` passes.

Reports and the Stability Probe store the structured diagnostic (kind, stage,
cause, exit code, stderr tail…), redacted, one entry per distinct cause. A
failed engine is never a valid measurement and never "completed". Old run
documents keep their checksums (the new keys are omitted when absent).

## 4. Tests

Deterministic (fake engines and executable scripts; `@TestOn('vm && !windows')`
for the process scripts):

- `test/engine_init_contract_test.dart` — coordinator states, concurrency,
  retry, dispose-during-start, wrapping/classification, taxonomy round-trip,
  redaction, slot joining, run-status/identity serialisation.
- `test/stockfish_runtime_test.dart` — resolver order and kinds, missing /
  non-executable / env var / PATH / nothing found, version parsing, process
  exit during handshake (exit code, stderr), handshake timeout, retry,
  concurrent initialize, dispose during initialize.
- `test/engine_preflight_test.dart` — every status and step, consent, timeouts
  with cleanup, illegal move, option/version/fallback warnings, cleanup failure,
  cancellation, gate admission and staleness.
- `test/bench_preflight_service_test.dart`, `test/stability_probe_test.dart`,
  `test/bench_engine_diagnostic_test.dart`,
  `test/uci_process_lifecycle_retry_test.dart`,
  `test/engine_preflight_screen_test.dart` (widget).
- `tools/tests/test_ios_release_guard.py` — ios-release dev-tag guard.

Lynx has no executable-path injection, so a fake-process Lynx timeout test is
not feasible; Lynx is covered through the shared coordinator contract.

Genuine Stockfish 16 (CI job `stockfish16-real` in `ci.yml`): official
`official-stockfish/Stockfish` tag `sf_16` = commit
`68e1e9b3811e16cad014b590d7443b9063b3eb52`, built from source with
`ARCH=x86-64-sse41-popcnt`, NNUE `nn-5af11540bbfe.nnue` checked against the
hash prefix in its name, `id name Stockfish 16` verified. Never committed or
bundled. Tests run with `REQUIRED=1` so a missing binary fails instead of
skipping: `test/stockfish16_integration_test.dart` (built-in adapter, Preflight
on every step, repeated init/dispose) and `test/real_uci_engine_test.dart`
(custom-UCI path: handshake, legal move, cp and mate perspective, clean stop).

## 5. Platform matrix

| Platform | Built | Fake-engine tests | Genuine Stockfish 16 | Status |
|---|---|---|---|---|
| Linux x86-64 | executed, passed | executed, passed | executed (see §7) | verified in CI |
| Windows x64 | executed, passed | not run (process scripts are POSIX) | not run | RCA executed (baseline vs candidate) |
| macOS | executed, passed | not run | not run | build only |
| Android | executed, passed | not run | not run | build only |
| iOS | executed, passed (unsigned) | not run | not run (stockfish.js 10.0.2) | build only |
| Web | executed, passed | not run | not run (web worker) | build only |

"Build only" is not verification of engine start-up on that platform.

## 6. Workflow change

`ios-release.yml` no longer runs the App Store job for `v*-dev*` tags (the dev1–
dev3 runs 41168930415, 41213598068, 41318615301 failed before upload); stable
tags and `workflow_dispatch` are unchanged. Release runs triggered by pull
requests only build and verify; `create-release` is tag-only.

## 7. Evidence

- RCA baseline vs candidate: run 41400637184 (head 225c0c1), 4/4 jobs green,
  results in §1.
- Genuine Stockfish 16, Linux x86-64: CI run 41403068465, job 125139989647
  (head 434d9b2): **11 passed, 0 failed, 0 skipped** — presence check (×2),
  handshake/identity, legal move, built-in adapter finds/starts/identifies
  Stockfish 16, cp perspective for both colours, Engine Preflight on every
  step, mate perspective, clean stop, repeated init/search/dispose. The earlier
  run 41400637020 (job 125132985301, head 225c0c1) had 10/11 with the test
  defect described in §2.
- The exact-head runs for the merged commit are listed in PR #11; this file
  is not edited after review so that the reviewed head stays the merged one.
