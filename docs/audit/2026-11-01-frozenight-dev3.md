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
