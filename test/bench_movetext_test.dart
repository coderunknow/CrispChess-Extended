// BenchGame.movetext must be the movetext alone. The board library's pgn()
// includes headers; pgnDocument() writes its own header block on top, so a
// full PGN in this field exported every game with two header blocks — and
// _toGameResult passes the same string on as GameResult.pgn, where callers
// expect movetext.
import 'package:crispchess/bench/game_player.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:crispchess/bench/opening_suite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('movetext excludes headers so pgnDocument has exactly one block',
      () async {
    final script = <String>['e2e4', 'e7e5', 'g1f3', 'b8c6'];
    var i = 0;
    Future<EngineMove> requester(
        String position, int? depth, Duration? moveTime) async {
      return EngineMove(script[i++], 1000);
    }

    final game = await playBenchGame(
      index: 7,
      whiteId: 'w',
      blackId: 'b',
      whiteLabel: 'White',
      blackLabel: 'Black',
      whiteMove: requester,
      blackMove: requester,
      opening: const Opening(id: 'start', name: 'Start', category: 'test'),
      plyCap: 4,
    );

    expect(game.outcome, GameOutcome.adjudicated,
        reason: 'plyCap stops the game after the scripted moves');
    expect(game.movetext, isNot(contains('[')),
        reason: 'headers belong to pgnDocument, which writes its own');
    expect(game.movetext, contains('e4'));

    final doc = game.pgnDocument();
    expect('[Event '.allMatches(doc).length, 1,
        reason: 'the exported PGN must contain exactly one header block');
    expect(doc, contains('1. e4'));
  });
}
