# Full code audit — three-check counters, move-analyzer capture, test-FEN fix

Audited: 2026-11-21, 10:26 → 12:00 UTC+7 (noon deadline, per request).
Scope: every Dart file under `lib/` (227 files across `chess`, `bench`,
`engines`, `services`, `widgets`, `diagnostics`, `screens`, `vision`,
`voice`, `l10n` generated) plus `lib/main.dart`, with fixes committed as
they were found.

## Bugs found and fixed (commit `a9da911`)

1. **Three-check counters lost on tree navigation** (`lib/chess/chess_game.dart`
   + `lib/chess/game_tree.dart`). The check counters (`whiteChecks`,
   `blackChecks`) were kept only on the live `Chess` object and were not part
   of the game tree. Undo, redo, `goForward`, `goToNode` and `enterVariation`
   reload the board from a node FEN but left the counters at whatever the
   last played move left them at: a check counted before an undo survived and
   could falsely trigger a three-check win. Fix: the counters now live on
   `GameTreeNode`; `_syncCheckCounters()` restores them from the node after
   every navigation path. The dead `GameTree.reset(String startFen)` (whose
   body was empty after earlier work) was removed.

2. **Capture/material annotation read off the post-move board**
   (`lib/chess/move_analyzer.dart` + `lib/chess/chess_game.dart`). Tactic
   analysis asked "did this move capture something, and what was the material
   difference?" using the board *after* the move, so every move looked like
   it had already captured (a move *to* an occupied square shows the capture
   only after it is applied). Fix: `analyzeMove` takes `preMoveFen`;
   `_isCapture` and `_getMaterialDifference` are parameterised by the board
   they inspect; `chess_game.dart` passes `preMoveFen = _game.fen` at the
   analysis call sites (which run after `_game.move`). `MoveAnnotation`
   gained a `copyWith` for the completed-annotation path.

## Test fixes (commit `da06eef`)

3. **Illegal FEN in the three-check regression tests**
   (`test/chess_game_variants_test.dart`). Both the undo and the redo
   regression tests loaded `7k/8/8/8/8/8/1Q6/4K3 w - - 0 1`, in which the
   queen on b2 *already* checks the king on h8 along the b2–h8 diagonal, so
   `package:chess` rejects the FEN and the tests failed with
   `King of opponent player is in check.` The position is now
   `7k/8/8/8/8/8/8/1Q2K3 w - - 0 1` (queen on b1, which checks nothing;
   Qb1–b8 then gives check along the eighth rank). Analyze & Test passes
   again on `da06eef` (the previous run's 2 failures are gone).

4. **Analyzer warnings** surfaced by the Analyze job: a duplicate
   `dart:async` import and an unused `redaction.dart` import in
   `lib/screens/diagnostics_screen.dart`, and an unused `_uncertainty`
   helper in `lib/screens/benchmark_report_screen.dart`. Removed.

## Areas audited, no bugs found

- `lib/chess/*` (23 files), `lib/bench/*` (30 files), `lib/engines/*`
  (52 files incl. all web/FFI variants, download/archive/storage helpers,
  RANSAC locator, UCI lifecycle and search-coordinator mixins)
- `lib/services/*` (18 files), `lib/widgets/*` (10 files)
- `lib/diagnostics/*` (15 files)
- `lib/screens/*` (25 files)
- `lib/vision/*` — diagram scanner and photo pipeline (board locator,
  Hough/canny/warp image ops, homography maths, crops, classifiers)
- `lib/voice/*` — spoken-move grammar, ranking, native Whisper worker
- `lib/l10n/generated/*`, `lib/main.dart`

## CI note

On `da06eef` the `Analyze & Test`, Linux/macOS/Android/Web builds, Frozenight
(Android arm64) and the secret scan all pass. The two failing check-runs are
the iOS builds (`Build iOS` in release.yml, `iOS` in ci.yml). Evidence they
are environmental, not code regressions:

- the same commit's `Frozenight (iOS)` check-run **passed**;
- all changes are pure Dart, which compiles identically on every platform,
  and Linux/macOS/Android/Web builds succeeded;
- the failures carry the GitHub "macOS arm64 runner capacity" notice and no
  compiler diagnostic in the check annotations.
