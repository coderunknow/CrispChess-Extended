/// Shared test harness for the Engine Lab: a scripted engine and a way to run a
/// short, real benchmark with it.
///
/// The engines are scripted through `ChessEngine` rather than mocked at the
/// service level, so the tests exercise the runner's real event loop, the real
/// game loop and the real storage path.
library;

import 'dart:async';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/search_telemetry.dart';
import 'package:crispchess/engines/uci_capabilities.dart';
import 'package:flutter/foundation.dart';

/// The move to play at ply [ply] of the starting position.
///
/// A fixed, legal game — Scholar's mate — rather than a random one: the tests
/// need a decisive result in a handful of plies, and every move must survive
/// the runner's legality check.
///
/// The book is keyed on the position, not on the engine, so the same function
/// drives both engines and both colours: White's moves and Black's moves are
/// looked up from the movelist the runner sent with the position.
String? openingBookMove(int ply) {
  const white = ['e2e4', 'f1c4', 'd1h5', 'h5f7'];
  const black = ['e7e5', 'b8c6', 'g8f6'];
  if (ply.isEven) {
    final index = ply ~/ 2;
    return index < white.length ? white[index] : null;
  }
  final index = (ply - 1) ~/ 2;
  return index < black.length ? black[index] : null;
}

/// Ply reached in a UCI position command (`position startpos moves e2e4 ...`).
int plyOf(String positionCommand) {
  final marker = positionCommand.indexOf(' moves ');
  if (marker < 0) return 0;
  final moves = positionCommand.substring(marker + 7).trim();
  if (moves.isEmpty) return 0;
  return moves.split(' ').length;
}

/// An engine whose every answer is scripted by the test.
class ScriptedEngine extends ChessEngine
    implements SearchTelemetry, UciOptionAware, SearchDrainableEngine {
  @override
  final String name;

  /// Every `initialize()` call, in order, so a test can prove a second engine
  /// was never started after a cancellation.
  final List<String> initialised = [];

  /// Positions the engine was asked about.
  final List<String> askedPositions = [];

  /// Every `setoption name ... value ...` the runner applied.
  final Map<String, String> appliedOptions = {};

  /// Answers a move request. [moveNumber] counts this engine's own moves.
  Future<String> Function(int moveNumber, int ply) ask = (n, ply) async =>
      openingBookMove(ply) ?? 'a7a6';

  /// Thrown by [initialize] when set.
  Object? initFailure;

  /// When set, [initialize] waits for this before returning.
  Completer<void>? initGate;

  /// When set, [stop] completes it, so a test can release a pending search.
  Completer<void>? stopGate;

  bool disposed = false;
  int disposeCalls = 0;
  int stopCalls = 0;
  int drainCalls = 0;
  SearchStatistics stats = SearchStatistics.none;

  ScriptedEngine(this.name);

  EngineState _state = EngineState.idle;

  @override
  String get version => '1.0';

  @override
  String get license => 'MIT';

  @override
  int get estimatedElo => 1500;

  @override
  EngineState get state => _state;

  @override
  final ValueNotifier<EngineState> stateNotifier =
      ValueNotifier(EngineState.idle);

  @override
  bool get canPonder => false;

  @override
  Future<void> initialize() async {
    initialised.add(name);
    _state = EngineState.initializing;
    final gate = initGate;
    if (gate != null) await gate.future;
    final failure = initFailure;
    if (failure != null) {
      _state = EngineState.error;
      throw failure;
    }
    _state = EngineState.ready;
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    askedPositions.add(positionCommand);
    if (_state != EngineState.ready) {
      throw StateError('Not initialized');
    }
    return ask(askedPositions.length, plyOf(positionCommand));
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
          {int? depth, bool infinite = false}) =>
      const Stream<EvalInfo>.empty();

  @override
  void stop() {
    stopCalls++;
    final gate = stopGate;
    stopGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  void dispose() {
    disposeCalls++;
    disposed = true;
    _state = EngineState.disposed;
  }

  // SearchTelemetry
  @override
  SearchStatistics get lastSearchStatistics => stats;

  @override
  void resetSearchStatistics() => stats = SearchStatistics.none;

  @override
  Future<void> synchronizeOptions() async {}

  // UciOptionAware
  @override
  List<String> get advertisedOptionNames => const ['Threads', 'Hash'];

  @override
  bool advertisesOption(String option) =>
      advertisedOptionNames.any((o) => o.toLowerCase() == option.toLowerCase());

  @override
  void applyOption(String option, String value) =>
      appliedOptions[option] = value;

  // SearchDrainableEngine
  @override
  Future<void> drainSearch(
      {Duration timeout = const Duration(seconds: 5)}) async {
    drainCalls++;
  }
}

/// A built-in engine identity for tests. Names are used as labels, so a test
/// can pass a hostile one.
EngineIdentity testIdentity(String name) => EngineIdentity.forBuiltIn(
      name: name,
      engineVersion: '1.0',
      appBuild: 'test',
    );

/// A configuration that plays a short real game quickly.
BenchmarkConfig benchConfig({
  int gamesPerPairing = 2,
  int repetitions = 1,
  int warmUpGames = 0,
  int plyCap = 200,
  Duration? maxDuration,
  int? maxGames,
  String openingSuiteId = 'startpos',
}) =>
    BenchmarkConfig(
      preset: BenchmarkPreset.custom,
      timePerMove: const Duration(milliseconds: 5),
      gamesPerPairing: gamesPerPairing,
      maxGames: maxGames,
      maxDuration: maxDuration,
      plyCap: plyCap,
      openingSuiteId: openingSuiteId,
      seed: 7,
      warmUpGames: warmUpGames,
      repetitions: repetitions,
      adaptiveStopping: false,
    );

/// A complete, real benchmark run between two scripted engines.
///
/// The runner is not disposed: [BenchmarkRunner.dispose] releases the engines,
/// and a test that needs them still standing can inspect them first.
Future<({
  BenchmarkRun run,
  BenchmarkRunner runner,
  ScriptedEngine alpha,
  ScriptedEngine beta,
})> runScriptedBenchmark({
  BenchmarkConfig? config,
  String alphaName = 'Alpha',
  String betaName = 'Beta',
  ScriptedEngine? alpha,
  ScriptedEngine? beta,
}) async {
  final first = alpha ?? ScriptedEngine(alphaName);
  final second = beta ?? ScriptedEngine(betaName);
  final identities = [
    testIdentity(alphaName),
    testIdentity(betaName),
  ];
  final plan = buildPlan(
    config: config ?? benchConfig(),
    engines: identities,
  );
  final runner = BenchmarkRunner(
    plan: plan,
    slots: {
      identities[0].engineId:
          BenchEngineSlot(identity: identities[0], build: () => first),
      identities[1].engineId:
          BenchEngineSlot(identity: identities[1], build: () => second),
    },
    environment: BenchmarkEnvironment.unknown,
  );
  final run = await runner.run();
  return (run: run, runner: runner, alpha: first, beta: second);
}
