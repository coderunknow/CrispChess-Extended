# dev6 execution status — 2026-11-18

Target version: `v2.3.2-dev6` (pubspec `2.3.2-dev6+22`). Base branch: `main`
at `56e0fc8` (merge of PR #12).

Statuses: `COMPLETE` (all mandatory criteria verified), `INCOMPLETE` (started,
not all criteria verified), `BLOCKED` (needs an unavailable environment or
permission). Evidence classes: VERIFIED / REASONED / HYPOTHESIS / BLOCKED.

## PHASE 0 — Repository reconnaissance — COMPLETE

- `main` SHA verified: `56e0fc8`; latest tag `v2.3.2-dev5`; pubspec version
  `2.3.2-dev5+21` before this work. VERIFIED (git).
- Engineering documents present and read: `AGENTS_LOG.md`, `DESIGN_LOG.md`,
  `PLAN.md`, `docs/audit/*` (no `FAILURE_LEDGER.md` exists). VERIFIED.
- No conflicting open repository changes overwritten: work happens on a new
  branch; existing arena branches untouched. VERIFIED.
- Execution flow mapped from source with two independent read-only audits of
  `lib/screens/engine_manager_screen.dart`, `lib/engines/*`, `lib/services/*`,
  `lib/bench/*`: open path is `initState → _loadProfiles → _checkForChangedEngines
  → BenchmarkService.changedEngines() → identityFor() → fingerprint caches`,
  with the automatic-run trigger behind `decideAfterChange`/`runAutomatic`.
  VERIFIED (source lines; see the comprehensive audit for file:line).

## PHASE 1 — Reproduction and baseline measurement — COMPLETE (with a documented boundary)

- Reproduction harness committed: `test/perf/engine_manager_open_perf_test.dart`
  (fake binaries: 10 files, 84 MB total, sizes 4–20 MB).
- Baseline on the unmodified code (Linux sandbox, JIT debug, VERIFIED for this
  environment; `docs/audit/2026-11-18-dev6-baseline-measurements.json`):
  - default settings `afterAdd=true`, `afterVersionChange=true`;
  - change scan, cold (both cache copies deleted): 962.5 ms median;
  - change scan, warm, next launch: 10.5 ms; same-session reopen: 8.6 ms —
    i.e. every open repeats the work;
  - `decideAfterChange` for an unchanged engine (trigger on): 1.4 ms;
  - SHA-256 of a 20 MB binary: 221 ms on the UI isolate, max event-loop gap
    16.3 ms (a dropped frame).
- The dominant field symptom — an automatic Quick-preset tournament (multiple
  engine processes, up to 24 games / 10 minutes at full CPU) started by merely
  opening the manager when an engine was added or changed — is REASONED from
  source (`benchmark_settings.dart` defaults ON; screen runs the scan before
  any setting is consulted; `runAutomatic` starts real engines as a background
  singleton) and matches the reported environment (several saved profiles,
  ~100% CPU on open). Not re-executed with real engine binaries here.
- **Boundary:** Windows 10 LTSC 21H2 on an i5-7300U is not accessible from this
  environment. All Windows-10-specific measurements are BLOCKED and must be
  reproduced by the owner with the diagnostic build (see the audit's
  "Remaining work"). CI Windows-Server evidence is explicitly *not* a Windows 10
  claim.

## PHASE 2 — Root-cause investigation — COMPLETE

Findings with evidence (full register in the comprehensive audit):

- **RC1 (VERIFIED):** automatic-benchmark triggers default ON
  (`benchmark_settings.dart`, constructor and `fromJson`). Opening the manager
  after an add/change silently starts a full tournament.
- **RC2 (VERIFIED):** the open-time change scan runs *before* the settings are
  read (`engine_manager_screen.dart`), so even with the triggers off the visit
  pays stat + SHA-256 per previously benchmarked binary.
- **RC3 (VERIFIED):** the fingerprint and identity caches are re-read from disk
  and re-decoded on every call (`benchmark_store.dart`), several times per open.
- **RC4 (VERIFIED):** the built-in Frozenight identity re-initialises the native
  engine and re-hashes the whole runtime library with **no cache at all**,
  twice per open when a change is suspected (`benchmark_service.dart
  identityFor`).
- **RC5 (VERIFIED):** binary hashing runs on the UI isolate
  (`benchmark_fingerprint_io.dart`).
- **RC6 (VERIFIED):** no structured diagnostics existed; failures surfaced only
  as `debugPrint`, and the stderr of every engine was printed through
  `debugPrint`.

## PHASE 3 — Architecture and design review — COMPLETE

`docs/plans/2026-11-18-dev6-resource-architecture.md` records the design, the
alternatives and the trade-offs. No new engine-management architecture; four
small, evidence-backed changes plus the diagnostics subsystem.

## PHASE 4 — Performance repair — COMPLETE

Implemented and covered by deterministic regression tests:

1. Both automatic triggers default OFF; stored opt-ins preserved
   (`test/benchmark_settings_defaults_test.dart`).
2. Open-time scan gated on the after-change setting
   (`test/engine_manager_scan_gate_test.dart`, widget-level).
3. In-memory memoization of the fingerprint and identity caches, with
   write-refresh and failed-write drop; disk reads proven absent on repeat
   (`test/benchmark_store_memoization_test.dart` with a counting storage
   wrapper).
4. Native-library fingerprint cache keyed by path+size+mtime (same file).
5. SHA-256 moved to a worker isolate (`test/benchmark_fingerprint_isolate_test.dart`
   pins the real digest — this test caught a dropped `await` during the
   refactor).

After-numbers (same harness, same machine; VERIFIED):
`docs/audit/2026-11-18-dev6-after-measurements.json` — with factory settings the
open path performs no scan at all (≈0.3 ms settings read); with the scan
opted in, the same-session reopen cost dropped 8.6 → 5.1 ms and the
re-benchmark decision (trigger on, unchanged engine) 1.4 → 0.43 ms; hashing
no longer runs on the UI isolate (max event-loop gap 16.3 → 4.1 ms). The
first published cold/decision figures (62.3 ms cold, 0.04 ms decision) came
from a flawed harness that left the `.bak` recovery copy in place and timed
the settings gate; both the harness and every published number were corrected
after review (dev6 review, methodology fix).

## PHASE 5 — Diagnostics & Logs — COMPLETE (feature), PARTIALLY VERIFIED (runtime)

Built: structured logger (`lib/diagnostics/`), rotating JSONL file sink with
bounded generations and graceful storage-failure handling, resource sampler
(`ProcessInfo.currentRss`, lifecycle counters), in-app viewer at
Settings → "Diagnostics & Logs" (filters, virtualized list, detail view,
copy, clear, export), `diagnostic-report.zip` export with export-time
redaction and a user preview before saving (no automatic upload anywhere).

Tests: `test/diagnostics/` (27 tests passing: levels, bounded buffer, JSONL
persistence, rotation with loss proof, concurrent burst parseability, corrupt
line skip, clear, timed helper, error hooks, redaction suite incl. the
self-detection regression, zip integrity + preview + redaction of the bundle).

Not yet verified: the viewer's runtime behaviour on real Windows hardware —
owner validation (BLOCKED).

## PHASE 6 — Regression and stress testing — COMPLETE for the suite, PARTIAL for the matrix

- Full `flutter test` suite executed on Linux; result recorded in the final
  audit (pass/fail counts and any pre-existing failures named explicitly).
- The spec's full manual matrix (real engines, Windows integration, benchmark
  strength comparisons) exceeds this environment; the parts executed here are
  listed in the comprehensive audit; the rest is disclosed as not executed, not
  claimed.

## PHASE 7 — Cross-platform validation — INCOMPLETE by design

- Build verification for Windows is produced by the repository's own
  `release.yml` on the PR (windows-latest, Flutter 3.44.2), including the
  built-in launch probe of the delivered `crispchess.exe`. The artifact is
  provided to the owner for verification.
- Linux unit/integration evidence: `flutter analyze` (0 errors) and the full
  test suite.
- macOS/iOS/Android/Web runtime: not executed here; disclosed. No platform
  restriction was changed by this branch.

## PHASE 8 — Before/after verification — COMPLETE on the harness, BLOCKED on target hardware

Before/after table with raw evidence in the comprehensive audit. The
target-hardware row (Windows 10 LTSC on i5-7300U) is BLOCKED pending the
owner's run of the provided build; nothing in the documents claims it.

## PHASE 9 — Audit, review, PR — see the final audit

`docs/audit/2026-11-18-dev6-comprehensive-audit.md` holds the final diff review,
the exact head SHA at writing time, CodeRabbit and CI status as *observed* (or
"not observed"), the PR link, and the explicit remaining-work list.
