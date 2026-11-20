/// Throttles live-board rendering without discarding benchmark events.
///
/// The benchmark runner always records every move and every game; the live
/// board is a *view*. This throttle decides when the view is allowed to rebuild
/// so a run with hundreds of moves does not rebuild the whole screen (and
/// reload the board) on every single ply — the cause of the "Not Responding"
/// behaviour under a long intelligent benchmark.
///
/// The three modes mirror the user's setting:
///
///  * [LiveBoardMode.off] never renders; moves are still accepted and kept as
///    the latest position.
///  * [LiveBoardMode.on] renders at the configured rate.
///  * [LiveBoardMode.auto] renders at the configured rate normally and slows
///    down under resource pressure, restoring the normal rate when it subsides.
///
/// Throttling a render never drops the move: [onMove] always stores the newest
/// position, and [pendingMoves] reports how many are waiting for the next
/// allowed render.
library;

import '../diagnostics/hardware_protection.dart'
    show LiveBoardMode, ResourcePressureLevel;

/// Decides when the live board may rebuild.
class LiveBoardThrottle {
  final LiveBoardMode mode;
  final int refreshPerSecond;

  /// The current pressure, used by `auto` mode. Null means "no pressure
  /// information", which `auto` treats as normal.
  ResourcePressureLevel? pressureLevel;

  final DateTime Function() _clock;

  DateTime? _lastRenderAt;
  String? _lastFen;
  String? _lastSan;
  int _pending = 0;

  LiveBoardThrottle({
    required this.mode,
    required this.refreshPerSecond,
    this.pressureLevel,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The minimum interval between renders, in milliseconds. A zero refresh
  /// rate means "never".
  int effectiveIntervalMs() {
    if (mode == LiveBoardMode.off || refreshPerSecond <= 0) return 1 << 30;
    final base = (1000 / refreshPerSecond).round();
    if (mode == LiveBoardMode.on) return base.clamp(1, 1 << 30);
    // Auto: under warning or worse, double the interval (at most 4 s) so the
    // board still updates but far less often.
    if ((pressureLevel?.severity ?? 0) >= ResourcePressureLevel.warning.severity) {
      return (base * 2).clamp(500, 4000);
    }
    return base.clamp(1, 1 << 30);
  }

  /// Records a move. Returns true when the board should rebuild now.
  bool onMove({required String fen, required String san}) {
    _lastFen = fen;
    _lastSan = san;
    _pending++;
    if (mode == LiveBoardMode.off) return false;
    final now = _clock();
    final last = _lastRenderAt;
    if (last == null || now.difference(last).inMilliseconds >= effectiveIntervalMs()) {
      _lastRenderAt = now;
      _pending = 0;
      return true;
    }
    return false;
  }

  /// Forces a render on the next call regardless of the interval (used when a
  /// game finishes or pressure changes, so the board is not left stale).
  void poke() {
    _lastRenderAt = null;
  }

  bool get hasPending => _pending > 0;
  int get pendingMoves => _pending;
  String? get lastFen => _lastFen;
  String? get lastSan => _lastSan;

  /// True when the board should be shown at all in the current mode.
  bool get isEnabled => mode != LiveBoardMode.off;

  void reset() {
    _lastRenderAt = null;
    _lastFen = null;
    _lastSan = null;
    _pending = 0;
  }
}
