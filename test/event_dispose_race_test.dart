// Disposing a match service while its run() is in flight must finish the run
// quietly, not throw StateError from an event emitted after close().
//
// The screen owns these services and disposes them in its own dispose() —
// leaving a match, stopping a tournament, or starting a new match all land
// while `await run()` is still going. The services closed their event
// controller in dispose() but kept emitting afterwards (MatchGameFinished,
// MatchMovePlayed, the final MatchFinished), and adding to a closed controller
// throws, so a screen the user had already left turned a completed run into a
// failed future. EngineService.requestMove has the same shape: its BestMoveEvent
// lands after `await bestMove(...)`, which a dispose() can outlive.
import 'dart:async';

import 'package:crispchess/services/engine_match_service.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

/// Releases the engines' first move only when the test says so, so dispose()
/// deterministically lands while a game is waiting on the board.
void gateFirstMove(ScriptedEngine engine, Completer<void> release) {
  engine.ask = (moveNumber, ply) async {
    if (moveNumber == 1) await release.future;
    return openingBookMove(ply) ?? 'a7a6';
  };
}

void main() {
  test('EngineMatchService: dispose mid-run lets run() complete', () async {
    final white = ScriptedEngine('White');
    final black = ScriptedEngine('Black');
    final release = Completer<void>();
    gateFirstMove(white, release);

    final match = EngineMatchService(
      engine1: white,
      engine2: black,
      engine1Id: 'w',
      engine2Id: 'b',
      config: const MatchConfig(numGames: 1),
    );
    final firstEvent = match.events.first;
    final running = match.run();
    await firstEvent; // MatchGameStarted — the game is under way
    match.dispose(); // exactly what the screen's dispose() does
    release.complete();
    final results = await running; // must not throw StateError
    expect(results, isA<List<GameResult>>());
  });

  test('TournamentService: dispose mid-run lets run() complete', () async {
    final a = ScriptedEngine('A');
    final b = ScriptedEngine('B');
    final release = Completer<void>();
    gateFirstMove(a, release);

    final tournament = TournamentService(
      engines: [a, b],
      engineIds: ['a', 'b'],
      gamesPerPairing: 1,
      depthPerMove: 1,
    );
    final firstEvent = tournament.events.first;
    final running = tournament.run();
    await firstEvent; // TournamentRoundStart
    tournament.dispose();
    release.complete();
    final results = await running;
    expect(results, isA<List<GameResult>>());
  });

  test('EngineService: dispose mid-move lets requestMove complete', () async {
    final engine = ScriptedEngine('S');
    final release = Completer<String>();
    engine.ask = (moveNumber, ply) => release.future;

    final service = EngineService(engine);
    service.useOpeningBook = false; // force the gated engine path
    expect(await service.initialize(), isTrue);

    final moving = service.requestMove('position startpos');
    service.dispose(); // the screen is gone while the engine still thinks
    release.complete('e2e4');
    await moving; // must not throw StateError from BestMoveEvent after close
  });
}
