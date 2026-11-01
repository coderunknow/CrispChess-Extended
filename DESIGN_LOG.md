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
