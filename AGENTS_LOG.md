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
