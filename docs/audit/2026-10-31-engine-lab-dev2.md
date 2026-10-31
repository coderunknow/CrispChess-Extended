# Dev2 Engine Lab implementation audit

**Date:** 2026-10-31 UTC
**Repository:** `coderunknow/ScrispChess-Extended`
**Starting `main` SHA:** `20bc1b8e670f8d75152a465ec3da094b2fcf2997`
**Starting tag:** `v2.3.2-dev1` points to that exact SHA; GitHub lists it as a prerelease.
**Working branch:** `arena/9e925a62-scrispchess-extended` (the Arena session branch; no branch switch).

This is a new audit record. The existing `docs/audit/2026-10-31-custom-uci-and-engine-audit.md` is historical and was not rewritten.

## Repository state verified before implementation

- GitHub default branch is `main`; API and local `origin/main` both identified the same starting SHA above.
- Existing tags/releases: `v2.3.2-dev1` at the starting SHA. The local repo also had that tag.
- Pull requests #1 and #2 are merged. The repository issue API responds that issues are disabled, so no open-issue list is available.
- GitHub lists 12 registered workflows and reports each as `active` at reconnaissance time. Recent exact runs included: main CI run `41168922313` succeeded; main Deploy Web run `41168922301` failed; dev1 Release run `41168930421` succeeded; dev1 iOS Release run `41168930415` failed. These are historical runs on the dev1 commit, not evidence for dev2.
- Recent commit ancestry showed the dev1 release merge and multiple engine lifecycle fixes. Relevant source files, `PLAN.md`, `README.md`, `CHANGELOG.md`, `NOTICE.md`, `THIRD_PARTY_LICENSES.md`, `docs/audit/`, `docs/plans/`, and workflow files were inspected before changes. No `AGENTS.md`, `AGENTS_LOG.md`, or `DESIGN_LOG.md` was present in the checkout.
- Issues are disabled at repository level; do not infer that there are no project defects from that endpoint.

## Implemented scope

- Added a local Engine Lab screen and navigation entry, engine multi-selection, workload estimation, 100/300/1,000 ms presets, custom move-time/game/ply caps, progress and cancellation.
- Engine match results now carry stable engine IDs separate from display names, per-move latency samples, explicit completion/adjudication/forfeit/abort/cancel states, failure reasons and PGN result tokens. Invalid moves and engine failures are not silently converted to draws or strength points.
- Round-robin uses stable IDs, balanced white/black assignments for even pairings, reports selected-engine construction failure rather than silently dropping it, and emits only one aggregate tournament-completion event.
- Added versioned benchmark-report JSON, native flushed snapshots with a backup and recovery path, browser-local persistence, validated additive imports, and JSON/CSV/PGN clipboard export. Existing reports are not overwritten on import. Exported option descriptions redact values with path/credential-like option names, and CSV string cells are protected against spreadsheet-formula injection.
- Relative Bradley–Terry ratings preserve the 1500-centred convention while fitting disconnected comparison components independently. Confidence intervals use the observed-game Fisher information with the centered-rating covariance; stabilizing priors are not counted as evidence. Calibrated Elo remains unavailable.
- Added median, P95, P99 and maximum measured move-response latency. Search nodes, NPS, CPU and memory are not exposed by the current `ChessEngine.bestMove` API and are not reported as if measured.
- Added opt-in Quick benchmarks after custom UCI addition and after a changed custom binary is detected when the Engine Lab is opened. Custom executable SHA-256 is streamed and cached by size/mtime. Built-in version-change detection is not present.
- The global application skill parameter no longer sends `setoption name Skill Level` to custom UCI engines; saved profile options remain authoritative.
- Corrected release Web fallback logic to accept `main.dart.wasm` plus `flutter_bootstrap.js` as a complete WASM build and to rebuild JS only if the WASM command fails or expected outputs are incomplete. The macOS release-version parser accepts Flutter prerelease versions while keeping Apple bundle short versions numeric.
- The manual Engine Strength workflow now writes a source-SHA/parameter metadata JSON, publishes the complete log as an artifact, and explicitly marks that its existing harness does not record engine binary fingerprints.

## Known limitations and risk

- Engine Lab UI strings are not fully localized yet.
- Custom configuration currently implements move time, games per pairing, total-game cap and ply limit. Warmups, repeated blocks, duration/uncertainty stopping, node limits, UCI option sweeps/editing, custom opening suites, gauntlet mode, A/B config sweeps, adaptive stopping, charted history and a full diagnostic matrix are not delivered. Each custom profile's already-saved UCI option overrides are used by the engine.
- Benchmark games use standard-start positions, deterministic round-robin pair order and engine-specific runtime labels. Custom UCI author and detected name are preserved, but its version is `unknown` because the current handshake does not expose a separate version field. No hardware identifier is collected; performance results from different devices/backends must not be pooled.
- Binary-change detection uses size and millisecond mtime as a cheap cache key; a same-size replacement preserving that timestamp may evade automatic detection. A manual benchmark forces a fresh digest. It is a file fingerprint, not a signed engine identity.
- Custom UCI executables are unavailable in Web and may not be executable on iOS. Engine Lab reports platform/backend conditions; it does not claim every registered engine can run on every platform.
- Web history uses browser storage and can hit browser quota. Native JSON history is not a substitute for SQLite at very large game/report volumes.
- No Flutter/Dart executable is installed in this sandbox. Consequently Flutter package resolution, Dart type analysis/tests, actual engine execution, screenshots, and Android/iOS/Windows/Linux/macOS/Web builds are blocked here. These gates must be resolved against the pushed PR SHA by GitHub Actions or a Flutter-equipped environment.
- No genuine app benchmark has yet been run in this environment. Existing `tool/perf/tournament.dart` output is historical repository documentation, not dev2 benchmark evidence.

## Checks performed in the sandbox

- `python3 -m unittest discover -s tools/tests -v`: 19/19 passed after the prerelease-version parser update.
- `tool/dev/parse_check.py`: 247 Dart files parsed successfully with tree-sitter Dart. This is syntax-only and is not Dart type checking.
- PyYAML parsed all 12 `.github/workflows/*.yml` files.
- `git diff --check`: passed.
- `flutter pub get`, `flutter analyze`, `flutter test`, platform builds, UCI real-engine runs and a genuine multi-engine benchmark: not run because the Flutter/Dart SDK is absent.

## Statistical and calibration decision

The repository's original 1500 anchor was a relative scale convention, not an absolute engine rating. Dev2 retains that convention, refuses to bridge disconnected engine graphs, and displays an observed-data uncertainty interval. No calibrated anchor is selected: the local environment and match budget do not establish a public reference cohort matched by engine version, hardware, backend and test methodology. Calibrated Elo therefore remains explicitly unavailable rather than being inferred from an advertised rating or a fixed Stockfish number.

## Post-implementation adversarial review

The final pass specifically rechecked identity mapping, duplicate display names, draw/forfeit classification, canceled searches, tournament terminal events, the centered Fisher covariance, import collision behavior, atomic snapshot recovery, profile option persistence, hash-cache invalidation, result PGN tokens and WASM fallback conditions. Regression tests were added for the code paths that can be tested in Dart CI. Because the Dart suite cannot execute in this sandbox, those tests remain authored but unverified until CI runs them on the PR head. No claim of a completed native-engine or cross-platform audit is made.
