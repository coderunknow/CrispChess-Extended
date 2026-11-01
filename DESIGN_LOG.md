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
