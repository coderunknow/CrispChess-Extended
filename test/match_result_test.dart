// What a match result means.
//
// The regression this covers: `EngineMatchService` decided the result by
// comparing SAN strings with "1-0"/"0-1" and treated every other ending as a
// draw, aggregating by display name. So an engine that crashed, or a game
// stopped at the ply cap, was recorded as a draw — for both engines — and two
// profiles with the same name shared one score.
import 'package:crispchess/bench/game_record.dart';
import 'package:crispchess/services/engine_match_service.dart';
import 'package:flutter_test/flutter_test.dart';

GameResult _game({
  required GameOutcome outcome,
  String? forfeitedBy,
  String whiteId = 'builtin:Built-in',
  String blackId = 'custom:p1',
  String white = 'Built-in',
  String black = 'Stockfish',
}) =>
    GameResult(
      whiteId: whiteId,
      blackId: blackId,
      white: white,
      black: black,
      outcome: outcome,
      forfeitedBy: forfeitedBy,
      moves: 40,
      pgn: '1. e4 e5',
    );

void main() {
  group('a game result says what happened', () {
    test('a win is a win', () {
      final result = _game(outcome: GameOutcome.whiteWin);
      expect(result.result, '1-0');
      expect(result.whiteScore, 1);
      expect(result.blackScore, 0);
      expect(result.isRated, isTrue);
    });

    test('a draw is a draw', () {
      final result = _game(outcome: GameOutcome.draw);
      expect(result.result, '1/2-1/2');
      expect(result.whiteScore, 0.5);
      expect(result.isRated, isTrue);
    });

    test('a forfeit names the side that broke, and is not rated', () {
      final result = _game(
        outcome: GameOutcome.forfeit,
        forfeitedBy: 'custom:p1',
      );
      expect(result.result, '1-0 (forfeit)');
      expect(result.pgnResult, '*');
      // The opponent gets the point on the board…
      expect(result.whiteScore, 1);
      // …but the game says nothing about which engine is stronger.
      expect(result.isRated, isFalse);
    });

    test('a game stopped at the ply cap is adjudicated, not drawn', () {
      final result = _game(outcome: GameOutcome.adjudicated);
      expect(result.isRated, isFalse);
      expect(result.whiteScore, isNull);
      expect(result.result, isNot('1/2-1/2'));
    });

    test('an aborted game has no result for anyone', () {
      final result = _game(outcome: GameOutcome.aborted);
      expect(result.whiteScore, isNull);
      expect(result.blackScore, isNull);
      expect(result.isRated, isFalse);
    });

    test('a cancelled game has no result for anyone', () {
      final result = _game(outcome: GameOutcome.cancelled);
      expect(result.whiteScore, isNull);
      expect(result.isRated, isFalse);
    });
  });

  group('aggregation is by id, not by name', () {
    test('two engines with the same display name keep separate scores', () {
      final results = [
        _game(
          outcome: GameOutcome.whiteWin,
          whiteId: 'custom:p1',
          blackId: 'custom:p2',
          white: 'Stockfish',
          black: 'Stockfish',
        ),
      ];
      final scores = EngineMatchService.scores(results);
      expect(scores['custom:p1'], 1);
      expect(scores['custom:p2'], 0);
      // The name is not a key: there is no single "Stockfish" total.
      expect(scores.containsKey('Stockfish'), isFalse);
    });

    test('unrated games move nothing', () {
      final results = [
        _game(outcome: GameOutcome.whiteWin),
        _game(outcome: GameOutcome.adjudicated),
        _game(outcome: GameOutcome.aborted),
        _game(
          outcome: GameOutcome.forfeit,
          forfeitedBy: 'custom:p1',
        ),
      ];
      final scores = EngineMatchService.scores(results);
      // One win for White, plus the point the forfeit awards on the board.
      expect(scores['builtin:Built-in'], 2);
      expect(scores['custom:p1'], 0);
      expect(EngineMatchService.gamesPlayed(results)['custom:p1'], 2);
      final skipped = EngineMatchService.unclassified(results);
      expect(skipped[GameOutcome.adjudicated.id], 1);
      expect(skipped[GameOutcome.aborted.id], 1);
    });

    test('standings are ordered by score and keyed by id', () {
      final results = [
        _game(outcome: GameOutcome.whiteWin),
        _game(
          outcome: GameOutcome.blackWin,
          whiteId: 'custom:p1',
          blackId: 'builtin:Built-in',
        ),
      ];
      final standings = TournamentService.standings(results);
      expect(standings.map((entry) => entry.key).toSet(),
          {'builtin:Built-in', 'custom:p1'});
      expect(standings.first.value, 1);
      expect(standings.length, 2);
    });
  });
}
