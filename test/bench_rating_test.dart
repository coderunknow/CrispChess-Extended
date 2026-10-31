// The rating numbers a report is allowed to show.
//
// These are the promises the Engine Lab makes about a rating: it comes with an
// interval, it is graded by how much evidence is behind it, games without a
// result are excluded (and counted), and a change between two runs is only
// called a change when its own interval excludes zero.
import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/calibration.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:flutter_test/flutter_test.dart';

BenchGame _game(
  int index, {
  required GameOutcome outcome,
  String whiteId = 'a',
  String blackId = 'b',
  String? forfeitedBy,
}) =>
    BenchGame(
      index: index,
      whiteId: whiteId,
      blackId: blackId,
      whiteLabel: whiteId,
      blackLabel: blackId,
      openingId: 'startpos',
      openingName: 'Starting position',
      startFen: '',
      moves: const ['e2e4'],
      movetext: '1. e4',
      outcome: outcome,
      forfeitedBy: forfeitedBy,
    );

void main() {
  group('quality grades', () {
    test('too few games is never a rating worth quoting', () {
      expect(gradeRating(19, 40), RatingQuality.insufficient);
      expect(gradeRating(200, 251), RatingQuality.insufficient);
      expect(gradeRating(300, double.infinity), RatingQuality.insufficient);
    });

    test('the thresholds behave at the boundary', () {
      expect(gradeRating(100, 50), RatingQuality.high);
      expect(gradeRating(99, 50), RatingQuality.moderate);
      expect(gradeRating(60, 80), RatingQuality.moderate);
      expect(gradeRating(59, 79), RatingQuality.low);
      expect(gradeRating(60, 81), RatingQuality.low);
    });
  });

  group('fitting a run', () {
    test('adjudications are draws only when explicitly enabled', () {
      final games = [_game(1, outcome: GameOutcome.adjudicated)];
      for (final enabled in [false, true]) {
        final fit = fitRunRatings(
          games: games,
          labels: const {'a': 'A', 'b': 'B'},
          config: BenchmarkConfig.quick.copyWith(
            countAdjudicatedAsDraws: enabled,
          ),
        );
        expect(fit.ratedGames, enabled ? 1 : 0);
        if (enabled) {
          expect(fit.ratingFor('a')!.rating,
              closeTo(fit.ratingFor('b')!.rating, 0.001));
        }
      }
    });

    test('a 75% score recovers the closed-form gap', () {
      final games = [
        for (var i = 0; i < 75; i++)
          _game(i + 1, outcome: GameOutcome.whiteWin, whiteId: 'a', blackId: 'b'),
        for (var i = 0; i < 25; i++)
          _game(i + 76, outcome: GameOutcome.blackWin, whiteId: 'a', blackId: 'b'),
      ];
      final fit = fitRunRatings(
        games: games,
        labels: const {'a': 'A', 'b': 'B'},
        config: BenchmarkConfig.quick.copyWith(warmUpGames: 0),
      );
      final gap =
          fit.ratingFor('a')!.rating - fit.ratingFor('b')!.rating;
      // 400 * log10(3) = 190.85; the prior pulls it in slightly.
      expect(gap, closeTo(400 * 0.47712125471966244, 6));
      expect(fit.ratedGames, 100);
      for (final rating in fit.ratings) {
        expect(rating.stdErr.isFinite, isTrue);
        expect(rating.ciLow, lessThan(rating.rating));
        expect(rating.ciHigh, greaterThan(rating.rating));
      }
    });

    test('games without a result are excluded and counted, not drawn', () {
      final fit = fitRunRatings(
        games: [
          _game(1, outcome: GameOutcome.whiteWin),
          _game(2, outcome: GameOutcome.aborted),
          _game(3, outcome: GameOutcome.adjudicated),
          _game(4, outcome: GameOutcome.forfeit, forfeitedBy: 'a'),
          _game(5, outcome: GameOutcome.cancelled),
        ],
        labels: const {'a': 'A', 'b': 'B'},
        config: BenchmarkConfig.quick.copyWith(warmUpGames: 0),
      );
      expect(fit.ratedGames, 1);
      expect(fit.excludedByOutcome[GameOutcome.aborted.id], 1);
      expect(fit.excludedByOutcome[GameOutcome.adjudicated.id], 1);
      expect(fit.excludedByOutcome[GameOutcome.forfeit.id], 1);
      expect(fit.excludedByOutcome[GameOutcome.cancelled.id], 1);
      // A single rated game cannot produce a usable rating.
      expect(
        fit.ratings.every((r) => r.quality == RatingQuality.insufficient),
        isTrue,
      );
    });

    test('warm-up games never enter the fit', () {
      final fit = fitRunRatings(
        games: [
          for (var i = 0; i < 30; i++)
            _game(i + 1,
                outcome: GameOutcome.whiteWin, whiteId: 'a', blackId: 'b'),
          for (var i = 0; i < 30; i++)
            BenchedWarmUp.game(i + 31),
        ],
        labels: const {'a': 'A', 'b': 'B'},
        config: BenchmarkConfig.quick.copyWith(warmUpGames: 2),
      );
      expect(fit.ratedGames, 30);
    });

    test('an engine that never played another is reported as disconnected',
        () {
      final fit = fitRunRatings(
        games: [
          _game(1, outcome: GameOutcome.whiteWin, whiteId: 'a', blackId: 'b'),
          _game(2, outcome: GameOutcome.whiteWin, whiteId: 'c', blackId: 'd'),
        ],
        labels: const {'a': 'A', 'b': 'B', 'c': 'C', 'd': 'D'},
        config: BenchmarkConfig.quick.copyWith(warmUpGames: 0),
      );
      expect(fit.components.length, 2);
      expect(fit.inSameComponent('a', 'b'), isTrue);
      expect(fit.inSameComponent('a', 'c'), isFalse);
      expect(fit.compare('a', 'c')!.warnings, isNotEmpty);
    });

    test('ratings do not depend on the order the games are listed in', () {
      final games = [
        for (var i = 0; i < 40; i++)
          _game(i + 1,
              outcome: i.isEven ? GameOutcome.whiteWin : GameOutcome.blackWin,
              whiteId: 'a',
              blackId: 'b'),
        for (var i = 0; i < 40; i++)
          _game(i + 41,
              outcome: i.isEven ? GameOutcome.blackWin : GameOutcome.draw,
              whiteId: 'c',
              blackId: 'b'),
      ];
      final config = BenchmarkConfig.quick.copyWith(warmUpGames: 0);
      final first = fitRunRatings(games: games, labels: const {}, config: config);
      final shuffled = [...games.reversed];
      final second =
          fitRunRatings(games: shuffled, labels: const {}, config: config);
      for (final rating in first.ratings) {
        expect(second.ratingFor(rating.engineId)!.rating,
            closeTo(rating.rating, 1e-6));
      }
    });
  });

  group('comparing two ratings', () {
    test('a difference inside its own interval is not a result', () {
      final fit = fitElo(games: [
        (white: 'a', black: 'b', score: 1.0),
        (white: 'b', black: 'a', score: 1.0),
      ]);
      final comparison = fit.compare('a', 'b')!;
      expect(comparison.isSignificant, isFalse);
      expect(comparison.verdict, contains('no reliable difference'));
    });

    test('a large, well-measured difference is a result', () {
      final fit = fitElo(games: [
        for (var i = 0; i < 120; i++)
          (white: 'a', black: 'b', score: 1.0),
        for (var i = 0; i < 20; i++)
          (white: 'b', black: 'a', score: 1.0),
      ]);
      final comparison = fit.compare('a', 'b')!;
      expect(comparison.isSignificant, isTrue);
      expect(comparison.ciLow, greaterThan(0));
    });
  });

  group('the regression detector', () {
    EloRating rating(String id, double value, double se) => EloRating(
          engineId: id,
          label: id,
          rating: value,
          stdErr: se,
          ciLow: value - kZ95 * se,
          ciHigh: value + kZ95 * se,
          wins: 50,
          draws: 0,
          losses: 50,
          quality: RatingQuality.moderate,
          opponents: 1,
        );

    test('a change smaller than the noise is not called a change', () {
      final delta = ratingDelta(rating('a', 1500, 40), rating('a', 1525, 40))!;
      expect(delta.isReliable, isFalse);
      expect(delta.verdict, contains('no reliable change'));
      // And it suggests how many more games would settle it.
      expect(delta.suggestedAdditionalGames, greaterThan(0));
    });

    test('a change far outside the noise is called one', () {
      final delta = ratingDelta(rating('a', 1500, 20), rating('a', 1560, 20))!;
      expect(delta.isReliable, isTrue);
      expect(delta.isImprovement, isTrue);
      expect(delta.verdict, contains('improvement'));
    });

    test('a rating with no interval is not comparable at all', () {
      final delta =
          ratingDelta(rating('a', 1500, 20), rating('a', 1500, double.infinity))!;
      expect(delta.isReliable, isFalse);
      expect(delta.verdict, contains('not comparable'));
    });
  });

  group('calibration', () {
    final identities = [
      EngineIdentity.forBuiltIn(
          name: 'Built-in', engineVersion: '1', appBuild: 'x'),
      EngineIdentity.forBuiltIn(
          name: 'Lynx', engineVersion: '1', appBuild: 'x'),
    ];
    final fit = fitElo(games: [
      for (var i = 0; i < 60; i++) (white: identities[0].engineId, black: identities[1].engineId, score: 1.0),
      for (var i = 0; i < 40; i++) (white: identities[1].engineId, black: identities[0].engineId, score: 1.0),
    ], labels: {
      identities[0].engineId: 'Built-in',
      identities[1].engineId: 'Lynx',
    });

    test('no declared anchor means no absolute number', () {
      final outcome = calibrateElo(
        fit: fit,
        anchor: null,
        config: BenchmarkConfig.quick,
        identities: identities,
      );
      expect(outcome.available, isFalse);
      expect(outcome.reason, contains('No calibration anchor'));
      expect(outcome.calibrated, isEmpty);
    });

    test('an anchor that did not take part cannot calibrate', () {
      final outcome = calibrateElo(
        fit: fit,
        anchor: const RatingAnchor(
          id: 'x',
          engineName: 'Stockfish',
          engineVersion: '17',
          rating: 3600,
          scale: 'CCRL 40/2',
          source: 'ccrl.org',
          publishedDate: '2026-01-01',
          hardware: 'Ryzen 9',
          timeControl: '40/2',
          timePerMoveMs: 100,
        ),
        config: BenchmarkConfig.quick,
        identities: identities,
      );
      expect(outcome.available, isFalse);
      expect(outcome.reason, contains('did not take part'));
    });

    test('an anchor whose budget is far off cannot calibrate', () {
      final outcome = calibrateElo(
        fit: fit,
        anchor: RatingAnchor(
          id: 'x',
          engineName: 'Built-in',
          engineIdHint: identities[0].engineId,
          engineVersion: '1',
          rating: 3200,
          scale: 'CCRL 40/2',
          source: 'ccrl.org',
          publishedDate: '2026-01-01',
          hardware: 'Ryzen 9',
          timeControl: '40/2',
          timePerMoveMs: 1000,
        ),
        config: BenchmarkConfig.quick,
        identities: identities,
      );
      expect(outcome.available, isFalse);
      expect(outcome.reason, contains('difference'));
    });
  });
}

/// A warm-up game, for the tests that check warmth is not rated.
class BenchedWarmUp {
  static BenchGame game(int index) => BenchGame(
        index: index,
        whiteId: 'a',
        blackId: 'b',
        whiteLabel: 'A',
        blackLabel: 'B',
        openingId: 'startpos',
        openingName: 'Starting position',
        startFen: '',
        moves: const ['e2e4'],
        movetext: '1. e4',
        outcome: GameOutcome.whiteWin,
        warmUp: true,
      );
}
