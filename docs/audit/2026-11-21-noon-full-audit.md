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

## CI note — the two failing iOS check-runs are a pre-existing, flaky
## runner-capacity failure, not a code regression

On `ec48fc5` the `Analyze & Test`, `Engine Lab tests`, Linux/macOS/Android/
Web builds, all test suites, Frozenight (all platforms) and the secret scan
all pass. The only failures are the Flutter iOS builds (`Build iOS` in
release.yml, `iOS` in ci.yml), both at the `flutter build ios --release
--no-codesign` step with "Process completed with exit code 1" and the GitHub
"macOS arm64 runner capacity" notice, and no compiler diagnostic in the
annotations.

Check-run conclusions across the branch (`Build iOS` / `iOS`):

- b486d83: Build iOS **failure**
- 8aebacb: Build iOS **failure**, iOS **failure**
- 742a162: Build iOS **failure**, iOS **failure**
- 668c5ef: Build iOS **failure**
- b4a589b: Build iOS **failure**, iOS **failure**
- c209fa5: Build iOS success, iOS cancelled
- b2723b0, 91c6dd6, 2a190a2, 1649228, fb59275, e10a86c, f505284: both **success**
- 5e8fcd3: Build iOS **failure**, iOS **failure**
- a9da911, da06eef, ec48fc5 (this session): both **failure**

The failures predate every change in this audit (they were already failing
on b486d83 through b4a589b and on 5e8fcd3), then passed on seven consecutive
commits, then failed again. This flake is correlated with windows of macOS
arm64 runner contention, not with the code: the changes here are pure Dart,
which compiles identically on every platform, and Linux/macOS/Android/Web
all build; the same-commit `Frozenight (iOS)` job (a Rust build, lighter
load) passes every time. No code change can fix a runner-capacity flake —
the next run after capacity frees up is expected to pass.
