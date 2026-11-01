/// Generic UCI engine that loads any engine binary from disk.
///
/// Speaks the UCI protocol over stdin/stdout. Available on desktop
/// and mobile platforms (not web — no process spawning).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chess_engine.dart';
import 'generic_uci_engine_stub.dart';
import 'search_telemetry.dart';
import 'uci_capabilities.dart';
import 'uci_option.dart';
import 'uci_process_lifecycle.dart';
import 'uci_position.dart';
import 'uci_search_coordinator.dart';

export 'generic_uci_engine_stub.dart' show EngineProfile;
export 'chess_engine.dart' show EngineProcessDiedException;

class GenericUciEngine
    with UciSearchCoordinator, UciProcessLifecycle
    implements ChessEngine, SearchTelemetry, UciOptionAware, SearchDrainableEngine, NodeLimitedEngine {
  final EngineProfile profile;

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  StreamSubscription? _stdoutSub;

  final _evalController = StreamController<EvalInfo>.broadcast();

  /// Engine identity parsed from the UCI handshake.
  String _detectedName = '';
  String _detectedAuthor = '';
  String _detectedVersion = '';

  /// Author, as reported by the engine's `id author` line.
  String get engineAuthor => _detectedAuthor;

  /// The name the engine calls itself, which may differ from the name the
  /// user gave this profile. Kept so two profiles — or two different binaries
  /// that share a name — can be told apart in logs and in the UI.
  String get engineIdentifier => _detectedName;

  /// UCI options advertised by the engine.
  final List<UciOption> options = [];

  /// Counters from the last search, for engines that report them.
  ///
  /// UCI makes `nodes`, `nps`, `time`, `hashfull` and `tbhits` optional on an
  /// `info` line, so each is recorded only when the engine actually printed it
  /// — the Engine Lab shows "unavailable" rather than a zero for the rest.
  SearchStatistics _lastStats = SearchStatistics.none;

  @override
  SearchStatistics get lastSearchStatistics => _lastStats;

  @override
  void resetSearchStatistics() => _lastStats = SearchStatistics.none;

  /// Whether the engine advertises a UCI option called [name], matched
  /// case-insensitively the way engines match it.
  ///
  /// Most engines match option names case-insensitively and ignore an unknown
  /// one silently, which is why a benchmark has to ask before claiming it
  /// applied "Threads = 4".
  @override
  bool advertisesOption(String name) {
    final wanted = name.toLowerCase();
    return options.any((o) => o.name.toLowerCase() == wanted);
  }

  @override
  List<String> get advertisedOptionNames =>
      [for (final option in options) option.name];

  @override
  void applyOption(String name, String value) => setOption(name, value);

  /// Whether the engine answered `uciok` in the last handshake.
  bool _handshakeComplete = false;

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r' multipv (\d+)');
  static final _nodesRegex = RegExp(r' nodes (\d+)');
  static final _npsRegex = RegExp(r' nps (\d+)');
  static final _timeRegex = RegExp(r' time (\d+)');
  static final _hashFullRegex = RegExp(r' hashfull (\d+)');
  static final _tbHitsRegex = RegExp(r' tbhits (\d+)');

  /// How long the engine has to answer `uci`.
  ///
  /// Configurable so tests can exercise the timeout without waiting ten
  /// seconds; the default is what the app uses.
  final Duration handshakeTimeout;

  /// Options may rebuild tables; allow a longer bounded wait than the handshake.
  final Duration readinessTimeout;

  GenericUciEngine(
    this.profile, {
    this.handshakeTimeout = const Duration(seconds: 10),
    this.readinessTimeout = const Duration(seconds: 30),
  });

  @override
  String get name => profile.displayName;
  @override
  String get version => _detectedVersion;
  @override
  String get license => 'Unknown';
  @override
  int get estimatedElo => 0;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // A real UCI process searches on its own thread and honours `stop`, so
  // background analysis is safe here.
  @override
  bool get canPonder => true;

  /// Starts the engine and completes the UCI handshake.
  ///
  /// Throws when the engine cannot be started or does not complete the
  /// handshake. The previous implementation caught the failure, set
  /// [EngineState.error] and returned normally, so every caller — including the
  /// Engine Manager — saw a successful `await initialize()` and saved a profile
  /// for an engine that could never run. The state is still set to error before
  /// the exception leaves, so state listeners keep working.
  /// The handshake currently in flight.
  ///
  /// Two callers can start the engine at once — the Engine Manager's "test"
  /// button and the screen that switches to it, a rebuild racing a retry — and
  /// two `Process.start` calls left one process with no reader, alive until the
  /// app exited. Repeated calls therefore join the attempt already running.
  Future<void>? _pendingInit;

  bool get _isDisposed => _stateNotifier.value == EngineState.disposed;

  /// Sets the state unless the engine has been disposed, so work that finishes
  /// after [dispose] cannot bring a dead engine back to `ready` — which would
  /// also mean adding to the eval stream after it was closed.
  void _setState(EngineState state) {
    if (_isDisposed) return;
    _stateNotifier.value = state;
  }

  @override
  Future<void> initialize() {
    if (_isDisposed) {
      return Future.error(StateError('Engine disposed'));
    }
    if (_stateNotifier.value == EngineState.ready) return Future.value();
    final pending = _pendingInit;
    if (pending != null) return pending;
    final run = _initializeOnce();
    _pendingInit = run;
    return run.whenComplete(() {
      if (identical(_pendingInit, run)) _pendingInit = null;
    });
  }

  Future<void> _initializeOnce() async {
    _stateNotifier.value = EngineState.initializing;
    await _teardownProcess(announce: false);

    try {
      final file = File(profile.path);
      if (!await file.exists()) {
        throw FileSystemException('Engine binary not found', profile.path);
      }

      _process = await Process.start(profile.path, []);
      watchProcess(_process!);

      final ready = Completer<void>();
      _handshakeComplete = false;
      options.clear();
      _detectedName = '';
      _detectedAuthor = '';
      _detectedVersion = '';

      _stdoutSub = _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        _handleLine(line, handshake: !ready.isCompleted);
        if (line.trim() == 'uciok') {
          _handshakeComplete = true;
          if (!ready.isCompleted) ready.complete();
        }
      }, onDone: () {
        // stdout closing is the first sign of death, usually ahead of the
        // exit code; don't leave a caller waiting for the difference.
        if (!ready.isCompleted) ready.complete();
        releaseOnLoss();
      }, onError: (Object e) {
        debugPrint('[UCI] ${profile.path} stdout error: $e');
        releaseOnLoss();
      });

      // Start UCI handshake
      _send('uci');

      try {
        await ready.future.timeout(handshakeTimeout);
      } on TimeoutException {
        // Reporting a half-initialised engine as ready is how an engine that
        // never spoke UCI ended up "added" and then failing on every move.
        throw TimeoutException(
          'No UCI handshake response within '
          '${handshakeTimeout.inMilliseconds}ms',
          handshakeTimeout,
        );
      }

      if (!_handshakeComplete) {
        // stdout ended before `uciok`: the process died during the handshake.
        // Report that rather than falling through to a false "ready".
        final death = await processDeathReport();
        await _teardownProcess();
        throw death;
      }

      // Apply saved option overrides
      for (final entry in profile.optionOverrides.entries) {
        _send('setoption name ${entry.key} value ${entry.value}');
        // Also update the in-memory option
        for (final opt in options) {
          if (opt.name == entry.key) opt.value = entry.value;
        }
      }

      // Remember what the engine called itself, so the profile keeps a
      // truthful identity even after the user renames it.
      profile.detectedName = _detectedName.isEmpty ? null : _detectedName;
      profile.detectedAuthor =
          _detectedAuthor.isEmpty ? null : _detectedAuthor;
      profile.optionCount = options.length;

      // UCI's own synchronisation point: after `isready` the engine answers
      // `readyok` once it is idle again, which is what says the option values
      // above have been applied. Marking the engine ready as soon as the
      // command was written let the first `position`/`go` overtake an engine
      // still working through them.
      //
      await synchronizeOptions();
      if (_isDisposed) {
        // Disposed while the handshake was running: the caller is gone and the
        // process has to go with it.
        await _teardownProcess(announce: false);
        throw StateError('Engine disposed during initialization');
      }
      // It can also die during the wait above — `onProcessLost` releases the
      // waiter, so without this the dead engine would be marked ready and the
      // caller told it started. That is the "a failing engine is saved as a
      // working one" defect this class exists to prevent.
      if (processGone) throw await processDeathReport();
      _stateNotifier.value = EngineState.ready;
      debugPrint('[UCI] $name ready (${options.length} options)');
    } catch (e) {
      debugPrint('[UCI] Init failed: $e');
      await _teardownProcess();
      _setState(EngineState.error);
      rethrow;
    }
  }

  @override
  String get processLabel => name;

  @override
  void onProcessLost() {
    if (!disposingProcess) _stateNotifier.value = EngineState.error;
    resetSearches();
    final ready = _readyOk;
    _readyOk = null;
    if (ready != null && !ready.isCompleted) ready.complete();
  }

  @override
  void sendUci(String command) {
    if (processGone) return;
    try {
      _process?.stdin.writeln(command);
    } on SocketException catch (e) {
      // Writing to a pipe whose far end is gone. The exit watcher reports it.
      debugPrint('[UCI] ${profile.path} write failed: $e');
    }
  }

  void _send(String command) => sendUci(command);

  @override
  Future<void> synchronizeOptions() async {
    if (_isDisposed || _process == null || processGone) {
      throw StateError('Engine unavailable during readiness synchronization');
    }
    if (_readyOk != null) {
      throw StateError('Concurrent readiness synchronization');
    }
    final ack = Completer<void>();
    _readyOk = ack;
    try {
      _send('isready');
      await ack.future.timeout(readinessTimeout);
      if (_isDisposed || processGone) {
        throw StateError('Engine lost during readiness synchronization');
      }
    } catch (_) {
      // A late response must never acknowledge a subsequent operation.
      dispose();
      rethrow;
    } finally {
      if (identical(_readyOk, ack)) _readyOk = null;
    }
  }

  @override
  Future<String> bestMoveWithNodes(String positionCommand, int nodes) {
    if (nodes < 1) throw ArgumentError.value(nodes, 'nodes');
    return _bestMove(positionCommand, nodes: nodes);
  }

  /// Completed by the engine's `readyok`.
  Completer<void>? _readyOk;

  /// Test-only access to the real stdout line parser.
  @visibleForTesting
  void debugHandleLine(String line, {bool handshake = false}) =>
      _handleLine(line, handshake: handshake);

  void _handleLine(String line, {bool handshake = false}) {
    final t = line.trim();

    // `readyok` answers `isready`: the engine has finished whatever it was
    // doing, including applying the `setoption`s before it. Checked before the
    // handshake branch because it can arrive either side of `uciok`.
    if (t == 'readyok') {
      final ready = _readyOk;
      _readyOk = null;
      if (ready != null && !ready.isCompleted) ready.complete();
      return;
    }

    // During handshake, parse engine identity and options
    if (handshake) {
      if (t.startsWith('id name ')) {
        _detectedName = t.substring(8).trim();
        // UCI has no id-version field. Preserve a trailing numeric version
        // from `id name` (e.g. Stockfish 17.1); never invent one from a path.
        final version = RegExp(r'\s(v?\d+(?:[.\-]\w+)*)\s*$').firstMatch(_detectedName);
        _detectedVersion = version == null ? '' : version.group(1)!;
      } else if (t.startsWith('id author ')) {
        _detectedAuthor = t.substring(10).trim();
      } else if (t.startsWith('option name ')) {
        final opt = UciOption.parse(t);
        if (opt != null) options.add(opt);
      }
      return;
    }

    // Search counters. Recorded for any `info` line that carries them, not
    // only the ones with a depth, because engines print `nodes`/`nps` on the
    // final line and some print them on every line.
    if (t.startsWith('info') && !t.startsWith('info string')) {
      int? grab(RegExp re) {
        final m = re.firstMatch(t);
        return m == null ? null : int.tryParse(m.group(1)!);
      }

      final nodes = grab(_nodesRegex);
      final nps = grab(_npsRegex);
      final timeMs = grab(_timeRegex);
      final hashFull = grab(_hashFullRegex);
      final tbhits = grab(_tbHitsRegex);
      final depth = grab(_depthRegex);
      if (nodes != null ||
          nps != null ||
          timeMs != null ||
          hashFull != null ||
          tbhits != null ||
          depth != null) {
        _lastStats = _lastStats.merge(SearchStatistics(
          nodes: nodes,
          nps: nps,
          timeMs: timeMs,
          hashFullPerMille: hashFull,
          tablebaseHits: tbhits,
          depth: depth,
        ));
      }
    }

    // Parse evaluation info lines
    if (t.startsWith('info') && t.contains('depth')) {
      final depthMatch = _depthRegex.firstMatch(t);
      if (depthMatch == null) return;

      double? score;
      final cpMatch = _cpRegex.firstMatch(t);
      final mateMatch = _mateRegex.firstMatch(t);
      if (cpMatch != null) {
        score = int.parse(cpMatch.group(1)!) / 100.0;
      } else if (mateMatch != null) {
        final mateIn = int.parse(mateMatch.group(1)!);
        score = mateIn > 0 ? 999.0 : -999.0;
      }

      if (score != null) {
        // UCI scores are from the side to move; the app's are from White's.
        final whiteScore = searchWhiteToMove ? score : -score;
        final pvMatch = _pvRegex.firstMatch(t);
        final pv = pvMatch?.group(1);
        final bestMove = pv?.split(' ').first;
        final mpvMatch = _multipvRegex.firstMatch(t);
        if (_evalController.isClosed) return;
        _evalController.add(EvalInfo(
          score: whiteScore,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: bestMove,
          pv: pv,
          pvIndex: mpvMatch != null ? int.parse(mpvMatch.group(1)!) : 1,
        ));
      }
    }

    // Parse bestmove. Every `bestmove` ends exactly one search, including
    // `(none)` and the one the engine emits in response to `stop` — routing all
    // of them through the coordinator is what keeps an aborted search's answer
    // from being handed to the next request.
    if (t.startsWith('bestmove')) {
      final parts = t.split(' ');
      final move = parts.length >= 2 && parts[1] != '(none)' ? parts[1] : null;
      finishSearch(move);
      if (!disposingProcess) _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) => _bestMove(positionCommand,
      depth: depth, moveTime: moveTime, skillLevel: skillLevel);

  Future<String> _bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel, int? nodes,
  }) async {
    if (_isDisposed) throw StateError('Engine disposed');
    if (_process == null) throw StateError('Not initialized');
    if (processGone) throw await processDeathReport();
    // Counters belong to one search; a merge across two would report the
    // larger of two depths and the sum-shaped nonsense in between.
    resetSearchStatistics();
    _stateNotifier.value = EngineState.thinking;
    // A custom profile's explicit UCI Skill Level is a user-owned option, so
    // keep it authoritative. The app-wide strength slider still has to work for
    // every profile that does *not* override it — dropping it there would leave
    // the slider silently doing nothing for UCI engines.
    final hasSkillLevelOverride = profile.optionOverrides.keys
        .any((key) => key.trim().toLowerCase() == 'skill level');
    if (skillLevel != null && !hasSkillLevelOverride) {
      setOption('Skill Level', '$skillLevel');
    }

    // Drive play by time rather than a fixed depth: the cost of a given depth
    // grows by an order of magnitude once the position opens up, which is what
    // made moves take seconds by the middlegame.
    final go = nodes == null
        ? uciGoCommand(depth: depth, moveTime: moveTime, skillLevel: skillLevel)
        : 'go nodes $nodes';
    final cap = nodes != null ? const Duration(seconds: 60) : uciSearchTimeout(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);

    final move = await startSearch(
            positionCommand,
            go,
            awaitMove: true,
            // Whose turn it is belongs to the search, not to the engine: the
            // lookups below convert `info` lines that may still be arriving
            // from the search being stopped.
            whiteToMove: positionCommandIsWhiteToMove(positionCommand))
        .timeout(cap, onTimeout: () {
      abandonSearch();
      return null;
    });
    if (move == null) {
      // A null answer means one of two very different things, and reporting
      // both as a timeout is what let a crashed engine pass for a slow one.
      if (processGone) throw await processDeathReport();
      throw TimeoutException(
          'No bestmove within ${cap.inMilliseconds}ms', cap);
    }
    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) {
    if (_process == null || processGone) {
      // Silently returning an empty stream here is how a dead engine looked
      // like a quiet one: the eval bar simply stopped updating.
      if (processGone) debugPrint('[$processLabel] analysis skipped: process gone');
      return const Stream.empty();
    }
    resetSearchStatistics();
    _stateNotifier.value = EngineState.thinking;
    // Bound the depth search by the clock too. A fixed depth costs whatever
    // that depth costs in the position in front of it — the thing that was
    // taken out of `bestMove` because it turned into seconds per move by the
    // middlegame — and nothing here ever stopped it: analysis has no timeout,
    // so a strong engine asked for depth 20 sits at full CPU until the next
    // move happens to interrupt it. On a phone that is the battery.
    //
    // `infinite` is left alone: it is unbounded on purpose and ends at `stop`.
    startSearch(
        positionCommand,
        infinite
            ? 'go infinite'
            : 'go depth ${depth ?? 20} movetime ${kFixedDepthTimeCap.inMilliseconds}',
        awaitMove: false,
        whiteToMove: positionCommandIsWhiteToMove(positionCommand));
    return _evalController.stream;
  }

  /// Set a UCI option at runtime.
  @override
  void setOption(String name, String value) {
    _send('setoption name $name value $value');
    for (final opt in options) {
      if (opt.name == name) opt.value = value;
    }
  }

  /// Trigger a button-type UCI option.
  void pressButton(String name) {
    _send('setoption name $name');
  }

  /// Waits for a stopped search's `bestmove` before this connection is reused.
  @override
  Future<void> drainSearch({Duration timeout = const Duration(seconds: 5)}) =>
      quiesceSearch(timeout: timeout);

  @override
  void stop() {
    // Ask the engine to stop, but leave the search registered: its `bestmove`
    // is still coming and must be consumed here, not by the next request.
    if (isSearching) _send('stop');
    // Do not report `ready` here: UCI is not idle until the matching `bestmove`
    // arrives. `_handleLine` performs that transition after the protocol
    // response, so a caller cannot start the next search on a connection that
    // is still finishing the previous one. Reporting `ready` unconditionally
    // also turned a disposed engine back into a live one.
  }

  /// Stops the process and forgets it, reporting nothing about the exit.
  ///
  /// Used both by [dispose] and by a failed [initialize]: a half-started engine
  /// must not leave a process behind, and its own death must not be reported as
  /// a crash of a working engine.
  Future<void> _teardownProcess({bool announce = true}) async {
    final process = _process;
    _process = null;

    await _stdoutSub?.cancel();
    _stdoutSub = null;

    if (process == null) {
      stopWatchingProcess();
      return;
    }

    beginProcessDispose();
    if (announce) {
      try {
        process.stdin.writeln('quit');
      } catch (_) {
        // Already gone; nothing to flush.
      }
    }
    stopWatchingProcess();
    try {
      await process.stdin.close();
    } catch (_) {}
    try {
      process.kill();
    } catch (_) {
      // Already exited.
    }
    resetSearches();
  }

  @override
  void dispose() {
    if (_stateNotifier.value == EngineState.disposed) return;
    beginProcessDispose();
    final ready = _readyOk;
    _readyOk = null;
    if (ready != null && !ready.isCompleted) ready.complete();
    resetSearches();
    _send('quit');
    _stdoutSub?.cancel();
    _stdoutSub = null;
    stopWatchingProcess();
    if (!_evalController.isClosed) _evalController.close();
    _process?.kill();
    _process = null;
    _stateNotifier.value = EngineState.disposed;
  }
}
