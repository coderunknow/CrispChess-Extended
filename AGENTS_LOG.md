# Engineering agent log

## 2026-11-01 — reconnaissance and reproduction harness

Fetched and verified main/tag SHA 5d2e8aecb83bd8c8bb0f9131375947545ec8220d,
PR #5 history and its exact-head 19-Minor review, release assets, instructions
(absent), audits, plans and release tooling. Inspected native/global FFI state,
factory/registry, gameplay, Match and Lab call paths before a production edit.
Added only an opt-in real-runtime probe, application-path reproduction and a
read-only Windows artifact workflow. No publication or other repository changed.

## 2026-11-01 — baseline established; candidate implementation

Readable Windows CI evidence: run 41257634990, harness 5ef8a7a, dev2 production
5d2e8ae. Original ZIP lacks Frozenight DLL; loader 126; controlled DLL restores
FFI/gameplay/four bounded presets/Match. Windows 10 is still unverified. Added
packaging gates, typed startup errors, ABI-2 handles, lifecycle serialization and
truthful Lab partial/cancellation semantics. Tests/reviews are pending, not passed.

## 2026-11-01 — candidate validation and review follow-through

Verified official dev2 RCA again with pinned baseline harness. Candidate runs
41262931779 and 41263336646 passed extracted Windows ZIP/ABI-2/gameplay/four
presets/Match on Windows Server 2025. Fixed verifier PE parsing/import closure,
test-host staging, review findings and scoped prior Lab defects. Recorded all 19
prior Minor dispositions. No Windows 10 claim, publication, tag, merge or release.
Final exact-head CI/re-review and owner decision remain the boundary.

## 2026-11-01 — release engineering and final-head CI repair

Completed the Windows import-closure repair: system DLL allowlist, JNI helper
exclusion, app-local VS CRT+OpenMP bundling, schema-2 PE verifier and fail-closed
release asset gate. Release 41279201169 and validation 41279201205 passed on
660c165, including all eight platform builds and release-asset verification.
Resolved all 19 PR review threads individually. CI integration first failed on
ambiguous device selection, then on a headless Linux display; the final change
selects `-d linux` and runs under xvfb-run. Owner authorization now covers
merge/tag/prerelease; Windows 10 and byte reproducibility remain unverified.

## 2026-11-02 — v2.3.2-dev4: Stockfish 16 initialization and Engine Preflight

Owner report "Stockfish 16: failed — Bad state: initialize returned with state
error". Reproduced on the dev3 baseline vs the candidate on Linux and Windows
CI (RCA run 41400637184): the desktop adapter swallowed "no Stockfish found"
and returned in the error state. Moved every engine onto one initialization
coordinator with structured, redacted failures; added Engine Preflight with
identity-bound gating; fixed an unhandled broken-pipe on engines that exit at
once; guarded ios-release against dev tags. Genuine Stockfish `sf_16` built
from pinned source runs in CI (11/11 on Linux x86-64, job 125139989647). Other
platforms are build-only for this change. No SDK in the sandbox: CI was the
oracle. Details: docs/audit/2026-11-02-engine-initialization-dev4.md.

## 2026-11-03 — dev5 baseline, scope and implementation plan

Read the design/agent logs, Engine Lab plan, prior audits, README/changelog,
benchmark config/plan/runner/run/store, rating fit/Elo/calibration, Preflight,
registry/profile storage, model/native download paths, Lab/Manager/Settings UI,
localizations, platform adapters and CI/release workflows. Verified main SHA
`09ce48228da30454362e184220c066916169bd92` and PR #11 facts against GitHub.
No AGENTS.md was present. No production edit preceded this reconnaissance.

Plan: (1) extend configuration with per-run precision and resource objectives;
(2) add candidate assessment, connected pilot and adaptive information/cost
allocation using the existing runner; (3) add global opening-cluster bootstrap,
joint covariance and simultaneous pairwise intervals; (4) unify verified
 downloads and platform-aware storage; (5) integrate setup/preview/live/report
UI and EN/DE strings; (6) add deterministic regressions, independent statistical
simulation and real-engine CI gates; (7) audit diff, run exact-head CI and
CodeRabbit, then open/update the PR. Authorization ends at an open PR: no merge,
tag, release or deployment. Local Flutter/Dart is absent; GitHub Actions is the
compiler/runtime oracle, with local Python/reference and syntax checks used
where possible. Unexecuted platform behavior will be reported as unverified.
