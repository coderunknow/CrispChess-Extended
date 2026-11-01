# Frozenight / Engine Lab — v2.3.2-dev3 investigation

Status: **investigation in progress; not a release approval**.

## Initial owner observations (preserved)

| Item | Confirmed information |
|---|---|
| Repository | `coderunknow/CrispChess-Extended` |
| Current release used | `v2.3.2-dev2` |
| Installation source | Official GitHub Release |
| Host platform | Windows 10 |
| Failing engine | Frozenight 7.0.0 |
| Failure location | Apparently Engine Lab; other execution paths require investigation |
| Presets | Failure reproduced with all four presets |
| Presets affected | Quick, Standard, Accurate, Custom |
| Visible error | `Frozenight 7.0.0: failed — Bad state: initialize returned with state error` |
| Diagnostic detail | The UI currently exposes no additional useful explanation |
| StockBear | Already registered as a Custom UCI engine and successfully plays an ordinary game |

The owner has not established that the defect is exclusive to Engine Lab.
Frozenight gameplay/Match and other Lab engines are not presumed working.
StockBear's separate UCI process does not validate Frozenight's FFI runtime.

## Baseline protection and reconnaissance

- Fetched `origin` and tags on 2026-11-01. Default remote branch: `main`.
- `main`, initial session HEAD, and peeled annotated `v2.3.2-dev2`:
  `5d2e8aecb83bd8c8bb0f9131375947545ec8220d`.
- Tag object: `bf9e2112084d9068795da021bc60f75d67a0c135`.
- PR #5 merged at 2026-10-31T15:00:32Z; reviewed head
  `f7c23727eb5b0c508ef297db1424c3c9979a14de`.
- Existing unrelated open PRs #3 and #4 are untouched.
- Existing release has eight uploaded assets. Windows archive metadata reports
  26,851,859 bytes; its downloaded bytes remain to be verified in hosted CI.
- No `AGENTS.md`, nested `AGENTS.md`, `DESIGN_LOG.md`, or `AGENTS_LOG.md` existed
  at the baseline. Existing audits, plans, README, CHANGELOG, workflows and
  release-version helper are the applicable recorded conventions.
- Arena requires the fixed session branch
  `arena/ce4354e1-crispchess-extended`; no alternate session branch is created.
- No merge, tag, release, deployment, external upload, credential change, or
  modification of another repository is authorized.

## Evidence collected before a production fix

1. `BenchmarkService.createRunner` resolves `builtin:Frozenight` through
   `createEngineForId` and the native conditional factory. There is no Engine
   Lab substitute engine or preset-specific Frozenight constructor.
2. `BenchmarkRunner.run` calls the same `initialize()` as gameplay and Match,
   then checks for `ready`. Its generic `StateError` is a secondary symptom.
3. Native `initialize()` catches the original failure, logs it only in debug,
   sets `error`, and returns normally. A nonzero native init result likewise
   loses its code. These are confirmed diagnostic defects, not yet the owner's
   underlying runtime cause.
4. The release Windows job runs Flutter and CrispASR packaging, but does not
   build/download/copy `frozenight_ffi.dll`. The separate Frozenight Windows CI
   job only uploads a standalone DLL artifact. Linux has explicit native-library
   bundling; Windows does not. This makes missing packaging a testable hypothesis.
5. The Rust wrapper's `frozenight_init` currently always returns zero after
   constructing its engine; it does not implement the nonzero branch assumed
   by the Dart wrapper. Construction panic/abort remains a separate possibility.
6. Native state/result/board are process-global, despite Dart instances being
   independent. Disposing one can invalidate another. This requires a separate
   real-library concurrency/lifecycle experiment, not attribution of the
   owner's all-presets failure without evidence.

## Reproduction protocol

A read-only Windows hosted workflow downloads the actual official dev2 archive,
records SHA-256 and extracted file inventory, and runs the original loader and
application paths. It then builds the locked native source and adds only the
missing DLL to the same extracted layout as a **controlled experiment**. Direct
FFI, ordinary EngineService, all four Lab presets (shortened tournament size,
original preset budgets), and engine-vs-engine Match are recorded separately.
The experiment is not a new release and not Windows 10 verification.

Direct release/log downloads in the local sandbox redirect to unauthorized
hosts and fail. Hosted execution and its retained evidence are used instead;
compilation alone is not counted as runtime verification.

Results, root-cause decision, fixes, review rounds and acceptance gates will be
appended below as they are established. No readiness claim is made yet.

## 2026-11-01 — Readable baseline result and controlled repair

**Evidence:** validation run `41257634990`, exact harness head
`5ef8a7ace24e92a714109646405f0b6ec2de706f` (merge checkout
`e8d541bf15810eba340dcf97328c321ab98f1261`), application production source
`5d2e8aecb83bd8c8bb0f9131375947545ec8220d`. The workflow now pins this harness
for baseline experiments so later production changes cannot rewrite history.
The full hosted comment is retained in the PR; local evidence extract:
`/home/user/dev3-evidence/baseline-success.md`.

- Official dev2 ZIP SHA-256:
  `39c572edbbec9539a41428181e73755def991047dc3cd67bbd56c9778830ab0c`.
- The extracted archive has no `frozenight_ffi.dll` (workflow inventory assertion).
- Direct absolute-path `DynamicLibrary.open` fails with original `ArgumentError`,
  Windows loader code **126**, “The specified module could not be found.”
- The application factory path reaches `initializing → error` in 3.872 ms and
  returns normally with a null original exception. Lab turns that state into
  `Bad state: initialize returned with state error`. Thus the visible Lab text
  is a secondary diagnostic, not the root cause.
- Building the locked native source and adding only its DLL to the same extracted
  archive restores all nine legacy symbols, three init/search/dispose cycles,
  ordinary gameplay initialization, EngineService, all four Lab presets and
  Match. No engine substitution or Lab code change was involved in this control.
- Controlled DLL SHA-256 for this run:
  `86ae3870eeddd15170b1229a5fbe75e563adc01d3fa687f73863eea23074b700`.
  This is a CI build identity, not a claim of byte-for-byte release reproducibility.
- Each preset retained its own move budget but was bounded to two games, zero
  warm-ups and 40 plies. Both games reached 40 plies and were **adjudicated**,
  not decisive results or rating evidence. Match likewise reached 40 plies.
- Runner: Windows Server 2025 Datacenter, build 26100; Dart 3.12.2.
  **Actual Windows 10 remains NOT VERIFIED.** The owner's original machine/archive
  hash has not been supplied. This is strong artifact-level causal evidence, not
  a claim to have operated that machine.

### RCA and scope

The release job packaged Flutter's Windows output without building/installing
Frozenight's DLL. CI built a separate DLL artifact, which does not make the release
ZIP complete. Linux has a copy step; Windows did not. The native/web initialization
adapters then swallowed the original failure, and consumers had inconsistent
readiness checks. All presets share the same pre-game initialization, explaining
why none can start. Ordinary gameplay and Match use the same missing runtime and
are affected; the successful control demonstrates this rather than inferring it
from Lab alone. StockBear's separate Custom UCI process path is not a control for
FFI loading and was not modified.

The control rules out preset parameters, opening selection, rating fitting and
game-loop logic as the cause of this startup failure. It does not establish that
every possible error-126 installation has the same cause: a missing dependency
can produce the same loader code. The candidate therefore checks the archive's
DLL, architecture, exports and non-system import closure as well as real loading.

### Candidate changes under validation

- Release builds the locked DLL, bundles it, verifies the extracted ZIP and uploads
  a hash manifest. No tag/release/publication is performed by validation.
- Typed startup diagnostics retain original cause/stack, stage, platform, path,
  symbol, native/loader code and elapsed time. Consumers require `ready`.
- ABI 2 uses per-instance native handles; legacy global exports remain for the
  already-released dev2 executable. Dart serializes requests and queued disposal.
- Lab distinguishes stopped initialization from failure, records unavailable
  pairings, continues healthy pairings and marks unfinished schedules partial.
- Regression tests cover missing libraries, shared initialization, dispose-once,
  cancellation, healthy-pairing preservation and real native handle isolation.

These are candidate changes, not passed gates. Compilation, native tests,
extracted-candidate execution and independent review remain pending at this log entry.

## 2026-11-01 — Candidate validation and scoped audit disposition

### Extracted Windows candidate

Validation run **41263336646**, application head
**00d3524db07d09a1593d2816a358862a78e838d0**, completed **success** for both
baseline and candidate jobs. The candidate job built the Windows executable,
built and tested the locked Rust wrapper (2 native tests passed), verified the
build directory, created the ZIP, verified the ZIP and its extracted layout,
loaded the exact extracted DLL through ABI 2, and ran three create/search/destroy
cycles. The production factory/EngineService, all four presets and Match then
passed using that extracted DLL staged beside the Windows test hosts.

The four preset runs each completed two scheduled games. Quick/Standard/Accurate
reached 40/40 plies; Custom reached 40/30 with one adjudication and one black win.
Match completed one game with a white win at 39 plies. These are functional smoke
runs, not strength calibration. The runner was Windows Server 2025 build 26100,
not Windows 10. The artifact and manifests are retained in the CI artifact
`crispchess-dev3-windows-candidate` (30-day retention); no GitHub Release was made.

The earlier green candidate run **41262931779** at `89b8c93` independently passed
the same extracted-archive path. Its Flutter suite failure was a missing required
field in a new test fixture and a readiness-timeout test that still assumed the
old two-second default; neither was a native runtime failure. The fixture and
test were corrected at `00d3524`. The remaining gauntlet assertion incorrectly
expected no warm-up-cap warning; the final test disables warm-ups to isolate the
pairing-count behavior. Failed intermediate runs are retained in PR evidence.

### Reproducibility boundary

The build recipe is source-reproducible: exact Git source, Flutter 3.44.2,
locked Cargo dependencies (Frozenight `6b811c86`), pinned GitHub actions and a
hash-pinned PE verifier dependency. It is **not yet byte-for-byte reproducible**:
repeated MSVC builds produced different DLL/EXE hashes, and the hosted runner's
Rust/MSVC toolchain is recorded rather than fully pinned. Every delivered bundle
gets a SHA-256 manifest. Do not describe the candidate as deterministic binary
reproduction or substitute a hash from another run.

### Independent review cycle 1

CodeRabbit full review **5725910525** examined exact head
`d7dd854547ba0d89f02fe21566e0a8c4463f6852`, state **COMMENTED**, not approval.
Ten inline findings were verified and addressed: baseline cross-job copy,
unchecked verifier exit codes, test-host DLL staging, warm-up/cancel completion
counting, invalid promotion suffixes, search/analysis state reset, analysis queue
reservation, disposal during WASM load, Windows API-set imports, and CMake DLL
destination. The first review's API-set concern was confirmed by the actual
candidate import closure. A later exact-head review is required after final CI.

### Prior PR #5: all 19 Minor findings

| Comment | Disposition in dev3 |
|---|---|
| 4432113030 | Fixed: diagnostics download action pinned to full SHA. |
| 4432113035 | Deferred: web publication workflow pinning is outside this Windows runtime repair; no deployment behavior changed. |
| 4432113038 | Fixed: gauntlet validation receives actual pairing count; regression added. |
| 4432113041 | Fixed: exclusion summary uses the fit's own counts. |
| 4432113042 | Fixed: interrupted initialization is skipped, not engine failure; regression retained. |
| 4432113046 | Fixed: custom UCI version parsed from `id name` when present and refined before calibration; no version invented from a path. |
| 4432113049 | Fixed: non-finite rating uncertainty serializes as null; round-trip regression added. |
| 4432113059 | Fixed: coprime opening stride; seven-entry coverage regression added. |
| 4432113063 | Fixed: opening FEN/UCI legality and promotion syntax validated before scheduling. |
| 4432113066 | Fixed: Lynx availability gates Lab and Match choices. |
| 4432113069 | Fixed: configurable readiness timeout, 30-second default; strict readyok barrier retained. |
| 4432113075 | Fixed: privacy text describes local unfinished-game autosave. |
| 4432113082 | Fixed: report table uses 95% half-width. |
| 4432113083 | Fixed: method text follows adjudication-as-draw setting. |
| 4432113087 | Fixed: ordered complete anchors are searched for a participating engine. |
| 4432113092 | Fixed: invalid anchor rating and missing move budget rejected. |
| 4432113099 | Fixed: depth/node controls clear only the conflicting positive budget. |
| 4432113102 | Fixed: Match table uses 95% half-width. |
| 4432113108 | Deferred: iOS/App Store version workflow is outside this repair and was not executed or published. |

Additional scoped fixes: Frozenight native binary SHA-256 in Lab identity;
shared WASM lease/queue prevents cross-instance board/result corruption and
premature disposal; automatic game/duration caps enforced at config conversion;
service runner preparation reserves the active slot; startup Details are
selectable/copyable. Storage schema/checksum/backup/import-overwrite protections,
Bradley–Terry fitting, phantom draws, centering and calibration guards were
inspected and retained. No absolute Elo claim is made from smoke games.

### Remaining acceptance gates

- **NOT VERIFIED:** owner's actual Windows 10 machine and installed archive hash.
- **NOT VERIFIED:** byte-for-byte binary reproducibility across toolchain installs.
- **NOT VERIFIED:** long-duration rating calibration, memory-leak soak, UI manual
  interaction, App Store/TestFlight, production web deployment (intentionally not run).
- **PENDING:** final exact-head CI and CodeRabbit re-review after the last test/docs
  commit. A skipped CodeRabbit check is not a review; COMMENTED is not approval.
- **BLOCKED until owner approval:** merge, dev3 tag, GitHub Release, publication.

Recommendation: keep the PR draft and ask the owner to approve the candidate for
a Windows 10 verification pass, or request more work. Do not publish from CI smoke
evidence alone.

## 2026-11-01 — Release engineering, import-closure repair and final-head gates

Owner authorization now covers the full dev3 lifecycle: merge PR #10, tag the
actual merge commit `v2.3.2-dev3`, run the tag release workflow and publish the
GitHub prerelease with nine assets. External app-store submission, external
credential signing and unrelated deployments remain unauthorized. This entry
supersedes the earlier “blocked until owner approval” boundary; it does not
rewrite the historical candidate entries above.

### Windows import closure and runtime bundling

The first real extracted-archive PE gate failed with unbundled imports
`d3d9.dll`, `jvm.dll`, `mf.dll`, `mfplat.dll`, `mfreadwrite.dll`,
`opengl32.dll`, `uiautomationcore.dll` and `vcomp140.dll` (PR comment 6554063219).
The diagnosis was:

- `d3d9/opengl32/mf/mfplat/mfreadwrite/uiautomationcore` are Windows system
  components and are now explicitly allowlisted by the verifier.
- `jvm.dll` came from the transitive `jni` Windows FFI helper, not from
  Frozenight. The Windows install filters that helper out of
  `PLUGIN_BUNDLED_LIBRARIES`; `jvm.dll` is not allowlisted.
- `vcomp140.dll` is the Visual C++ OpenMP runtime and is not a system DLL.
  `tool/bundle_msvc_windows.ps1` copies the CRT and OpenMP redist DLLs
  app-locally from the installed VS redist directory and fails closed if any
  source or target is missing. The verifier requires the three CRT images plus
  `vcomp140.dll` and checks the import closure of every delivered PE image.

`include(InstallRequiredSystemLibraries)` was tried and reverted: under the
hosted VS generator it made `cmake_install.cmake` exit 1 (MSB3073, PR comment
6553964946). The vswhere redist copy is the retained repair.

Proof on head `0b3af59d68c71a69cd81aec375367d6ebbb1f687`:

- Release run **41278815647**, Windows job: SUCCESS through MSVC CRT+OpenMP
  bundle, CrispASR bundle, hash-pinned PE verification, ZIP packaging,
  extracted-archive verification, runtime probe, executable launch and evidence
  upload.
- Frozenight release validation run **41278815687**: candidate archive, clean
  rebuild 1, clean rebuild 2, comparison, evidence, all six Frozenight platform
  jobs and engine-gate SUCCESS.

Proof on head `660c165e6ecbedac1e97dd79560b851519bf0117`:

- Release run **41279201169**: Android, iOS, Linux, Linux+Frozenight, macOS,
  Windows, Web, Frozenight native libraries and **Verify all release assets**
  SUCCESS. The tag-only GitHub Release job was correctly skipped on the PR.
- Frozenight release validation run **41279201205**: baseline, candidate, both
  clean rebuilds, comparison and evidence SUCCESS; candidate-sha.txt records
  `660c165e6ecbedac1e97dd79560b851519bf0117`.
- Engine Lab run **41279201315** SUCCESS; Lab diagnostics comment 6554234358:
  analyze exit 0, test exit 0, **784 passed / 26 skipped**.
- Python release-tooling suite: **32/32** locally and in CI.

### CI integration device and display repair

CI run 41278815661 failed because `flutter test integration_test/...` saw both
Linux desktop and Chrome and required an explicit device (PR comment 6554197250).
Head `660c165` added Linux desktop dependencies and `-d linux`. CI run
41279201194 then built the Linux app but failed with “Error waiting for a debug
connection: The log reader stopped unexpectedly, or never started” (PR comment
6554288632): the hosted Linux runner has no interactive display. The final CI
change runs the Linux integration tests under `xvfb-run` with a fixed screen and
keeps the tee/artifact/PR-comment failure path. The app smoke test also uses a
bounded pump instead of `pumpAndSettle`, because the app can host periodic
timers. These are CI environment repairs, not a weakening of the integration
assertions.

### Review-thread reconciliation

All 19 PR #10 review threads were individually verified, replied to and resolved
on GitHub. Cycle 1 review 5725910525 (`d7dd854`) and cycle 2 review 5726314400
(`97ffe04`) were both COMMENTED, not approval. The nine cycle-2 findings and the
manifest-as-ninth-asset requirement are implemented: concurrent automatic
preparation skip, compatible anchor selection, interruption-reason preservation,
single-number UCI versions, iOS availability consistency, Darwin numeric bundle
version, VC runtime import closure, and x64 PE validation of the executable,
Flutter DLL and Frozenight DLL. A final exact-head CodeRabbit full review is
requested after the last CI/docs commit; rate-limited, skipped, neutral or
other-commit reviews are not counted.

### Remaining limitations

- Windows 10 is still **NOT VERIFIED**. CI is Windows Server 2025 build 26100.
  App-local CRT/OpenMP bundling and loaded-module assertions are proven, but a
  clean owner Windows 10 installation is not.
- Byte-for-byte reproducibility is **NOT GUARANTEED**. Clean rebuilds are
  compared and hashed; hosted MSVC/Rust toolchain and PE metadata can vary.
- Smoke games and short soaks are not long-duration rating calibration. No
  absolute Elo is claimed without a compatible declared anchor.
- The iOS IPA is unsigned; no App Store/TestFlight submission or external
  signing is performed.

### Headless integration follow-up

The first xvfb run (CI 41280180792, PR comment 6554377531) proved the Linux app
could start, but the smoke assertion looked for a literal `CrispChess` Text
widget. `CrispChess` is the MaterialApp/window title, not a visible Text widget;
the visible root is `ChessGameScreen`. The smoke test now asserts the real game
screen and no framework exception. The two integration files are also run in
separate xvfb/flutter-test invocations because the second file failed to obtain a
debug connection after the first file's failed assertion. The EngineService and
20-move self-play assertions are unchanged.

### Least-privilege CI/release posting and YAML pin gate

CodeRabbit review 5726775509 on `e755d7f` raised three still-valid security
findings and one integration assertion already fixed at `c830edb`. The workflow
level `pull-requests: write` permission was removed from `ci.yml` and
`release.yml`. Build/test jobs now only upload failure logs; isolated
`post-integration-failure` and `post-failure-logs` jobs download the artifacts and
hold job-level PR write permission without executing repository build code.
`tool/dev/check_action_pins.py` now parses workflow YAML with hash-pinned PyYAML
and fails closed on invalid YAML or any mutable `uses` ref, including quoted
keys/values. Four regression tests cover pinned, quoted mutable, and invalid YAML
cases; the Python tooling suite is now 36 tests.

### Follow-up review dispositions on the final candidate

The next CodeRabbit pass raised five additional items; all were verified and
addressed: evidence comments are capped below GitHub's comment limit; iOS
upload/TestFlight metadata uses the same numeric Darwin `read_version()` as the
build; `EngineSlot` reuses a cached `thinking` engine but still rejects
`initializing`; the native probe's `missing` mode only succeeds when the target
file is absent and loading failed; and the Windows JNI exclusion removes the
exact `$<TARGET_FILE:jni>` generator expression instead of scanning ancestor
paths. Regression tests cover the cached thinking/initializing slot states.

## 2026-11-01 — Final exact-head gates on 760db1f

Final candidate head: **760db1f892ae06bab5f82c48a5aa6abbdd6fdac1**.

- CI run **41292823104**: SUCCESS. Analyze & Test passed Python tooling
  (**36 tests**), action-pin YAML gate, Flutter analyze, unit/widget tests,
  Linux desktop integration under xvfb, all six Frozenight platform builds and
  the engine-gate. The isolated PR-log posting job was correctly skipped on green.
- Release run **41292823103**: SUCCESS. Android, iOS, Linux, Linux+Frozenight,
  macOS, Windows, Web, Frozenight native libraries and **Verify all release
  assets** passed. The tag-only GitHub Release job was correctly skipped on PR.
- Frozenight release validation run **41292823072**: SUCCESS. Baseline,
  candidate, clean rebuild 1, clean rebuild 2, comparison and evidence passed.
- Engine Lab run **41292823089**: SUCCESS. Engine latency **41292823065**:
  SUCCESS. Secret scans **41292823117** and **41292818538**: SUCCESS.
- Lab diagnostics run **41292823070**, comment 6556080731: analyze exit 0,
  test exit 0, **786 passed / 26 skipped**.

Review follow-through: cycle 1 5725910525 (`d7dd854`, 10 findings), cycle 2
5726314400 (`97ffe04`, 9 findings), cycle 3 5726775509 (`e755d7f`, 4 findings),
cycle 4 5727330079 (`c830edb`, 5 findings). All were verified and addressed;
all review threads are resolved. The final exact-head full review is requested
after the CodeRabbit fair-usage cooldown; rate-limited attempts are not counted.

The remaining limitations are unchanged: Windows 10 is not verified; byte-for-byte
reproducibility is not guaranteed; smoke/short soak is not long-duration rating
calibration; the iOS IPA is unsigned and no store submission is performed.

### Final full-review follow-up (cycle 5)

CodeRabbit full review 5727549754 on `d0edc6f` posted four Minor findings; all
were verified and addressed: the Linux Frozenight release job now selects the
centralized `RUST_VERSION`; the Windows runtime probe asserts `vcomp140.dll`
loads from the extracted archive; stored automatic benchmark budgets are clamped
to the effective 24-game/10-minute caps on load; and the WASM soak validates the
first UCI token while retaining the compatibility fallback. The local 3-cycle
WASM soak passed after the change.
