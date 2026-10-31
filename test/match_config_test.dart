// One search budget per game, and the configuration says which.
//
// A UCI engine given `go depth 8` and a time control obeys the depth and
// ignores the clock. Every producer of `MatchConfig` used to set both: the
// match screen passed its depth slider alongside a per-move time, so a "timed"
// match measured a depth budget — and the rating the run produced described a
// search the report did not name.
import 'package:crispchess/engines/chess_engine.dart' show uciGoCommand;
import 'package:crispchess/services/engine_match_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MatchConfig', () {
    test('a timed configuration carries no depth', () {
      final config = MatchConfig.timed(moveTime: const Duration(milliseconds: 100));
      expect(config.depthPerMove, isNull);
      expect(config.effectiveDepth, isNull);
      expect(config.moveTime, const Duration(milliseconds: 100));
    });

    test('a timed configuration cannot quietly gain a depth', () {
      // The default depth is 10; the factory must clear it, and the getter must
      // keep it cleared even if a caller builds the object by hand.
      expect(const MatchConfig().effectiveDepth, 10);
      expect(
        const MatchConfig(depthPerMove: 10, moveTime: Duration(milliseconds: 50))
            .effectiveDepth,
        isNull,
      );
    });

    test('the go command for a timed config has no depth in it', () {
      final config = MatchConfig.timed(moveTime: const Duration(milliseconds: 100));
      expect(
        uciGoCommand(depth: config.effectiveDepth, moveTime: config.moveTime),
        'go movetime 100',
      );
    });

    test('the go command for a depth config has no clock in it', () {
      const config = MatchConfig(depthPerMove: 6);
      expect(
        uciGoCommand(depth: config.effectiveDepth, moveTime: config.moveTime),
        goDepth(6),
      );
    });
  });

}

/// `go depth N`, spelled out rather than interpolated, so a change to the
/// command's shape shows up here as a failure instead of silently matching.
String goDepth(int depth) => 'go depth $depth';
