// Built-in drill content must be mechanically true: every step's position
// loads, its "correct" move is legal, an explanation that claims checkmate
// (#) really is mate, and wrong-move messages name moves that can be played.
//
// Two content bugs this pins: the back-rank drill's second step offered
// Ra8 as mate while a black rook on d8 blocked the check entirely, and the
// two-bishops drill's king-march step had correctMove c1d2 moving a bishop
// while the explanation said "Kd2 begins the king march" (the king is on e1).
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/drill.dart';
import 'package:flutter_test/flutter_test.dart';

chess.Chess _board(String fen) {
  final game = chess.Chess();
  expect(game.load(fen), isTrue, reason: 'drill FEN must load: $fen');
  return game;
}

bool _try(chess.Chess game, String uci) => game.move({
      'from': uci.substring(0, 2),
      'to': uci.substring(2, 4),
    }) ==
    true;

void main() {
  group('built-in drills', () {
    test('every correct move is legal from its position', () {
      for (final drill in builtInDrills) {
        for (final step in drill.steps) {
          expect(step.correctMove.length, 4,
              reason: '${drill.id}: UCI move expected');
          final game = _board(step.fen);
          expect(_try(game, step.correctMove), isTrue,
              reason: '${drill.id}: ${step.correctMove} must be legal');
        }
      }
    });

    test('an explanation that claims checkmate really mates', () {
      for (final drill in builtInDrills) {
        for (final step in drill.steps) {
          final explanation = step.explanation ?? '';
          if (!explanation.contains('#')) continue;
          final game = _board(step.fen);
          expect(_try(game, step.correctMove), isTrue,
              reason: '${drill.id}: claimed mate ${step.correctMove} must '
                  'at least be legal');
          expect(game.in_checkmate, isTrue,
              reason: '${drill.id}: explanation claims "#", but '
                  '${step.correctMove} is not checkmate from ${step.fen}');
        }
      }
    });

    test('wrong-move messages name legal moves', () {
      for (final drill in builtInDrills) {
        for (final step in drill.steps) {
          for (final uci in step.wrongMoveMessages.keys) {
            final game = _board(step.fen);
            expect(_try(game, uci), isTrue,
                reason: '${drill.id}: wrong-move message for $uci, which is '
                    'not even legal here — the message can never show');
          }
        }
      }
    });

    test('the two-bishops king-march step moves the king', () {
      final drill =
          builtInDrills.firstWhere((d) => d.id == 'two_bishops_mate');
      expect(drill.steps.first.correctMove, 'e1d2',
          reason: 'the explanation says Kd2 begins the king march and the '
              'king starts on e1; c1d2 moved the bishop instead');
    });
  });
}
