# dev6 binary acceptance checklist — 2026-11-18

Every criterion is marked only as its evidence allows. Classes: VERIFIED
(direct execution/source evidence in this environment), REASONED (derived from
inspected implementation), BLOCKED (needs an unavailable environment).
Nothing is marked complete without evidence.

## Phase 4 — performance repair

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 4.1 | Automatic benchmark triggers default OFF (add + version-change) | VERIFIED | `test/benchmark_settings_defaults_test.dart` (7 tests); baseline harness printed `defaultAfterAdd: true` before, `false` after |
| 4.2 | A stored explicit opt-in is preserved | VERIFIED | same file: stored `true` reads back `true` |
| 4.3 | Missing/corrupt settings read as OFF, never as ON | VERIFIED | same file: missing keys, corrupt JSON |
| 4.4 | Opening Engine Manager with triggers off performs no fingerprinting | VERIFIED | `test/engine_manager_scan_gate_test.dart` widget tests: `scanCalls == 0` for off and factory settings; gate log line observed |
| 4.5 | Opening Engine Manager with the trigger on scans exactly once | VERIFIED | same file: `scanCalls == 1` |
| 4.6 | Fingerprint/identity caches are not re-read from disk on repeat | VERIFIED | `test/benchmark_store_memoization_test.dart` with a counting `BenchmarkStorage` |
| 4.7 | Replaced binaries (size/mtime) still invalidate cached fingerprints | VERIFIED | same file: size-change and mtime-change cases re-hash |
| 4.8 | Native-library fingerprint cached with the same invalidation | VERIFIED | same file: `fingerprintForNativeLibrary` |
| 4.9 | SHA-256 runs off the UI isolate and returns the true digest | VERIFIED | `test/benchmark_fingerprint_isolate_test.dart` (digest equality, missing file, concurrency) — this test caught the dropped-`await` regression during the refactor |
| 4.10 | Opening the manager with factory settings starts no benchmark | VERIFIED | gate test + `decideAfterAdd` skip with defaults (`shouldRun == false` measured in the harness) |
| 4.11 | No arbitrary resource limits introduced (Threads/Hash/depth/duration) | VERIFIED | diff review: no limit added; `toConfig` caps unchanged |

## Phase 5 — Diagnostics & Logs

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 5.1 | Structured logging with TRACE..FATAL and structured fields | VERIFIED | `test/diagnostics/app_logger_test.dart`; `DiagLogRecord` JSON round trip |
| 5.2 | Critical paths instrumented (engine lifecycle, benchmark start/finish, change scan, screen open/close, manager failures) | VERIFIED | source: `generic_uci_engine.dart`, `benchmark_service.dart`, `engine_manager_screen.dart`, `diagnostics_screen.dart` |
| 5.3 | Resource snapshots: process RSS + engine/probe/benchmark counters, sampled only during a diagnostic session, disable-able | VERIFIED (logic + unit) / REASONED (cross-platform RSS fidelity) | `resource_sampler.dart`; `ProcessInfo.currentRss` with `maxRss` fallback; sampler runs only from the viewer and has a switch. Per-platform RSS semantics are platform-dependent by Dart's own documentation — disclosed in the export metadata |
| 5.4 | Persistent, rotating, bounded logs; safe flush; corrupt-line recovery; no UI-isolate blocking | VERIFIED | `app_logger_test.dart`: rotation with loss proof (40/40 lines recovered), concurrent burst parseability (200/200), torn-line skip, clear-then-log |
| 5.5 | In-app viewer: filters, search, detail, copy, virtualized list, clear | VERIFIED (unit/widget level) | `lib/screens/diagnostics_screen.dart`; `ListView.builder` virtualization; filters implemented. Interactive runtime verification on target hardware: BLOCKED (owner) |
| 5.6 | Export produces `diagnostic-report.zip` with summary.md, metadata.json, application.log, errors.json, lifecycle.json, performance.csv | VERIFIED | `test/diagnostics/diagnostic_export_test.dart` decodes the zip and checks every documented file + preview bytes |
| 5.7 | Export-time redaction (tokens, credentials, personal paths, emails) with technical content preserved | VERIFIED | redaction suite (9 tests) incl. the self-detection regression; export test asserts the bundle contains no personal path while local logs do |
| 5.8 | User previews the report before saving; nothing is uploaded automatically | VERIFIED | export flow: preview dialog → OS save dialog; no network call in the diagnostics code path (source) |
| 5.9 | Logging overhead bounded (levels gate at zero cost; batched writes) | VERIFIED (structure) / REASONED (magnitude) | rejected-level records return before allocation; batched 2 s debounced appends; overhead measurement on the harness: profile-load path with logging ≈ baseline (0.46 vs 0.43 ms) |
| 5.10 | Viewer reachable from Settings and from an engine failure in the manager | VERIFIED | `settings_screen.dart` button; manager snackbars carry a "Diagnostics" action (`diagnosticsTitle` l10n key en+de) |

## Phase 6 — regression

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 6.1 | Full existing test suite passes on Linux | VERIFIED | full `flutter test` run recorded in the comprehensive audit |
| 6.2 | Existing bench/engine suites unchanged behaviour | VERIFIED | same run; bench suites executed without modification |
| 6.3 | Custom UCI process matrix (missing binary, non-UCI, timeout, death during init/search, concurrent init/dispose, restart) | PARTIAL — VERIFIED for the pre-existing suite that already covers these; no new matrix cases were added for dev6 because the engine lifecycle code is untouched apart from instrumentation | existing `test/` engine tests; diff review shows lifecycle contract unchanged |

## Phase 7/8 — platforms and target hardware

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 7.1 | Windows build + launch of the delivered exe | VERIFIED on Windows Server CI (GitHub Actions release.yml), BLOCKED on Windows 10 LTSC 21H2 | PR CI run; the release workflow launches `crispchess.exe` and inspects loaded modules. This is NOT a Windows 10 claim |
| 7.2 | Windows 10 LTSC / i5-7300U measurements on target hardware | BLOCKED | owner runs the provided build; procedure in the comprehensive audit |
| 7.3 | macOS/iOS/Android/Web runtime validation | NOT EXECUTED (disclosed) | outside this environment; no platform behaviour changed by the branch (web keeps the memory-only sink) |
| 8.1 | Before/after on the harness, same machine | VERIFIED | baseline/after JSONs in `docs/audit/` |
| 8.2 | Before/after on target hardware | BLOCKED | as 7.2 |

## Sign-off rule

A criterion may be upgraded only by new evidence, never by intention. The
owner's Windows 10 run is the gate for 7.2/8.2 and the final "is this complete"
decision.
