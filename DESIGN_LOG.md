# Design log

## 2026-11-01 — Frozenight dev3 investigation

The baseline has no design log. Start an append-only record here rather than
rewriting the existing PR #5 audit. See
`docs/audit/2026-11-01-frozenight-dev3.md` for the preserved owner context,
verified baseline, hypotheses and artifact-reproduction protocol. Production
changes wait for the original-archive experiment. The session branch is fixed
by Arena; publishing remains behind owner approval.

## dev3 — evidence-first Frozenight repair

The official dev2 archive experiment established a missing Windows runtime before
production edits. The repair is at the release boundary, not a Lab fallback.
Startup is a fail-closed contract with typed causal diagnostics. ABI 2 isolates
native engine instances while retaining legacy exports for dev2 compatibility.
Lab cancellation and partial coverage remain distinct from failure and success.
See docs/audit/2026-11-01-frozenight-dev3.md for evidence and unverified gates.

## dev3 — audit follow-through

The extracted Windows candidate passed real ABI-2 loading, gameplay, four bounded
Lab presets and Match on Windows Server 2025. The first genuine CodeRabbit full
review was COMMENTED with ten findings; all were addressed. The 19 prior Minor
findings were individually dispositioned in the audit, with unrelated publication
workflow changes explicitly deferred. Native runtime hashes now identify Lab
measurements; the singleton WASM backend is leased and serialized across Dart
instances. Binary reproducibility and actual Windows 10 remain unverified gates.

## dev3 — release boundary and headless integration

The release boundary is fail-closed: eight platform jobs feed a structural
asset verifier, and only the tag job may publish. Windows delivery is defined by
the extracted archive, not the build tree: every required PE image must be x64,
ABI-2 exports must exist, non-system imports must close over bundled or documented
system DLLs, and the app-local CRT/OpenMP runtime must load from the delivered
layout. The JNI Windows helper is excluded because it introduced an unnecessary
jvm.dll import. CI integration tests are real Linux desktop tests under xvfb;
headless runners are an environment constraint, not a reason to skip the UI and
EngineService lifecycle assertions.

## dev4 — one initialization contract, Preflight before measurement

`initialize()` either returns ready or throws `EngineInitializationException`
with a failure kind from a fixed taxonomy; a normal return while not ready is a
contract violation reported as `readinessFailed`, never a bare StateError. One
coordinator owns concurrency, retry and dispose-during-start for every engine,
so adapters only describe their stages. GPL Stockfish stays outside the MIT
binary: desktop resolves a user-installed runtime and names it when missing.
Engine Preflight is a separate step whose results are bound to identity,
platform, configuration and app build; stale or unreviewed results never admit
an engine, and excluded engines are listed, not dropped. A gauntlet's
reference is a precondition, not something to substitute. Late `info` lines of
a stopped search remain delivered with their own colour; consumers that need
one position's eval drain the previous search first.

## 2026-11-03 — dev5 reconnaissance and architecture decision

Verified remote `main` and local baseline at
`09ce48228da30454362e184220c066916169bd92`; PR #11 is merged and its final
reviewed head was `428309e2504e073da6d3f3369093e4f534ba39fc`. Baseline version
is `2.3.2-dev4+20`; dev5 uses build 21. Existing main CI run 41596124729,
Engine Lab run 41596124318 and secret scan 41596124146 passed on the exact
baseline SHA. The existing Deploy Web run 41596124411 failed at its Vercel
deployment step; deployment is outside this directive and will not be run.

Reuse decision: keep `BenchmarkRunner`, `BenchmarkPlan`, `EnginePreflight`,
`PreflightGate`, `BenchmarkStore`, `fitRatings`, `EloFit`, engine registry and
custom profiles. Add a pure-Dart adaptive scheduler above the existing runner,
cluster-bootstrap statistics above the existing Bradley–Terry fitter, and a
shared download/storage layer used by existing adapters. Static round-robin and
gauntlet remain available. Intelligent runs admit opponents automatically,
record every actual participant, and allocate two-game colour-reversed opening
units by expected joint-variance reduction per measured cost.

Statistical decision: opening identity is the global resampling cluster, so a
position shared by several matchups is sampled once with all of its games and
colour reversals. Percentile intervals and direct bootstrap differences are
primary; Fisher covariance remains an independent diagnostic. Simultaneous
pairwise coverage uses the bootstrap distribution of the maximum absolute
contrast error, explicitly labelled approximate. Failed/singular replicates,
too few clusters and Monte Carlo endpoint uncertainty block precision success.
Historical measurements may inform costs/opponent choice only under an exact
measurement-cohort key; they are never silently added as games.

Platform decision: desktop uses a selectable global root; Android keeps native
executables in app-private executable storage and allows a supported model-data
location; iOS uses sandboxed model/JavaScript assets and never executes
downloaded native code; web uses browser-managed cache storage, not a pretended
POSIX directory. See `docs/audit/2026-11-03-dev5-reconnaissance.md` for the
verification matrix and confirmed source-level defects.

## dev5 verification round: what the compiler and the tests changed

The Lab diagnostics workflow turned out to be the only readable CI channel in
this environment (Actions logs redirect to a blob host that is unreachable
here), so each round was driven by its PR comment rather than by guessing. Four
rounds, in order of what they exposed:

1. `flutter analyze` reported 35 issues including 9 errors. Every one was real:
   a getter two files assumed existed, an import for a top-level function that
   is not a method, a `const` suite that reads another suite's field (illegal in
   a constant expression), a nonexistent `sha256OfFile`, a duplicate
   `redactPath` with two different meanings, three files importing `dart:io`
   from a build target that cannot link it, a parameter that never existed, and
   a cancel callback whose type did not match the transport.
2. The compiler then reported what the analyzer's `show` clauses had hidden:
   `Abi` without `dart:ffi` (which broke the *loading* of 31 test files, not the
   tests themselves) and a non-exhaustive switch over the new
   `TournamentFormat.intelligent`.
3. Behaviour: 10 failures. Six were defects in the tests I wrote — a
   colour-reversed pair that sampled the winner from a per-colour probability and
   so cancelled the strength difference it was meant to measure, a 50% draw rate
   applied on top of that probability, a covariance sign asserted backwards, a
   cluster count that assumed the old per-pairing key, and a refusal asserted by
   the wrong field. Four were defects in the code: the draw prior was validated
   as if it were evidence, so a separated replicate counted as a clean sample;
   `fitElo` rated participants that had played nothing; a stored run could not be
   `jsonEncode`d at all once any uncertainty was unbounded; and the pilot priced
   its whole cluster target before admitting a single opponent.
4. Two more: a pilot that demanded 40 games before selecting anyone (a two-game
   budget selected nobody), and `90%` printed as `90.0%`.

Decisions worth keeping:

* The prior keeps the displayed estimate *and* its interval finite — that is a
  documented contract and an existing test. What it must not do is hide that the
  record was perfect, so `separated` travels with the fit, and the bootstrap
  validates replicates with **no** prior. A resample the prior rescued is not
  evidence.
* The pilot is the minimum connected schedule (one colour-reversed unit per
  spanning-tree edge). Reaching `minClusters` belongs to the adaptive phase,
  which can stop when the budget runs out instead of failing before the first
  game. The target is still computed and reported, clamped to the number of
  distinct openings the suite holds, because a repeat is not a new cluster.
* The cluster key is the line of chess, not the (suite, opening) pair: two
  pairings that play the same moves are one cluster of evidence.
* A stored run is JSON, and JSON has no Infinity. Every non-finite value is
  written as `null` with a marker on the map that held it, and the readers
  restore it as an infinity rather than failing a cast.
* `engine_storage`, `download_manager` and the Lynx install path reach the
  filesystem only through conditional-import seams (`storage_fs.dart`,
  `download_io.dart`). `Build Web (WASM)` now compiles and links, which is the
  evidence that the seam is right.

Verification at the final SHA `6147fea`: all seven workflows green — CI (every
job, including Linux/macOS/Windows/iOS/Android and the WASM web build), Engine
Lab, Lab diagnostics (`flutter analyze` exit 0, `flutter test` exit 0), Release,
Stockfish RCA, Frozenight release validation, Engine latency, Secret scan.
`tool/bench/verify_cluster_bootstrap.py` passes all 7 statistical checks and
`verify_rating_math.py --trials 50` passes 25/25.
