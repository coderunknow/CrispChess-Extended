import 'dart:async';

/// Serialises searches on a single UCI engine connection.
///
/// UCI has exactly one search in flight at a time: after `go` the engine owns
/// the connection until it prints `bestmove`. The app breaks that rule in
/// normal play — it starts a background (ponder) analysis after every engine
/// move, then sends a new `position` + `go` as soon as the player moves. Two
/// things went wrong:
///
///  * the `bestmove` belonging to the *aborted* ponder search arrived first and
///    was handed back as the answer to the new request, so the engine "played"
///    a move computed for the previous position — usually illegal, which left
///    the UI stuck on "thinking" forever;
///  * the new `position` was parsed while the old search was still running, so
///    the engine could search the wrong tree.
///
/// Both get worse the longer the game runs, because a fixed-depth ponder search
/// takes longer every move — which is what read as "the engine dies after a few
/// turns".
///
/// This mixin makes the rule explicit: a new search always drains the previous
/// one first, and a `bestmove` only ever resolves the search that asked for it.
mixin UciSearchCoordinator {
  /// Write one UCI command to the engine. Implemented by each transport
  /// (process stdin, web worker `postMessage`, platform channel, ...).
  void sendUci(String command);

  /// Completes when the search in flight ends. Null when the engine is idle.
  Completer<void>? _running;

  /// Set when a caller is waiting for this search's `bestmove`.
  Completer<String?>? _awaited;

  /// `bestmove` lines the engine still owes for searches that were given up on.
  ///
  /// A UCI engine answers every `go` with exactly one `bestmove`, including the
  /// ones stopped mid-search. Giving up before that answer arrives does not make
  /// the answer go away: it turns up later, while a *different* search is
  /// running. Counting it is what keeps it from being read as that search's
  /// answer — the engine "playing" a move computed for the previous position,
  /// which is the defect this mixin exists to prevent.
  int _owedBestMoves = 0;

  /// Completes when [_owedBestMoves] reaches zero.
  Completer<void>? _owed;

  /// Whether the position the search in flight was started for has White to
  /// move.
  ///
  /// The conversion from the engine's side-to-move scores to White's has to
  /// belong to the search the numbers came from, not to the engine. A caller
  /// that set it before asking for a search had already changed it by the time
  /// the search being stopped printed its last `info` lines — measured on
  /// Stockfish 11: 16 `info` lines arrive between `stop` and `bestmove` — so
  /// those were converted with the *next* position's colour and the eval bar
  /// briefly showed the opposite of the engine's opinion.
  bool _searchWhiteToMove = true;

  /// Whose turn it is in the position the current search was started for.
  bool get searchWhiteToMove => _searchWhiteToMove;

  /// True while a `go` is outstanding.
  bool get isSearching => _running != null;

  /// True while the engine still owes a `bestmove` for a search that was given
  /// up on. Output arriving in this state may belong to an older position.
  bool get hasOwedBestMoves => _owedBestMoves > 0;

  /// Stop the search in flight (if any) and wait for its `bestmove`.
  ///
  /// Returns immediately when the engine is idle *and* owes nothing. If the
  /// engine does not answer within [timeout] the search is dropped — but it is
  /// still counted as owed, so its late `bestmove` is discarded instead of being
  /// handed to the next search.
  Future<void> quiesceSearch(
      {Duration timeout = const Duration(seconds: 5)}) async {
    final running = _running;
    if (running != null) {
      sendUci('stop');
      await running.future.timeout(timeout, onTimeout: () {
        finishSearch(null);
        _owedBestMoves++;
      });
    }
    await _awaitOwedBestMoves(timeout);
  }

  /// Wait (bounded) for the `bestmove` lines an abandoned search still owes.
  ///
  /// When the engine does answer — the normal case; a stopped Stockfish prints
  /// its `bestmove` immediately — the debt is paid here and the late answer is
  /// swallowed by [finishSearch] instead of being read as the next search's.
  ///
  /// When it does not answer within [timeout] the debt is dropped: an engine
  /// that ignores `stop` for that long is wedged, and keeping the count would
  /// both stall every later search and swallow the first real answer, leaving
  /// the game with no move at all. Dropping it re-exposes the older race on that
  /// connection only, which is the lesser failure.
  Future<void> _awaitOwedBestMoves(Duration timeout) async {
    if (_owedBestMoves == 0) return;
    _owed ??= Completer<void>();
    await _owed!.future.timeout(timeout, onTimeout: () {
      _owedBestMoves = 0;
      _owed = null;
    });
  }

  /// Drain any previous search, then send [positionCommand] and [goCommand].
  ///
  /// With [awaitMove] the returned future carries that search's `bestmove` (or
  /// null if it was aborted or produced none). Without it the future completes
  /// as soon as the commands are sent — the caller only wants the `info` lines.
  Future<String?> startSearch(
    String positionCommand,
    String goCommand, {
    required bool awaitMove,
    bool? whiteToMove,
  }) async {
    await quiesceSearch();
    // Set only after the previous search has drained: the `info` lines it emits
    // on its way out belong to its position and must keep its colour.
    if (whiteToMove != null) _searchWhiteToMove = whiteToMove;
    _running = Completer<void>();
    final waiter = awaitMove ? Completer<String?>() : null;
    _awaited = waiter;
    sendUci(positionCommand);
    sendUci(goCommand);
    return waiter?.future;
  }

  /// Feed every `bestmove` line here, with the move or null when the engine
  /// reported `(none)`.
  ///
  /// A `bestmove` that arrives with nothing outstanding is a leftover from an
  /// already-abandoned search and is discarded — never adopted as the answer to
  /// a later request.
  void finishSearch(String? move) {
    if (_owedBestMoves > 0) {
      // The answer to a search that was already given up on. Swallow it: the
      // search waiting now asked about a different position.
      _owedBestMoves--;
      if (_owedBestMoves == 0) {
        final owed = _owed;
        _owed = null;
        if (owed != null && !owed.isCompleted) owed.complete();
      }
      return;
    }
    final waiter = _awaited;
    final running = _running;
    _awaited = null;
    _running = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(move);
    if (running != null && !running.isCompleted) running.complete();
  }

  /// Release the search in flight and forget everything the engine owes.
  ///
  /// For teardown only: the process/worker is going away, so no further
  /// `bestmove` will arrive. Keeping the debt across a restart would make the
  /// first answer of the *new* connection be swallowed as a stale one.
  void resetSearches() {
    _owedBestMoves = 0;
    final owed = _owed;
    _owed = null;
    if (owed != null && !owed.isCompleted) owed.complete();
    final waiter = _awaited;
    final running = _running;
    _awaited = null;
    _running = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(null);
    if (running != null && !running.isCompleted) running.complete();
  }

  /// Abort the search in flight without waiting for the engine to answer.
  ///
  /// Used when a search overruns its cap. The engine will still print that
  /// search's `bestmove`, so it is recorded as owed (see [_owedBestMoves])
  /// rather than forgotten.
  void abandonSearch() {
    if (_running == null && _awaited == null) return;
    sendUci('stop');
    finishSearch(null);
    _owedBestMoves++;
  }
}
