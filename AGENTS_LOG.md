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
