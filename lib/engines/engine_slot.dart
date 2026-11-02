/// Holding an engine that might die.
///
/// An engine kept in a field and reused is the normal arrangement — starting
/// one costs a process, a download or a model load — but it has a failure
/// mode that has now appeared twice here. A process that dies leaves its
/// engine in [EngineState.error], which is neither `idle` nor `disposed`, so
/// the usual `??=` keeps the dead instance and the usual "initialise if idle"
/// guard never fires again. Every later request fails, identically, forever.
///
/// The hint engine had exactly that: one crash and every hint after it
/// reported "Hint failed", advice that could not have helped.
library;

import 'chess_engine.dart';
import 'engine_initialization.dart';

/// Whether an engine in this state can still be asked for anything.
///
/// `disposed` is included because a slot outliving its engine is the same
/// problem wearing a different state.
bool engineNeedsRebuild(EngineState state) =>
    state == EngineState.error || state == EngineState.disposed;

/// An engine that is built on demand and replaced when it becomes unusable.
class EngineSlot {
  EngineSlot(this._build);

  final ChessEngine Function() _build;
  ChessEngine? _current;

  /// The start this slot itself began, so concurrent [get]s can join it.
  Future<void>? _starting;
  ChessEngine? _startingEngine;

  /// How many times the engine has been replaced, for callers that want to
  /// stop after a while rather than restart something permanently broken.
  int rebuilds = 0;

  /// The engine held right now, without building or replacing anything.
  ChessEngine? get current => _current;

  /// A usable engine, initialised and ready to be asked.
  Future<ChessEngine> get() async {
    final cached = _current;
    if (cached != null && engineNeedsRebuild(cached.state)) {
      _disposeQuietly(cached);
      _current = null;
      rebuilds++;
    }

    final engine = _current ??= _build();
    final starting = _starting;
    if (starting != null && identical(_startingEngine, engine)) {
      // A second request while this slot is starting the engine waits for
      // that start instead of being rejected as "initializing".
      await starting;
    } else if (engine.state == EngineState.idle) {
      final start = engine.initialize();
      _starting = start;
      _startingEngine = engine;
      try {
        await start;
      } finally {
        if (identical(_starting, start)) {
          _starting = null;
          _startingEngine = null;
        }
      }
    }
    // A cached thinking engine may still be finishing a prior search. It is
    // already initialized, and the engine serializes the next request. Do not
    // skip the check for initializing/error/disposed: those are not usable.
    if (engine.state != EngineState.thinking) {
      requireEngineReady(engine, platform: 'native');
    }
    return engine;
  }

  void dispose() {
    final cached = _current;
    if (cached != null) _disposeQuietly(cached);
    _current = null;
  }

  /// Disposing something already gone is not an error worth propagating: the
  /// point is only to stop holding it.
  void _disposeQuietly(ChessEngine engine) {
    try {
      engine.dispose();
    } catch (_) {}
  }
}
