import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/engine_match_service.dart';

class _FakeEngine implements ChessEngine, SearchDrainableEngine {
  @override
  final String name;
  final String move;
  final Completer<void>? searching;
  final Completer<String>? pending;
  final Completer<void>? drainGate;
  final Completer<void>? drainStarted;
  final bool leaveThinkingAfterMove;
  int drainCalls = 0;
  _FakeEngine(this.name, this.move, {
    this.searching,
    this.pending,
    this.drainGate,
    this.drainStarted,
    this.leaveThinkingAfterMove = false,
  });

  EngineState _state = EngineState.idle;
  final ValueNotifier<EngineState> _notifier = ValueNotifier(EngineState.idle);
  @override
  String get version => 'test';
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 0;
  @override
  EngineState get state => _state;
  @override
  ValueNotifier<EngineState> get stateNotifier => _notifier;
  @override
  bool get canPonder => false;
  void failBeforeStart() {
    _state = EngineState.error;
    _notifier.value = _state;
  }
  @override
  Future<void> initialize() async {
    _state = EngineState.ready;
    _notifier.value = _state;
  }
  @override
  Future<String> bestMove(String positionCommand, {int? depth, Duration? moveTime, int? skillLevel}) async {
    _state = EngineState.thinking;
    _notifier.value = _state;
    if (searching != null && !searching!.isCompleted) searching!.complete();
    final wait = pending;
    final result = wait != null ? await wait.future : move;
    if (!leaveThinkingAfterMove) {
      _state = EngineState.ready;
      _notifier.value = _state;
    }
    return result;
  }

  @override
  Future<void> drainSearch({Duration timeout = const Duration(seconds: 5)}) async {
    drainCalls++;
    if (drainStarted != null && !drainStarted!.isCompleted) drainStarted!.complete();
    if (drainGate != null) await drainGate!.future.timeout(timeout);
    _state = EngineState.ready;
    _notifier.value = _state;
  }
  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) async* {}
  @override
  void stop() {
    if (pending != null && !pending!.isCompleted) {
      pending!.completeError(StateError('search stopped'));
    }
  }
  @override
  void setOption(String name, String value) {}
  @override
  void dispose() {
    _state = EngineState.disposed;
    _notifier.dispose();
  }
}

void main() {
  test('an illegal move is a forfeit, never an ordinary draw', () async {
    final white = _FakeEngine('Same label', 'e2e5');
    final black = _FakeEngine('Same label', 'e7e5');
    final match = EngineMatchService(
      engine1: white,
      engine2: black,
      engine1Id: 'custom:first',
      engine2Id: 'custom:second',
      config: const MatchConfig(numGames: 1),
    );
    final results = await match.run();
    expect(results, hasLength(1));
    expect(results.single.status, GameResultStatus.forfeit);
    expect(results.single.result, '0-1');
    expect(results.single.eligibleForRating, isFalse);
    expect(results.single.failureReason, contains('Illegal move'));
    expect(results.single.whiteId, 'custom:first');
    expect(results.single.blackId, 'custom:second');
    expect(EngineMatchService.scoresById(results), isEmpty);
    match.dispose();
    white.dispose();
    black.dispose();
  });

  test('same display names remain distinct in score aggregation', () {
    final results = [
      GameResult(
        white: 'Shared', black: 'Shared', whiteId: 'custom:a', blackId: 'custom:b',
        result: '1-0', moves: 10, pgn: '',
      ),
    ];
    expect(EngineMatchService.scoresById(results), {'custom:a': 1, 'custom:b': 0});
  });

  test('cancelling during a search is classified, not scored as a draw or forfeit', () async {
    final searching = Completer<void>();
    final pending = Completer<String>();
    final white = _FakeEngine('white', 'e2e4', searching: searching, pending: pending);
    final black = _FakeEngine('black', 'e7e5');
    final match = EngineMatchService(
      engine1: white,
      engine2: black,
      config: const MatchConfig(numGames: 1),
    );
    final future = match.run();
    await searching.future;
    match.stop();
    final result = await future;
    expect(result.single.status, GameResultStatus.cancelled);
    expect(result.single.eligibleForRating, isFalse);
    expect(EngineMatchService.scoresById(result), isEmpty);
    match.dispose();
    white.dispose();
    black.dispose();
  });

  test('tournament cancellation records a cancelled game instead of a forfeit', () async {
    final searching = Completer<void>();
    final pending = Completer<String>();
    final white = _FakeEngine('white', 'e2e4', searching: searching, pending: pending);
    final black = _FakeEngine('black', 'e7e5');
    final tournament = TournamentService(
      engines: [white, black],
      engineIds: const ['white-id', 'black-id'],
      gamesPerPairing: 2,
    );
    final future = tournament.run();
    await searching.future;
    tournament.stop();
    final results = await future;
    expect(results, hasLength(1));
    expect(results.single.status, GameResultStatus.cancelled);
    expect(results.single.eligibleForRating, isFalse);
    tournament.dispose();
    white.dispose();
    black.dispose();
  });

  test('tournament drains a stopped UCI search before reusing the engine', () async {
    final draining = Completer<void>();
    final drainStarted = Completer<void>();
    final first = _FakeEngine(
      'first',
      'e2e5',
      drainGate: draining,
      drainStarted: drainStarted,
      leaveThinkingAfterMove: true,
    );
    final second = _FakeEngine('second', 'e7e5');
    final tournament = TournamentService(
      engines: [first, second],
      engineIds: const ['first-id', 'second-id'],
      gamesPerPairing: 2,
    );
    final future = tournament.run();
    // Let the one-game match finish and enter the bounded protocol drain.
    await drainStarted.future.timeout(const Duration(seconds: 1));
    expect(first.state, EngineState.thinking);
    expect(tournament.results, hasLength(1));

    draining.complete();
    final results = await future;
    expect(first.drainCalls, 1);
    expect(results, hasLength(2));
    expect(results.every((result) => result.status == GameResultStatus.forfeit), isTrue);
    tournament.dispose();
    first.dispose();
    second.dispose();
  });

  test('round robin preserves identities and emits one aggregate completion', () async {
    final engines = [
      _FakeEngine('duplicate', 'e2e5'),
      _FakeEngine('duplicate', 'e2e5'),
      _FakeEngine('duplicate', 'e2e5'),
    ];
    final tournament = TournamentService(
      engines: engines,
      engineIds: const ['id:a', 'id:b', 'id:c'],
      gamesPerPairing: 2,
    );
    var finishedEvents = 0;
    final subscription = tournament.events.listen((event) {
      if (event is MatchFinished) finishedEvents++;
    });
    final results = await tournament.run();
    expect(results, hasLength(6));
    expect(results.map((result) => result.whiteId).toSet().union(
      results.map((result) => result.blackId).toSet(),
    ), {'id:a', 'id:b', 'id:c'});
    expect(results.every((result) => result.status == GameResultStatus.forfeit), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(finishedEvents, 1, reason: 'submatches must not announce tournament completion');
    await subscription.cancel();
    tournament.dispose();
    for (final engine in engines) {
      engine.dispose();
    }
  });

  test('a failed engine handshake is represented as a forfeit', () async {
    final failed = _FakeEngine('broken', 'e2e4')..failBeforeStart();
    final opponent = _FakeEngine('opponent', 'e7e5');
    final result = await EngineMatchService(
      engine1: failed,
      engine2: opponent,
      engine1Id: 'failed-id',
      engine2Id: 'ok-id',
      config: const MatchConfig(numGames: 1),
    ).run();
    expect(result.single.status, GameResultStatus.forfeit);
    expect(result.single.result, '0-1');
    failed.dispose();
    opponent.dispose();
  });
}
