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
import 'uci_option.dart';
import 'uci_process_lifecycle.dart';
import 'uci_position.dart';
import 'uci_search_coordinator.dart';

export 'generic_uci_engine_stub.dart' show EngineProfile;
export 'chess_engine.dart' show EngineProcessDiedException;

class GenericUciEngine
    with UciSearchCoordinator, UciProcessLifecycle
    implements ChessEngine {
  final EngineProfile profile;

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  StreamSubscription? _stdoutSub;

  final _evalController = StreamController<EvalInfo>.broadcast();

  /// Engine identity parsed from the UCI handshake.
  String _detectedName = '';
  String _detectedAuthor = '';

  /// Author, as reported by the engine's `id author` line.
  String get engineAuthor => _detectedAuthor;

  /// The name the engine calls itself, which may differ from the name the
  /// user gave this profile. Kept so two profiles — or two different binaries
  /// that share a name — can be told apart in logs and in the UI.
  String get engineIdentifier => _detectedName;

  /// UCI options advertised by the engine.
  final List<UciOption> options = [];

  /// Whether the engine answered `uciok` in the last handshake.
  bool _handshakeComplete = false;

  /// Whether the position currently on the engine has White to move.
  ///
  /// UCI reports `score cp` from the side to move's point of view, while
  /// [EvalInfo] (and every consumer: eval bar, chart, analysis panel) is in
  /// White's. Without this the evaluation of every Black-to-move position was
  /// displayed upside down — the eval bar showed the opponent winning exactly
  /// when the engine thought it was winning.
  bool _whiteToMove = true;

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r' multipv (\d+)');

  /// How long the engine has to answer `uci`.
  ///
  /// Configurable so tests can exercise the timeout without waiting ten
  /// seconds; the default is what the app uses.
  final Duration handshakeTimeout;

  GenericUciEngine(
    this.profile, {
    this.handshakeTimeout = const Duration(seconds: 10),
  });

  @override
  String get name => profile.displayName;
  @override
  String get version => '';
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
  @override
  Future<void> initialize() async {
    if (_stateNotifier.value == EngineState.ready) return;
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

      _send('isready');
      _stateNotifier.value = EngineState.ready;
      debugPrint('[UCI] $name ready (${options.length} options)');
    } catch (e) {
      debugPrint('[UCI] Init failed: $e');
      await _teardownProcess();
      _stateNotifier.value = EngineState.error;
      rethrow;
    }
  }

  @override
  String get processLabel => name;

  @override
  void onProcessLost() {
    if (!disposingProcess) _stateNotifier.value = EngineState.error;
    if (isSearching) finishSearch(null);
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

  void _handleLine(String line, {bool handshake = false}) {
    final t = line.trim();

    // During handshake, parse engine identity and options
    if (handshake) {
      if (t.startsWith('id name ')) {
        _detectedName = t.substring(8).trim();
      } else if (t.startsWith('id author ')) {
        _detectedAuthor = t.substring(10).trim();
      } else if (t.startsWith('option name ')) {
        final opt = UciOption.parse(t);
        if (opt != null) options.add(opt);
      }
      return;
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
        if (!_whiteToMove) score = -score;
        final pvMatch = _pvRegex.firstMatch(t);
        final pv = pvMatch?.group(1);
        final bestMove = pv?.split(' ').first;
        final mpvMatch = _multipvRegex.firstMatch(t);
        _evalController.add(EvalInfo(
          score: score,
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
  }) async {
    if (_process == null) throw StateError('Not initialized');
    if (processGone) throw await processDeathReport();
    _stateNotifier.value = EngineState.thinking;
    _whiteToMove = positionCommandIsWhiteToMove(positionCommand);

    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    // Drive play by time rather than a fixed depth: the cost of a given depth
    // grows by an order of magnitude once the position opens up, which is what
    // made moves take seconds by the middlegame.
    final go = uciGoCommand(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    final cap = uciSearchTimeout(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);

    final move = await startSearch(positionCommand, go, awaitMove: true)
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
    _stateNotifier.value = EngineState.thinking;
    _whiteToMove = positionCommandIsWhiteToMove(positionCommand);
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
        awaitMove: false);
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

  @override
  void stop() {
    // Ask the engine to stop, but leave the search registered: its `bestmove`
    // is still coming and must be consumed here, not by the next request.
    if (isSearching) _send('stop');
    _stateNotifier.value = EngineState.ready;
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
    finishSearch(null);
  }

  @override
  void dispose() {
    if (_stateNotifier.value == EngineState.disposed) return;
    beginProcessDispose();
    finishSearch(null);
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
