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
executable → `permissionDenied`) → Android asset (only if the build includes
one; release builds do not) → iOS (`unsupportedPlatform`
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
  downloaded. Engines declare pending downloads through `DownloadAwareEngine`
  without downloading: Stockfish (iOS/web), Lynx, and — after review — the model
  engines Lc0 (native and web), Maia3, Ghost, ChessMamba, searchless and Chess
  LM, which check the model cache (`isModelCached`; on the web the browser cache
  cannot be queried, so they always ask). Their model fetch now runs in the
  `download` stage, so a failed transfer is `downloadFailed`.
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
- The exact-head runs for the merged commit are listed in PR #11.

## 8. Review (CodeRabbit full review on 17fed43)

| Finding | Severity | Disposition |
|---|---|---|
| Lynx archive saved as `lynx.zip.part`; Windows `Expand-Archive` only accepts `.zip` (regression in this PR) | Major | Fixed: `lynx.part.zip` |
| Model engines (Lc0, Maia3, ChessMamba, searchless, Chess LM; also Ghost) could download in Preflight without consent | Major | Fixed: `DownloadAwareEngine` via the model cache; download stage; `test/model_download_consent_test.dart` |
| ios-release step guards true on push because GitHub coerces null == false; test evaluator used Python semantics | Minor | Fixed: manual clauses tied to `workflow_dispatch`; evaluator coerces like GitHub; step-only test (fails on the old workflow) |
| Release notes claimed excluded engines are listed in the saved run | Minor | Fixed wording: listed on the Preflight screen; only admitted engines run |
| Release notes implied fake-engine tests on other platforms | Minor | Fixed: Ubuntu only; others build-only |
| Review checkbox text said engines that did not pass are left out (accepted warnings are admitted) | Minor | Fixed EN + DE |
| README implied automatic runs are preflighted | Minor | Fixed: manual runs; automatic runs keep their rules |
| Contract test attached the second matcher after the shared failure could be delivered | Minor | Fixed: both matchers attached before completing |
| Annotator repeated failures in `--summary` mode | Minor | Fixed |

### Second full review (7f8be3a)

| Finding | Severity | Disposition |
|---|---|---|
| Runtime-refined identities (detected version, fallback backend) stored in runs made automatic change detection report a change against the registry's unrefined identity, so automatic benchmarks could repeat (regression from `withRuntime` in this PR) | Major | Fixed: `withRuntime` keeps the assumed fingerprint/backend (`sourceFingerprint`, `sourceBackend`, exported only when set); `changeFrom(sourceOnly: true)` compares those, `identityKey`/cohorts are unchanged; test in `engine_init_contract_test.dart` |
| Custom UCI: dispose during the handshake waited for the 10 s timeout and was classified `handshakeTimeout` | Minor | Fixed: dispose releases the handshake wait; caller disposal is `cancelled`; test in `generic_uci_init_test.dart` |
| German consent text used formal "Ihre" | Minor | Fixed: "deine" |

### Third full review (eebe0df)

| Finding | Severity | Disposition |
|---|---|---|
| iOS Stockfish (WebKit): `_start` re-read the handshake completer fields with `!` after awaiting the method channel; `uciok`/`readyok` or a harness error delivered first cleared them, giving a null-check TypeError instead of ready or the real worker error | Major | Fixed: completers held in locals (fields stay for `_handleOutput`/`dispose`, which complete before clearing). The web adapter's `_send` is synchronous and has no await between creation and read, so it is unaffected |

### Fourth full review (a2e32eb)

| Finding | Severity | Disposition |
|---|---|---|
| Custom UCI: dispose during `File.exists()`/`Process.start()` left the new process running through the handshake timeout | Minor | Fixed: disposed checks before and right after launch; the new process is torn down and the start ends as a cancellation (the window is a single await, so it has no timing-based test) |
| Annotator skipped hidden reporter entries even when they failed (compile errors, `setUpAll`) | Minor | Fixed: failed hidden entries are kept |

### Fifth full review (c6a1ca2)

| Finding | Severity | Disposition |
|---|---|---|
| Release notes called the Android Stockfish asset "bundled" (release builds have none) | Minor | Fixed wording in the release notes, CHANGELOG and this audit |
| Preflight treated an adapter's own `TimeoutException` (no `uciok`/`readyok`) as Preflight's deadline, hiding the adapter's diagnostic | Minor | Fixed: only Preflight's deadline is flagged; everything else goes through `engineFailureOf`; test |
| Same in the Stability Probe | Minor | Fixed the same way; test |
| Preflight screen could call `_check` after being disposed during the first admission refresh | Minor | Fixed: `mounted` check |

### Sixth full review (947d179)

| Finding | Severity | Disposition |
|---|---|---|
| Runner decided "started, then failed while configuring" from the engine's live state; a failed option sync leaves Stockfish in `error`, so a configuration failure got a startup diagnostic | Minor | Fixed: an explicit flag set once `requireEngineReady` passes; test |
| Preflight's identity check warned on Lynx dev builds (`1.11.0-2e4b458f` vs `1.11.0`) | Minor | Fixed: a 7–40 character hex commit-hash suffix is the same release (`-rc1` is not); test |

### Seventh full review (b6edbb9)

| Finding | Severity | Disposition |
|---|---|---|
| `EngineInitCoordinator.run` trusted a shared `ready` state. Several adapters' `stop()` set `ready` unconditionally, so `EngineService.stop()` after a failed start could make the next `initialize()` skip the start and return success with no model or runtime | Major | Fixed: the coordinator takes the ready shortcut only after a successful attempt (flag cleared when a new attempt begins). `stop()` in Lc0, Lc0 web, Maia3, Stockfish iOS, Stockfish web and Frozenight web now returns to `ready` only from `thinking`, as Lynx already did. Two contract tests |
| `runAutomatic` threw (via `createRunner`) while Engine Preflight ran, despite "never throws for a refusal" | Minor | Fixed: it also refuses quietly while Preflight runs; test |

### Eighth full review (0ac8a5f)

Review 5738440495 on the exact head 0ac8a5f: no Major findings, one Minor.

| Finding | Severity | Disposition |
|---|---|---|
| `annotate_test_failures.py` read the UTF-8 test report with the OS default encoding (cp1252 on Windows) | Minor | Fixed: explicit UTF-8 on read, and stdout reconfigured to UTF-8. Reproduced first: under cp1252 the old script crashed (`UnicodeEncodeError`, exit 1) on a test name with `→`, breaking its always-exit-0 promise on the Windows RCA job; the new one exits 0 with the text intact |

Independent re-check of 0ac8a5f, before the fix above:

- All 48 changed Dart files parse; no file deleted; no binary committed.
- `AGENTS_LOG.md` and `DESIGN_LOG.md`: additions only. Version `2.3.2-dev4+20`.
- English and German ARB files have the same keys and placeholders, and every key exists in the generated code; all 228 key references in the Engine Lab, Preflight and report screens resolve.
- Absolute paths in the diff appear only in test fixtures that assert redaction.
- All workflow files parse; the iOS release guard test passes (10 tests).
- On 0ac8a5f: real Stockfish 16 11/11 (job 125314391606); RCA baseline still `Bad state: initialize returned with state error` on Linux and Windows, candidate `runtimeMissing` with install guidance on both.
- The one analyzer warning in a changed file (`chess_lm_engine.dart:255`) is on a line unchanged since the base commit 5ee20cd.
- The "Kilo Code Review" check reports `action_required` on every head because the account has insufficient credits; it is not a review and is not counted as one.

### Ninth full review (5c759d1)

Review 5739366024 on the exact head 5c759d1: no Major findings, one Minor (Security & Privacy).

| Finding | Severity | Disposition |
|---|---|---|
| When `pendingDownload()` threw, Preflight recorded a warning and still called `initialize()`, which downloads whatever is missing, without consent | Minor | Fixed: an unknown download state is not consent. The runtime step is `notInstalled`, the engine is never started (cleanup still runs). Preflight is the only consumer of `pendingDownload()`. Test: consent is not asked, `initialize()` never runs, the engine is disposed |

CI on ffd0504 (run 41476939319) did not complete: the "Frozenight (iOS)" job
was cancelled because no hosted macOS runner picked it up ("The job was not
acquired by Runner of type hosted even after multiple attempts"; GitHub's
macOS-capacity notice). No step ran; every other job matched the previous green
run. The session token cannot re-run jobs (HTTP 403), so CI was re-triggered by
the next commit (a release-notes line wrap) instead of being treated as passed.

### Tenth full review (a68368d)

Review 5740207229 on the exact head a68368d: no Major findings, three Minor. CI on a68368d was green, including real Stockfish 16 11/11 (job 125399260919).

| Finding | Severity | Disposition |
|---|---|---|
| `runWithRunner` did not refuse while a Preflight runs, so a runner prepared earlier could start mid-Preflight | Minor | Fixed; service test |
| A second tap on "Start benchmark" while admission is computed or a dialog is open started a second preparation (and Preflight); an admission error escaped `_start` unhandled | Minor | Fixed: a `_starting` flag guards re-entry and disables both buttons until the attempt ends; preparation errors are shown. Verified by analyzer and build only (no Engine Lab widget test exists) |
| The start button was squeezed by `Expanded` next to a long localized "Check engines" | Minor | Fixed: `OverflowBar` (side by side when they fit, stacked otherwise). Analyzer and build only |

CI on 13e184d failed (runs 41487234619, 41487234719): the new
`runWithRunner` test built its runner with the harness default of 5 ms per move,
which `createRunner` correctly rejects (minimum 10 ms) — a test-fixture error,
not a product defect (875 and 279 other tests passed). The fixture now uses
50 ms. "Build iOS" in the same run was cancelled again for lack of a hosted
macOS runner; no step ran.

### Eleventh full review (fdc726d)

Review 5741003831 on the exact head fdc726d: no Major findings, one Minor. CI on fdc726d was green, including real Stockfish 16 11/11 (job 125435237238).

| Finding | Severity | Disposition |
|---|---|---|
| A Preflight result for the built-in Stockfish was bound to its build-based identity only, so replacing the executable or changing `CRISPCHESS_STOCKFISH_PATH` after the check kept the result current and let a manual run admit a different binary | Minor | Fixed in the binding, not the identity. `PreflightBinding` gains an optional `runtimeDigest`: SHA-256 over the executable's location and its contents' SHA-256, so no path is exposed. It comes from the new `RuntimeDigestSource` interface, implemented only by the native Stockfish adapter, which resolves the executable without starting it. It is null on iOS and Web, and for every other engine. A different digest makes the result stale ("the engine executable changed"). The stored run identity is deliberately unchanged: switching the built-in Stockfish fingerprint from `builtin-build` to `sha256`, as suggested, would mark every stored Stockfish measurement as "binary changed" and trigger automatic re-benchmarks. That is a separate, pre-existing identity limitation, already noted in the prior audit. Tests: stale and JSON round-trip in `engine_preflight_test.dart`; digest stability, path and contents sensitivity, no start, and null when missing in `stockfish_runtime_test.dart` |

### Twelfth full review (5f3e6a4)

Review 5747483903 on the exact head 5f3e6a4: no Major findings, one Minor.

| Finding | Severity | Disposition |
|---|---|---|
| Release notes, CHANGELOG and README said a run continues with "the passed engines only", but an engine whose warnings were accepted is admitted too | Minor | Fixed: "the admitted engines (passed, or with warnings you accepted)". The Preflight button label "Continue with passed engines" keeps the specification's wording. The engines whose warnings were accepted are the ones the user explicitly reviewed on that screen |

### Thirteenth full review (f555e5f)

Review 5747867848 on the exact head f555e5f: no Major findings, one Minor (Security & Privacy). CI on f555e5f was green, including real Stockfish 16 11/11 (job 125739163314).

| Finding | Severity | Disposition |
|---|---|---|
| `EngineInitializationException.summary` (documented as redacted) inserted `detail` unredacted. A cleanup error such as a `FileSystemException` could carry a home-directory path into the summary and into the header of `toDiagnosticText(redact: true)`. The JSON field was already redacted | Minor | Fixed: `detail` is passed through `redactPersonalPaths` in `summary`. Test: a home path in the detail is absent from `summary` and from the redacted diagnostic text, and kept in the local unredacted text |

Stop condition for the review loop: the final head needs a genuine full
review with every Major finding fixed. Minor findings on that head are either
fixed, which makes a new head and needs a new full review, or dispositioned
here with a rationale and left unchanged.
