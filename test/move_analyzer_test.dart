import 'package:flutter_test/flutter_test.dart';
import 'package:chess/chess.dart' as chess;
import 'package:crispchess/chess/chess_game.dart';
import 'package:crispchess/chess/move_analyzer.dart';

void main() {
  group('MoveAnalyzer', () {
    test('analyzeInIsolate returns annotation for opening move', () {
      final request = AnalysisRequest(
        fen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        uciMove: 'e2e4',
        evaluation: MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.3,
          bestMove: 'e2e4',
          bestMoveScore: 0.3,
          depth: 10,
          whiteToMove: true,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.move, 'e2e4');
      expect(annotation.gamePhase, GamePhase.opening);
    });

    test('MoveEvaluation quality thresholds', () {
      // Good move (slight improvement)
      final good = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 0.2,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      expect(good.quality, MoveQuality.good);

      // Blunder (big loss)
      final blunder = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -4.0,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      expect(blunder.quality, MoveQuality.blunder);
    });

    test('MoveQuality.brilliant for significant improvement', () {
      // White moves, eval goes from 0.0 to +2.0 (big improvement for White)
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 2.0,
        bestMove: 'e2e4',
        bestMoveScore: 2.0,
        depth: 15,
        whiteToMove: true,
      );
      // evaluationChange = 0.0 - 2.0 = -2.0 => brilliant (< -1.0)
      expect(eval.quality, MoveQuality.brilliant);
    });

    test('MoveQuality.neutral for small change', () {
      // White moves, eval goes from 0.5 to 0.2 => change = 0.3
      final eval = MoveEvaluation(
        scoreBefore: 0.5,
        scoreAfter: 0.2,
        bestMove: 'd2d4',
        bestMoveScore: 0.5,
        depth: 10,
        whiteToMove: true,
      );
      // evaluationChange = 0.5 - 0.2 = 0.3, which is < 0.5 => neutral
      expect(eval.quality, MoveQuality.neutral);
    });

    test('MoveQuality.mistake for moderate loss', () {
      // White moves, eval drops from 0.0 to -2.5 => change = 0.0 - (-2.5) = 2.5
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -2.5,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 15,
        whiteToMove: true,
      );
      // evaluationChange = 0.0 - (-2.5) = 2.5 => mistake (2.0 <= change < 3.0)
      expect(eval.quality, MoveQuality.mistake);
    });

    test('MoveEvaluation.centipawnLoss for white move', () {
      // White moves, eval drops from 1.0 to 0.5
      final eval = MoveEvaluation(
        scoreBefore: 1.0,
        scoreAfter: 0.5,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // centipawnLoss for white = scoreBefore - scoreAfter = 0.5
      expect(eval.centipawnLoss, closeTo(0.5, 0.001));
    });

    test('MoveEvaluation.centipawnLoss for black move', () {
      // Black moves, eval goes from -1.0 to 0.0 (bad for black)
      final eval = MoveEvaluation(
        scoreBefore: -1.0,
        scoreAfter: 0.0,
        bestMove: 'e7e5',
        bestMoveScore: -1.0,
        depth: 10,
        whiteToMove: false,
      );
      // centipawnLoss for black = scoreAfter - scoreBefore = 0.0 - (-1.0) = 1.0
      expect(eval.centipawnLoss, closeTo(1.0, 0.001));
    });

    test('MoveEvaluation.centipawnLoss is zero when position improves', () {
      // White moves, eval improves from 0.0 to 1.0
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 1.0,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // centipawnLoss = 0.0 - 1.0 = -1.0, clamped to 0
      expect(eval.centipawnLoss, 0.0);
    });

    test('MoveEvaluation.evaluationChange sign convention', () {
      // White move: positive change = worsening
      final whiteEval = MoveEvaluation(
        scoreBefore: 1.0,
        scoreAfter: 0.5,
        bestMove: 'e2e4',
        bestMoveScore: 1.0,
        depth: 10,
        whiteToMove: true,
      );
      // For white: scoreBefore - scoreAfter = 0.5 (positive = loss)
      expect(whiteEval.evaluationChange, closeTo(0.5, 0.001));

      // Black move: positive change = worsening
      final blackEval = MoveEvaluation(
        scoreBefore: -1.0,
        scoreAfter: -0.5,
        bestMove: 'e7e5',
        bestMoveScore: -1.0,
        depth: 10,
        whiteToMove: false,
      );
      // For black: scoreAfter - scoreBefore = -0.5 - (-1.0) = 0.5 (positive = loss)
      expect(blackEval.evaluationChange, closeTo(0.5, 0.001));
    });
  });

  group('MoveAnnotation', () {
    test('getFullDescription includes quality', () {
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: -4.0,
        bestMove: 'e2e4',
        bestMoveScore: 0.3,
        depth: 10,
        whiteToMove: true,
      );
      final annotation = MoveAnnotation(
        move: 'f2f3',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.opening,
      );
      final desc = annotation.getFullDescription();
      // Should contain the quality description (blunder in this case)
      expect(desc.contains('Blunder'), isTrue);
      // Should contain phase advice
      expect(desc.contains('Opening'), isTrue);
    });

    test('getPhaseAdvice varies by phase', () {
      final eval = MoveEvaluation(
        scoreBefore: 0.0,
        scoreAfter: 0.0,
        bestMove: '',
        bestMoveScore: 0.0,
        depth: 10,
        whiteToMove: true,
      );

      final opening = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.opening,
      );
      expect(opening.getPhaseAdvice(), contains('Opening'));
      expect(opening.getPhaseAdvice(), contains('development'));

      final middlegame = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.middlegame,
      );
      expect(middlegame.getPhaseAdvice(), contains('Middlegame'));
      expect(middlegame.getPhaseAdvice(), contains('tactical'));

      final endgame = MoveAnnotation(
        move: 'e2e4',
        evaluation: eval,
        tactics: [],
        positionalThemes: [],
        gamePhase: GamePhase.endgame,
      );
      expect(endgame.getPhaseAdvice(), contains('Endgame'));
      expect(endgame.getPhaseAdvice(), contains('king'));
    });
  });

  group('GamePhase detection', () {
    test('GamePhase detection based on move count and pieces', () {
      // Opening: fewer than 15 moves
      final request = AnalysisRequest(
        fen: 'rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1',
        uciMove: 'e7e5',
        evaluation: MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.0,
          bestMove: '',
          bestMoveScore: 0.0,
          depth: 10,
          whiteToMove: false,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.gamePhase, GamePhase.opening);
    });
  });

  group('analyzeInIsolate', () {
    test('analyzeInIsolate handles castling move', () {
      // Position where white has already castled kingside
      // After 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5, white can castle
      final fen = 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4';
      final request = AnalysisRequest(
        fen: fen,
        uciMove: 'e1g1', // kingside castling
        evaluation: MoveEvaluation(
          scoreBefore: 0.5,
          scoreAfter: 0.6,
          bestMove: 'e1g1',
          bestMoveScore: 0.6,
          depth: 15,
          whiteToMove: true,
        ),
      );
      final annotation = analyzeInIsolate(request);
      expect(annotation.move, 'e1g1');
      // Should detect castling as a tactical pattern
      expect(
        annotation.tactics.any((t) => t.name == 'Castling'),
        isTrue,
      );
    });
  });

  group('analyzeMove pre-move capture detection', () {
    test('detects material gain from the pre-move board, not the post-move board', () {
      // Before the move: white rook on d1, black queen on d8. White plays
      // Rd1xd8, winning the queen (queen 9 > rook 5 => +4 material gain).
      final preFen = '3qk3/8/8/8/8/8/8/3RK3 w - - 0 1';
      // After Rd1xd8: white rook now on d8, black queen gone.
      final postFen = '3Rk3/8/8/8/8/8/8/4K3 b - - 0 1';

      // The analyzer is constructed on the POST-move board (as ChessGame does).
      final analyzer = MoveAnalyzer(chess.Chess.fromFEN(postFen));
      final annotation = analyzer.analyzeMove(
        uciMove: 'd1d8',
        evaluation: MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 3.0,
          bestMove: 'd1d8',
          bestMoveScore: 3.0,
          depth: 15,
          whiteToMove: true,
        ),
        preMoveFen: preFen,
      );

      // Capture + material gain must be read from the pre-move board.
      expect(annotation.tactics.any((t) => t.name == 'Material Gain'), isTrue);
    });
  });

  group('pin detection', () {
    MoveEvaluation eval() => MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.0,
          bestMove: '',
          bestMoveScore: 0.0,
          depth: 10,
          whiteToMove: true,
        );

    test('a bishop that pins a knight to the king is labelled a pin', () {
      // After 1.e4 e5 2.Nf3 Nc6 white plays 3.Bb5: the bishop on b5 attacks
      // the knight on c6, which shields the king on e8 along c6-d7-e8.
      const preFen = 'rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 0 3';
      const postFen = 'r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 1 3';
      final analyzer = MoveAnalyzer(chess.Chess.fromFEN(postFen));
      final annotation = analyzer.analyzeMove(
        uciMove: 'f1b5',
        evaluation: eval(),
        preMoveFen: preFen,
      );
      final pin = annotation.tactics.where((t) => t.name == 'Pin').toList();
      expect(pin, isNotEmpty,
          reason: 'Bb5 pins Nc6 to the king and must be labelled');
      expect(pin.single.involvedSquares, contains('b5'));
      expect(pin.single.involvedSquares, contains('c6'));
    });

    test('a knight fork is not labelled a pin', () {
      // White knight lands on c7 forking king e8 and rook a8. The old logic
      // counted two occupied destinations as a "Pin"; a knight holds no pin
      // (its attack is not a line), so only the fork may be reported.
      const preFen = 'r3k3/8/8/1N6/8/8/8/4K3 b - - 0 1';
      // The knight gives check on the post-move board, so the position is
      // only legal with black to move — a king in check while the other
      // side is to move is rejected by the library.
      const postFen = 'r3k3/2N5/8/8/8/8/8/4K3 b - - 0 2';
      final analyzer = MoveAnalyzer(chess.Chess.fromFEN(postFen));
      final annotation = analyzer.analyzeMove(
        uciMove: 'b5c7',
        evaluation: eval(),
        preMoveFen: preFen,
      );
      expect(annotation.tactics.any((t) => t.name == 'Fork'), isTrue,
          reason: 'Nc7 hits the king and the rook');
      expect(annotation.tactics.any((t) => t.name == 'Pin'), isFalse,
          reason: 'a double attack is not a pin');
    });
  });

  group('GamePhase on FEN-loaded positions', () {
    MoveEvaluation eval() => MoveEvaluation(
          scoreBefore: 0.0,
          scoreAfter: 0.0,
          bestMove: '',
          bestMoveScore: 0.0,
          depth: 10,
          whiteToMove: true,
        );

    test('a loaded middlegame is not called an opening', () {
      // No history (fresh from FEN) but full material past move 15: the
      // move-count branch used to fire on history.length == 0 and hand every
      // loaded position the opening advice.
      final request = AnalysisRequest(
        fen: 'r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 16',
        uciMove: 'c4b3',
        evaluation: eval(),
      );
      expect(analyzeInIsolate(request).gamePhase, GamePhase.middlegame);
    });

    test('a loaded endgame is not called an opening', () {
      final request = AnalysisRequest(
        fen: '8/5k2/8/8/8/8/4K3/4R3 w - - 0 40',
        uciMove: 'e1e7',
        evaluation: eval(),
      );
      expect(analyzeInIsolate(request).gamePhase, GamePhase.endgame);
    });
  });

  group('annotation completion', () {
    test('completes an annotation whose scoreBefore is exactly 0.0', () {
      // A fresh game has no evaluation yet, so the first move's temporary
      // annotation is built with scoreBefore = 0.0. The completion guard used
      // to read that zero as "nothing to complete", so the first move of a
      // game never got its evaluation: always shown as a good move, with no
      // evaluation change and no "Better:" suggestion.
      final game = ChessGame();
      expect(game.makeMove('e2e4'), isTrue);
      expect(game.lastAnnotation!.evaluation.scoreBefore, 0.0,
          reason: 'no analysis has run yet, so this is the zero-score path');

      game.updateEvaluation(-0.4, 'e7e5', 14);

      final completed = game.lastAnnotation!.evaluation;
      expect(completed.bestMove, isNotEmpty,
          reason: 'the pending annotation must complete even from scoreBefore 0.0');
      expect(completed.scoreAfter, -0.4);
      expect(completed.depth, 14);
    });
  });
}
