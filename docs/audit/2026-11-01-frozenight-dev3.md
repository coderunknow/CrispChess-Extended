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
