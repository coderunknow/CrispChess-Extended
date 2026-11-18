# dev6 resource architecture — Custom UCI Engine Manager open path

Date: 2026-11-18. Scope: eliminate the CPU and memory consumption caused by
opening Custom UCI Engines / Engine Manager, without harming engine strength,
benchmarks, or configured options. Companion documents:
`docs/audit/2026-11-18-dev6-execution-status.md` and
`docs/audit/2026-11-18-dev6-comprehensive-audit.md`.

## Current architecture (before dev6)

Opening the manager (`lib/screens/engine_manager_screen.dart`) does three
things in order:

1. `initState` → `_loadProfiles()` — `EngineProfileStore.load()` reads the
   profiles JSON from `shared_preferences`. Cheap; not a bottleneck.
2. `unawaited(_checkForChangedEngines())` — **runs before any setting is
   read** — `BenchmarkService.changedEngines()`:
   - reads `identities.json` from disk (every call, no memoization),
   - for every previously benchmarked engine calls `identityFor`:
     - custom engines: `stat` + (on any cache miss) a full streamed SHA-256 of
       the binary **on the UI isolate**, with the fingerprint cache document
       (`fingerprints.json`) re-read from disk and re-decoded per call;
     - the built-in Frozenight engine: constructs the native engine
       (`DynamicLibrary.open` + `frozenight_create`), disposes it, then hashes
       the whole runtime library — **uncached** — once here and once again in
       `decideAfterChange` when a change is suspected;
   - for each change, `decideAfterChange` → `runAutomatic` → `run` →
     `createRunner` → `BenchmarkRunner.run()`, which initializes every
     participating engine (real UCI child processes, up to 4 resident at once)
     and plays rated games up to the Quick-preset caps (24 games / 10 minutes)
     as a background singleton that outlives the screen.
3. `_maybeAutoBenchmark` after a successful add — same automatic tournament,
   gated by `afterAdd`.

The automatic triggers (`AutoBenchmarkSettings.afterAdd`,
`afterVersionChange`) defaulted to **ON** and were persisted under `lab.auto`.

## Confirmed bottlenecks and their fixes

| # | Bottleneck | Evidence | Fix |
|---|---|---|---|
| RC1 | A silent full-CPU tournament can start from opening the screen (defaults ON) | defaults in `benchmark_settings.dart`; measured defaults `true`/`true` in the baseline harness | Defaults OFF (constructor + `fromJson`); stored opt-ins untouched; `toConfig` caps unchanged |
| RC2 | Open-time scan runs even when no automatic run can start | scan executed before `autoSettings()` in the screen | Gate the scan on `settings.afterVersionChange`; skipped-open path ≈ 0.3 ms |
| RC3 | Cache documents re-read/decoded per call | counting-storage test shows ≥1 disk read per `fingerprintForProfile`/`knownIdentities` call before dev6 | In-memory memos refreshed by every write, dropped when a write fails; verified zero re-reads |
| RC4 | Frozenight runtime library re-hashed (and engine re-constructed) per open | `identityFor` built-in path had no cache | New `fingerprintForNativeLibrary(path)` cache with stat invalidation |
| RC5 | SHA-256 on the UI isolate | 227 ms wall for 20 MB in the baseline probe | `Isolate.run` worker hashing; digests pinned by tests |
| RC6 | No structured diagnostics | failures only in `debugPrint` | New diagnostics subsystem (below) |

## Behavior after dev6

### Opening the Engine Manager

- Factory settings: profile load + UI render only. No binary is read, no
  process starts, no benchmark can start. Measured: ≈0.3 ms settings read.
- `afterVersionChange` explicitly enabled by the user: one scan per visit
  (stat per known engine; SHA-256 only on cache misses; hashes on a worker
  isolate), and a re-run only if something actually changed — unchanged from
  the documented contract, minus the redundant work.

### Adding an engine

Unchanged user-visible flow: probe (`uci` handshake, no `go`, no search),
persist on success, then the same opt-in automatic decision. With the trigger
off, `decideAfterAdd` returns after a settings read (0.5 ms measured).

### Background benchmarks

Unchanged semantics: user-approved runs continue in the background, are
visible (`BenchmarkService.isRunning`, Lab), cancellable, capped by config,
and now logged (start/finish with duration and trigger). Automatic runs still
refuse to overlap a running benchmark or a preflight.

### Engine lifecycle

Unchanged contract: `idle → initializing → ready → thinking → stopping →
disposed`, single-flight initialization, no resurrection after dispose. What
changed: each transition of the process lifecycle now produces a structured
diagnostic record (start, ready, lost, stopped, disposed, init failed), and
lifecycle counters feed the resource sampler.

## Alternatives considered

1. **Limit UCI Threads/Hash/benchmark parallelism.** Rejected: rule 1.3 — the
   bottleneck is not engine configuration, and caps would degrade intended
   work. No resource limits were introduced.
2. **Drop the open-time scan entirely.** Rejected: the after-change
   re-measurement is a real, user-visible feature; the scan is correct *when
   the user opted in*. It is gated, not removed.
3. **Move the whole Engine Lab service to a background isolate.** Rejected:
   overkill for a ~10 ms path; the expensive piece (hashing) is exactly what
   moved to a worker isolate, and store state is process-local.
4. **Cache Frozenight identity in memory only.** Rejected: the persisted
   path+stat cache also survives restarts and is invalidated the same way the
   profile cache is (size+mtime), so a replaced library is still noticed.

## Benchmark integrity considerations

- Fingerprints are still content-based SHA-256; invalidation still keyed on
  size+mtime; a replaced binary is re-hashed and re-benchmarked exactly as
  before. No measurement was made cheaper by weakening identity.
- The Quick-preset caps (≤24 games, ≤10 min, adaptive stopping) are unchanged.
- Ratings, anchors, preflight admission and the runner's engine lifecycle are
  untouched by this branch (verified by the existing bench test suites, which
  run unchanged).

## Diagnostics subsystem design (Phase 5)

- `AppLogger` (singleton): levels TRACE..FATAL, bounded 2000-record buffer,
  per-session id + correlation counter, `timed()` helper, Flutter/zone error
  hooks installed in `main`. Persisted JSONL via `DiagLogSink`: batches, 2 s
  debounce, 1 MB rotation × 3 generations under the application support
  directory, all failures degrade to memory-only (never crash, never block the
  UI isolate; file writes are async appends).
- `ResourceSampler`: 2 s sampling **only while the viewer is open** and
  switchable there; `ProcessInfo.currentRss`; engine/probe/benchmark counters
  maintained at the spawn/dispose sites in `generic_uci_engine.dart` and
  `benchmark_service.dart`. No PowerShell, no process scanning, no polling at
  idle.
- Viewer `DiagnosticsScreen` (Settings → Diagnostics & Logs; one-tap from the
  Engine Manager's engine-failure snackbars): level/component/text filters,
  virtualized list, per-entry detail with stack traces and copy, copy visible
  range, confirmed clear, export.
- Export (`DiagnosticReportBuilder`): `diagnostic-report.zip` with
  `summary.md`, `metadata.json`, `application.log`, `errors.json`,
  `lifecycle.json`, `performance.csv` (only files actually collected), every
  text through export-time redaction (tokens, credentials, personal paths,
  emails), a size preview dialog before saving, saved via the OS save dialog
  (`file_picker`), never uploaded by the app.

## Testing strategy

- Deterministic regression tests per fix (see the execution status, Phase 4).
- Reproducibility harness `test/perf/engine_manager_open_perf_test.dart` used
  for before/after numbers (raw JSONs in `docs/audit/`).
- Full existing suite for regressions; diagnostics suites for the new
  subsystem; widget-level gate tests for the screen path.
- Target hardware (Windows 10 LTSC / i5-7300U): owner-run validation with the
  provided build; deliberately not claimed from CI.
