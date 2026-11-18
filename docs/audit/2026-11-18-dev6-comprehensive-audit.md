# dev6 comprehensive audit — Custom UCI Engine resource repair and Diagnostics & Logs

Date: 2026-11-18. Base: `main` at `56e0fc8` (v2.3.2-dev5+21). Target: `v2.3.2-dev6+22`.
Companions: `docs/audit/2026-11-18-dev6-execution-status.md`,
`docs/audit/2026-11-18-dev6-acceptance-checklist.md`,
`docs/plans/2026-11-18-dev6-resource-architecture.md`.

## 1. Original defects

Reported: opening Custom UCI Engines / Engine Manager causes CPU usage
approaching 100% and substantial memory consumption on Windows 10 LTSC 21H2
(i5-7300U, 8 GB, several custom UCI profiles saved); the responsible process
was unidentified.

## 2. Confirmed root causes (with locations and evidence)

| ID | Component | Location | Root cause | Evidence class |
|---|---|---|---|---|
| RC1 | Automatic benchmarks | `lib/bench/benchmark_settings.dart` (constructor + `fromJson`) | Both triggers defaulted **ON**; a changed or added engine + an open of the manager started a real tournament (up to 24 games / 10 min, several engine processes resident, singleton run outliving the screen) | VERIFIED (source + measured defaults in baseline harness) |
| RC2 | Engine Manager open path | `lib/screens/engine_manager_screen.dart` `_checkForChangedEngines` | Scan ran before any setting was read, so even disabled triggers paid stat + SHA-256 per previously benchmarked binary, per visit | VERIFIED (source; harness) |
| RC3 | Benchmark store caches | `lib/bench/benchmark_store.dart` `_fingerprintCache` / `knownIdentities` | Both cache documents re-read from disk and JSON-decoded on **every** call — several calls per open | VERIFIED (source; counting-storage test shows ≥1 read/call before dev6) |
| RC4 | Built-in identity | `lib/bench/benchmark_service.dart` `identityFor` (Frozenight branch) | Native engine constructed + whole runtime library SHA-256'd with **no cache**, twice per open when a change was suspected | VERIFIED (source) |
| RC5 | Fingerprinting | `lib/bench/benchmark_fingerprint_io.dart` `sha256OfFile` | Hashing on the UI isolate (20 MB ≈ 227 ms measured) | VERIFIED (harness) |
| RC6 | Observability | app-wide | No structured logging; failures only via `debugPrint`; no in-app way to see logs, resources or engine lifecycle | VERIFIED (absence in source) |

Possible contributors investigated and cleared: profile loading (prefs-sized,
0.43 ms), duplicate engine initialization (single-flight guarded), leaked
processes/subscriptions (audited; teardown/dispose paths are complete),
widget rebuild loops (list renders from loaded state), benchmark trigger
double-fire (`_checkedForChanges` once-per-visit guard existed).

## 3. Fixes (file → behavior)

1. `benchmark_settings.dart` — `afterAdd`/`afterVersionChange` default OFF;
   `fromJson` treats missing/malformed switches as OFF; stored values pass
   through unchanged.
2. `engine_manager_screen.dart` — the change scan is gated on
   `settings.afterVersionChange` (with a fail-safe: if settings cannot be
   read, skip the scan — losing a re-measurement is the safe side). Failure
   snackbars now log to the diagnostics system and offer a one-tap path to it.
3. `benchmark_store.dart` — in-memory memos for the fingerprint and identity
   caches; refreshed by every write; dropped when a write fails; readers get
   copies so no mutation can leak into the memo. New
   `fingerprintForNativeLibrary(path)` cache under the `nativelibs` storage
   key with the same size+mtime invalidation as the profile cache.
4. `benchmark_fingerprint_io.dart` — `sha256OfFile` hashes inside
   `Isolate.run`; streamed reading kept.
5. `benchmark_service.dart` — uses the native-library cache; logs benchmark
   run start/finish (trigger, engine count, duration) and change-scan
   duration; test seam `BenchmarkService.sharedOverride`.
6. `generic_uci_engine.dart` — lifecycle instrumentation: initialize
   start/complete/fail with duration, process started/lost/stopped/disposed,
   plus the `DiagCounters` process counters (double-count guarded by an
   `_aliveCounted` flag).
7. New `lib/diagnostics/` — `AppLogger` (levels, bounded buffer, session/
   correlation ids, timed helper, Flutter+zone error hooks), `DiagLogSink`
   (JSONL, batching, 1 MB × 3 rotation, storage-failure tolerance),
   `redaction.dart` (export-time), `resource_sampler.dart` (`ProcessInfo`
   RSS + lifecycle counters, viewer-scoped sampling), `diagnostic_export.dart`
   (zip bundle with preview).
8. New `lib/screens/diagnostics_screen.dart` — the viewer; reachable from
   Settings and engine failures. L10n: new `diagnosticsTitle` key (en/de).
9. `main.dart` — error hooks installed before the first frame; logger
   initialized without blocking start-up. `pubspec.yaml` — `archive` declared
   direct (already resolved 4.0.9 in the lock); version `2.3.2-dev6+22`.

No UCI option, no engine search, no benchmark config, no platform restriction
was changed. No arbitrary resource limits were introduced.

## 4. Before/after (committed harness, same machine: Linux 5.10 x86_64 sandbox, JIT debug build, 10 fake binaries / 84 MB)

Raw: `docs/audit/2026-11-18-dev6-baseline-measurements.json`,
`docs/audit/2026-11-18-dev6-after-measurements.json`.

| Metric | Before | After | Note |
|---|---:|---:|---|
| Default `afterAdd` / `afterVersionChange` | ON / ON | OFF / OFF | spec-mandated; opt-ins preserved |
| Open-path work with factory settings | full change scan (≥8.6 ms warm, 62.3 ms cold) + possible tournament | ≈0.3 ms (settings read only) | the tournament is the field's ~100% CPU suspect |
| Warm scan, same service (per visit) | 8.6 ms | 3.8 ms | when the user opted in |
| Cold scan (cache deleted) | 62.3 ms | 50.3 ms | hashing on worker isolate; wall time dominated by hashing itself |
| `decideAfterChange` (unchanged) | 2.0 ms | 0.04 ms | cache memos |
| SHA-256 20 MB | 227 ms on UI isolate (max event-loop gap 1.8 ms) | 211 ms on worker isolate | off the UI thread |
| Profile load | 0.43 ms | 0.46 ms | +diagnostics instrumentation overhead ≈ 0.03 ms |

These are the harness's environment. **Windows 10 LTSC 21H2 on the i5-7300U
has NOT been measured** — that remains the owner's gate. Procedure: install
the build from this PR's `windows-x64` artifact, save several UCI profiles
(with binaries ≥ tens of MB if available), open/close Custom UCI Engines
repeatedly with factory settings, then again with the after-change trigger
enabled, and read the numbers from Diagnostics & Logs → export.

## 5. Diagnostics & Logs — user-facing summary

- Where: Settings → "Diagnostics & Logs"; on any engine-init/configure failure
  in the Engine Manager, the failure message carries a "Diagnostics" action.
- Inspect: severity/component/text filters, per-entry detail with stack trace
  and copy, copy visible range, live resource header (RSS, engine processes,
  probes, benchmarks) sampled at 2 s only while open, switchable.
- Export: preview dialog listing each file and size → OS save dialog →
  `diagnostic-report.zip`. All text passes redaction (GitHub tokens, bearer/
  basic credentials, `password|token|api key|secret`-style key/values,
  `C:\Users\<name>` / `/home/<name>` / `/Users/<name>`, emails) while
  exception types, error codes, stages and timings are preserved. The app
  never uploads anything.
- Privacy: local log files are unredacted on the device; only exports are
  redacted (stated in the export's own metadata).
- Overhead: rejected levels cost a comparison; persisted entries batch into
  one small append per 32 records or 2 s; rotation keeps 1 MB × 3 files;
  sampling exists only inside the viewer.

## 6. Test evidence

- `flutter analyze`: **0 errors** (repo-wide info-level lints pre-existing).
- Full `flutter test`: **980 passed, 31 skipped, 1 failed** — the one failure
  was `bench_service_identity_test.dart`, which asserted the *old* ON default
  inside `decideAfterChange`; updated to opt in explicitly (test intent —
  override-vs-run-config detection — preserved), then passing.
- New suites: `benchmark_settings_defaults_test.dart` (7),
  `benchmark_store_memoization_test.dart` (5), `engine_manager_scan_gate_test.dart`
  (3 widget tests), `benchmark_fingerprint_isolate_test.dart` (3),
  `test/diagnostics/` (logger 9, redaction 9, export 7 = 25).
- Harness: `test/perf/engine_manager_open_perf_test.dart` — the same file
  produced both the baseline and the after-numbers.
- The widget-gate suite documents its own FakeAsync constraints (service
  initialised outside the test zone; the recording service does not run the
  real scan, which is the unit under test).

## 7. CodeRabbit

Status at writing time: **not started** for this branch (PR opened after this
audit; see the PR for the current review state; a review of an older commit
does not validate the head). Findings will be dispositioned in the PR.

## 8. CI

The PR against `main` triggers the repository's own `ci.yml` (analyze + test)
and `release.yml` (Android/Linux/Windows/macOS/Web builds; the Windows job
additionally launches the delivered `crispchess.exe` and records loaded
modules). Exact run IDs and conclusions are recorded in the PR description
when observed; queued runs are never reported as passed.

## 9. Remaining limitations (explicit)

1. **Windows 10 LTSC 21H2 / i5-7300U runtime validation: BLOCKED** — needs the
   owner's run of the provided build. CI Windows Server evidence is explicitly
   not a Windows 10 claim.
2. macOS/iOS/Android/Web runtime validation: not executed here; builds are
   produced by the PR's CI where applicable; no platform code paths were
   changed (web logging is memory-only by design).
3. The viewer's interactive behaviour under real hardware loads is verified by
   unit/widget tests, not by a manual GUI session in this environment.
4. The diagnostics screen's strings are currently English (repo l10n is en/de);
   the new snackbar action uses the localized `diagnosticsTitle` key. Widening
   localization of the viewer is left as a small, explicit follow-up.
5. Real-engine benchmarking of the repaired candidate (strength parity) was
   not re-run here; the benchmark code paths are unchanged except for logging
   and caching, and the bench suites pass unchanged.

## 10. Exact head SHA

Recorded in the PR description at opening time; any later commit is re-reviewed
and the SHA in the PR is updated. This document does not claim review of a SHA
it has not seen.
