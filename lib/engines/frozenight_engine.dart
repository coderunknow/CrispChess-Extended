import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'engine_initialization.dart';
import 'search_pacing.dart';
import 'uci_position.dart';

typedef _Handle = Pointer<NativeType>;
typedef _Create = Pointer<NativeType> Function(Uint32);
typedef _SetPosition = Int32 Function(_Handle, Pointer<Utf8>, Pointer<Utf8>);
typedef _Search = Int32 Function(_Handle, Int32, Uint64);
typedef _GetMove = Pointer<Utf8> Function(_Handle);
typedef _GetInt = Int64 Function(_Handle);
typedef _GetScore = Int32 Function(_Handle);
typedef _Destroy = Void Function(_Handle);

/// Chess engine using Frozenight (Rust, MIT/Apache-2.0, ~2960 ELO).
///
/// Requires the native `frozenight_ffi` shared library to be available
/// at runtime. See `native/frozenight/` for the Rust FFI wrapper.
class FrozenightEngine implements ChessEngine {
  FrozenightEngine({String? libraryPath}) : _libraryPath = libraryPath;
  final String? _libraryPath;
  DynamicLibrary? _library;
  Pointer<NativeType>? _handle;
  Pointer<NativeType> Function(int)? _create;
  int Function(Pointer<NativeType>, Pointer<Utf8>, Pointer<Utf8>)? _setPosition;
  int Function(Pointer<NativeType>, int, int)? _searchBounded;
  int Function(Pointer<NativeType>)? _getNodes;
  Pointer<Utf8> Function(Pointer<NativeType>)? _getBestMove;
  int Function(Pointer<NativeType>)? _getScore;
  int Function(Pointer<NativeType>)? _getDepth;
  void Function(Pointer<NativeType>)? _disposeNative;
  Future<void>? _initializing;
  EngineInitializationException? _initializationError;
  String? _resolvedLibraryPath;
  String? get resolvedLibraryPath => _resolvedLibraryPath;
  EngineInitializationException? get initializationError => _initializationError;

  /// Nodes per millisecond, measured as play goes on. Only the initial value
  /// is a guess, and it is deliberately low: guessing high on the first search
  /// of a session is the one case that cannot be corrected afterwards.
  double _nodesPerMs = 200;

  bool _disposed = false;
  bool _available = false;
  bool _stopped = false;

  /// Deep enough that the time budget is always what ends the search, without
  /// being unbounded: a depth this engine cannot reach inside any budget the
  /// app hands it, so the iterative deepening loop still terminates on its own
  /// in a position where the search returns instantly.
  static const int _fullStrengthDepth = 64;

  /// One search at a time. Each FFI handle owns its position, so
  /// two overlapping searches would clobber each other's board between
  /// iterations (the deepening loop yields to the event loop, so another call
  /// really can land in the middle of one).
  Future<void> _searchLock = Future<void>.value();
  Future<void> _analysisLock = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() body) {
    final result = _searchLock.then((_) => body());
    _searchLock = result.then((_) {}, onError: (_) {});
    return result;
  }

  final ValueNotifier<EngineState> _stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  String get name => 'Frozenight';
  @override
  String get version => '7.0.0';
  @override
  String get license => 'MIT/Apache-2.0';
  @override
  int get estimatedElo => 2960;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // The FFI search is one blocking call on the calling isolate — the UI
  // isolate here — so a background ponder search would freeze the app.
  @override
  bool get canPonder => false;

  /// Check if the native library is available on this platform.
  static bool get isAvailable {
    if (kIsWeb) return false;
    try {
      final lib = _openDefaultLibrary();
      lib.lookup<Void>('frozenight_abi_version');
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize() {
    if (_disposed) return Future.error(StateError('Frozenight is disposed'));
    if (state == EngineState.ready) return Future<void>.value();
    final failure = _initializationError;
    if (failure != null) return Future.error(failure);
    return _initializing ??= _initializeNow().whenComplete(() => _initializing = null);
  }

  Future<void> _initializeNow() async {
    final watch = Stopwatch()..start();
    var stage = 'load-library';
    String? symbol;
    _stateNotifier.value = EngineState.initializing;
    try {
      _resolvedLibraryPath = _libraryPath ?? (Platform.isIOS ? null : _defaultLibraryPath());
      _library = _libraryPath != null
          ? DynamicLibrary.open(_libraryPath)
          : _openDefaultLibrary();
      final lib = _library!;
      stage = 'check-abi';
      symbol = 'frozenight_abi_version';
      final abi = lib.lookupFunction<Uint32 Function(), int Function()>(symbol)();
      if (abi != 2) throw UnsupportedError('Expected Frozenight ABI 2, found $abi');
      stage = 'resolve-symbols';
      symbol = 'frozenight_create';
      _create = lib.lookupFunction<_Create, Pointer<NativeType> Function(int)>(symbol);
      symbol = 'frozenight_set_position_v2';
      _setPosition = lib.lookupFunction<_SetPosition, int Function(Pointer<NativeType>, Pointer<Utf8>, Pointer<Utf8>)>(symbol);
      symbol = 'frozenight_search_bounded_v2';
      _searchBounded = lib.lookupFunction<_Search, int Function(Pointer<NativeType>, int, int)>(symbol);
      symbol = 'frozenight_get_nodes_v2';
      _getNodes = lib.lookupFunction<_GetInt, int Function(Pointer<NativeType>)>(symbol);
      symbol = 'frozenight_get_best_move_v2';
      _getBestMove = lib.lookupFunction<_GetMove, Pointer<Utf8> Function(Pointer<NativeType>)>(symbol);
      symbol = 'frozenight_get_score_v2';
      _getScore = lib.lookupFunction<_GetScore, int Function(Pointer<NativeType>)>(symbol);
      symbol = 'frozenight_get_depth_v2';
      _getDepth = lib.lookupFunction<_GetScore, int Function(Pointer<NativeType>)>(symbol);
      symbol = 'frozenight_destroy';
      _disposeNative = lib.lookupFunction<_Destroy, void Function(Pointer<NativeType>)>(symbol);
      stage = 'native-create';
      _handle = _create!(32);
      if (_handle == null || _handle!.address == 0) {
        throw StateError('frozenight_create returned a null handle');
      }
      stage = 'verify-ready';
      _available = true;
      _initializationError = null;
      _stateNotifier.value = EngineState.ready;
    } catch (error, stack) {
      _releaseHandle();
      _available = false;
      final failure = EngineInitializationException(
        engine: name, version: version, stage: stage,
        platform: Platform.operatingSystem, cause: error, causeStack: stack,
        libraryPath: _resolvedLibraryPath, symbol: symbol,
        nativeCode: windowsLoaderCode(error), elapsedMicros: watch.elapsedMicroseconds,
      );
      _initializationError = failure;
      _stateNotifier.value = EngineState.error;
      throw failure;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_disposed || !_available) throw StateError('Engine not ready');
    if (_disposed || state == EngineState.disposed) throw StateError('Engine disposed');
    // The depth ceiling is the difficulty knob: a weaker setting is a
    // shallower search. At full strength it should not be a knob at all — the
    // clock should be what stops the search — and 14 was low enough to stop it
    // first. Measured over a round robin at 300ms per move, 830 of 1554
    // Frozenight moves finished depth 14 and returned, several of them in
    // three milliseconds, handing back nearly the whole budget unused.
    final maxDepth = depth ??
        (skillLevel != null && skillLevel >= 20
            ? _fullStrengthDepth
            : (2 + (skillLevel ?? 10) * 12 ~/ 20).clamp(2, 14));
    final budget = moveTime ??
        (depth != null ? kFixedDepthTimeCap : thinkTimeForLevel(skillLevel ?? 10));

    // Deepen one step at a time inside a time budget rather than jumping
    // straight to the target depth. A single `search(14)` is one uninterruptible
    // FFI call whose cost explodes once the position opens up — fine on move 2,
    // tens of seconds of frozen UI by the middlegame. Each iteration is a small
    // fraction of the next, so stopping before starting one keeps the overshoot
    // bounded.
    return _serialized(() async {
      if (_disposed || !_available) throw StateError('Engine disposed');
      _stateNotifier.value = EngineState.thinking;
      try {
      _applyPosition(positionCommand);
      final sw = Stopwatch()..start();
      String? best;
      var reached = 0;
      for (var d = 1; d <= maxDepth; d++) {
        if (_disposed) break;
        final remaining = budget - sw.elapsed;
        if (d > 1) {
          // With a node bound there is no need to predict whether a depth
          // fits: it is cut short if it does not. Without one, fall back to
          // the prediction, which is all the older library can support.
          if (_searchBounded == null) {
            if (!hasTimeForNextDepth(sw.elapsed, budget)) break;
          } else if (!worthStartingDepth(remaining, budget)) {
            break;
          }
          // Yield so the UI can paint between iterations.
          await Future<void>.delayed(Duration.zero);
        }

        final before = sw.elapsed;
        final int status;
        if (_searchBounded != null) {
          status = _searchBounded!(_handle!, d, nodeAllowance(remaining, _nodesPerMs));
        } else {
          throw StateError("Frozenight ABI 2 requires bounded search");
        }
        if (status != 0) {
          throw StateError('Frozenight native search failed at depth $d (code $status)');
        }

        if (_getNodes != null) {
          final nodes = _getNodes!(_handle!);
          final spent = (sw.elapsed - before).inMilliseconds;
          _nodesPerMs = updatedRate(_nodesPerMs, nodes, spent);
        }

        final ptr = _getBestMove!(_handle!);
        if (ptr.address != 0) {
          best = ptr.toDartString();
          reached = d;
        }
      }

      if (!_disposed) _stateNotifier.value = EngineState.ready;

      // Nothing came back because the budget ran out before even depth one
      // finished, which is a timeout and not a broken engine. The type is what
      // the service classifies on: as a StateError this arrived at the player
      // as "Move request failed: Bad state: No move found".
      if (best == null) {
        throw TimeoutException(
            'No move within ${budget.inMilliseconds}ms', budget);
      }
      debugPrint('[Frozenight] $best depth=$reached/$maxDepth '
          '${sw.elapsedMilliseconds}ms (budget ${budget.inMilliseconds}ms)');
      return best;
      } finally {
        if (!_disposed) _stateNotifier.value = EngineState.ready;
      }
    });
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {
    if (_disposed || !_available) return;
    // Reserve the queue synchronously before the first await. Otherwise a
    // bestMove queued while analysis waits can be lost from the disposal chain.
    final previousSearch = _searchLock;
    final previousAnalysis = _analysisLock;
    final gate = Completer<void>();
    _analysisLock = gate.future;
    _searchLock = gate.future;
    await previousSearch;
    await previousAnalysis;
    if (_disposed || !_available) { gate.complete(); return; }
    try {
    _stateNotifier.value = EngineState.thinking;
    _stopped = false;
    _applyPosition(positionCommand);
    // frozenight's own search is negamax, so `SearchInfo.eval` — the value
    // `frozenight_get_score` returns — is positive when the *side to move* is
    // better (see `search_moves`, which maximises over negated child scores,
    // and the mated-position arm returning `-MATE`). EvalInfo is from White's.
    // A local, not a field: `analyze` is a generator, so this value belongs
    // to this stream and no other search can change it underneath it.
    final whiteToMove = positionCommandIsWhiteToMove(positionCommand);

    // Bounded for the same reason as [bestMove]: a deep iteration is one
    // blocking call that `stop` cannot interrupt.
    final budget = infinite ? const Duration(seconds: 10) : kFixedDepthTimeCap;
    final sw = Stopwatch()..start();

    for (int d = 1; d <= (depth ?? 20); d++) {
      if (_disposed || _stopped) break;
      if (d > 1 && !hasTimeForNextDepth(sw.elapsed, budget)) break;
      if (d > 1) await Future<void>.delayed(Duration.zero);
      if (_searchBounded!(_handle!, d, 0) != 0) break;

      final ptr = _getBestMove!(_handle!);
      final sideToMove = _getScore!(_handle!) / 100.0;
      yield EvalInfo(
        score: whiteToMove ? sideToMove : -sideToMove,
        depth: _getDepth!(_handle!),
        bestMove: ptr.address != 0 ? ptr.toDartString() : null,
      );
    }
    if (!_disposed) _stateNotifier.value = EngineState.ready;
    } finally {
      if (!_disposed) _stateNotifier.value = EngineState.ready;
      gate.complete();
    }
  }

  @override
  void stop() {
    // The FFI search itself can't be signalled; this stops the deepening loop
    // from starting another iteration.
    _stopped = true;
  }

  @override
  void setOption(String name, String value) {
    // Frozenight FFI engine doesn't support runtime option changes
    // Options would need to be implemented in the native library
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopped = true;
    _available = false;
    // FFI calls are synchronous. Queue cleanup after the last queued request;
    // never free a handle while a request can still use it.
    final cleanup = _searchLock.then((_) => _analysisLock)
        .then((_) => _releaseHandle(), onError: (_) => _releaseHandle());
    _searchLock = cleanup;
    _stateNotifier.value = EngineState.disposed;
  }

  void _releaseHandle() {
    final handle = _handle;
    _handle = null;
    if (handle != null && handle.address != 0) _disposeNative?.call(handle);
  }

  void _applyPosition(String positionCommand) {
    final parts = positionCommand.split(' ');
    String fen = 'startpos';
    String moves = '';

    if (parts.length >= 2 && parts[1] == 'fen') {
      final mi = parts.indexOf('moves');
      fen = mi > 0 ? parts.sublist(2, mi).join(' ') : parts.sublist(2).join(' ');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    } else {
      final mi = parts.indexOf('moves');
      if (mi > 0) moves = parts.sublist(mi + 1).join(' ');
    }

    final fenPtr = fen.toNativeUtf8();
    final movesPtr = moves.isEmpty ? nullptr.cast<Utf8>() : moves.toNativeUtf8();
    final rc = _setPosition!(_handle!, fenPtr, movesPtr);
    malloc.free(fenPtr);
    if (moves.isNotEmpty) malloc.free(movesPtr);
    // Ignoring this return code is how a broken position went unnoticed: the
    // library kept the position it already had and answered with a move for the
    // wrong side, which the board then rejected as illegal.
    if (rc != 0) {
      throw StateError('Frozenight rejected the position (code $rc): $fen'
          '${moves.isEmpty ? '' : ' moves $moves'}');
    }
  }

  /// iOS links native engines into the process; opening the executable path
  /// is not the same lookup. Keep availability and initialization on one path.
  static DynamicLibrary _openDefaultLibrary() => Platform.isIOS
      ? DynamicLibrary.process()
      : DynamicLibrary.open(_defaultLibraryPath());

  static String _defaultLibraryPath() {
    if (Platform.isWindows) {
      // Resolve beside the executable, not the process working directory.
      return File(Platform.resolvedExecutable).parent.uri
          .resolve('frozenight_ffi.dll').toFilePath();
    }
    if (Platform.isAndroid || Platform.isLinux) return 'libfrozenight_ffi.so';
    if (Platform.isMacOS) return 'libfrozenight_ffi.dylib';
    throw UnsupportedError('Unsupported platform');
  }
}
