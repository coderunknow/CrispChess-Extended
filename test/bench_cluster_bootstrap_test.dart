/// Deterministic regressions for the dev5 statistics: joint covariance,
/// opening-cluster bootstrap, pairwise contrasts and precision stopping.
library;

import 'dart:math' as math;

import 'package:crispchess/bench/cluster_bootstrap.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:crispchess/bench/intelligent_scheduler.dart';
import 'package:crispchess/bench/precision.dart';
import 'package:crispchess/services/rating_fit.dart';
import 'package:flutter_test/flutter_test.dart';

List<ClusteredRatedGame> simulate({
  required Map<String, double> trueRatings,
  required List<(String, String)> edges,
  required int clusters,
  int seed = 7,
  double drawRate = 0.5,
}) {
  final random = math.Random(seed);
  final games = <ClusteredRatedGame>[];
  for (var c = 0; c < clusters; c++) {
    final cluster = 'opening-$c';
    for (final edge in edges) {
      final a = trueRatings[edge.$1]!, b = trueRatings[edge.$2]!;
      final p = 1 / (1 + math.pow(10, (b - a) / 400));
      for (final whiteFirst in [true, false]) {
        final white = whiteFirst ? edge.$1 : edge.$2;
        final black = whiteFirst ? edge.$2 : edge.$1;
        final score = random.nextDouble() < drawRate
            ? 0.5
            : random.nextDouble() < p
                ? 1.0
                : 0.0;
        games.add(ClusteredRatedGame(
          clusterId: cluster, white: white, black: black, score: score,
        ));
      }
    }
  }
  return games;
}

void main() {
  group('joint covariance', () {
    test('pairwise variance differs from the independence formula', () {
      // 3 engines, unequal edge counts: A–B well measured, B–C well measured,
      // A–C only through B. Cov(A,C) is materially positive.
      final games = <RatedGame>[];
      for (var i = 0; i < 40; i++) {
        games.add((white: 'a', black: 'b', score: i.isEven ? 1.0 : 0.0));
        games.add((white: 'b', black: 'c', score: i.isEven ? 1.0 : 0.0));
      }
      final model = fitRatingModel(games);
      final a = model.players.indexOf('a');
      final b = model.players.indexOf('b');
      final c = model.players.indexOf('c');
      final covarianceVariance = model.covariance[a][a] +
          model.covariance[c][c] -
          2 * model.covariance[a][c];
      expect(model.covariance[a][c], isNot(0),
          reason: 'joint covariance must not be diagonal');
      final independence = model.covariance[a][a] + model.covariance[c][c];
      expect(covarianceVariance, lessThan(independence),
          reason: 'ignoring covariance overstates the pairwise interval');
      final viaFit = model.contrastVariance({'a': 1.0, 'c': -1.0});
      expect(viaFit, closeTo(covarianceVariance, 1e-6));
    });

    test('disconnected engines have infinite contrast variance', () {
      final model = fitRatingModel([
        (white: 'a', black: 'b', score: 1),
        (white: 'c', black: 'd', score: 1),
      ]);
      expect(model.components.length, 2);
      expect(model.contrastVariance({'a': 1, 'c': -1}), double.infinity);
    });

    test('a perfect record is flagged separated and never given a finite SE', () {
      final model = fitRatingModel([
        for (var i = 0; i < 30; i++) (white: 'a', black: 'b', score: 1.0),
      ]);
      expect(model.separated, isTrue);
      final a = model.ratingFor('a')!;
      expect(a.stdErr.isFinite, isFalse);
    });

    test('participants with no games are kept with an unknown rating', () {
      final model = fitRatingModel(
        [(white: 'a', black: 'b', score: 1)],
        participants: ['a', 'b', 'idle'],
      );
      expect(model.players, contains('idle'));
      final idle = model.ratingFor('idle')!;
      expect(idle.games, 0);
      expect(idle.stdErr, double.infinity);
      expect(idle.hasUsableEstimate, isFalse);
    });
  });

  group('opening-cluster bootstrap', () {
    test('too few clusters blocks a precision claim instead of narrowing it', () async {
      final games = simulate(
        trueRatings: {'a': 1600, 'b': 1500},
        edges: [('a', 'b')],
        clusters: 4,
      );
      final report = await runClusterBootstrap(
        games: games,
        participants: ['a', 'b'],
        precision: const PrecisionSettings(),
        settings: const BootstrapSettings(replicates: 200, minValidReplicates: 99),
      );
      expect(report.reliable, isFalse);
      expect(report.completed, isTrue);
      expect(report.warnings.join(' '), contains('clusters'));
      expect(report.individual, isEmpty);
    });

    test('replicate failures are counted, not silently dropped', () async {
      final games = simulate(
        trueRatings: {'a': 1650, 'b': 1500, 'c': 1350},
        edges: [('a', 'b'), ('b', 'c'), ('a', 'c')],
        clusters: 30,
      );
      // A cluster that only ever saw one pairing cannot break connectivity, but
      // recording its absence in the report is what matters here.
      final report = await runClusterBootstrap(
        games: games,
        participants: ['a', 'b', 'c'],
        precision: const PrecisionSettings(confidenceLevel: 0.9),
        settings: const BootstrapSettings(replicates: 300, minValidReplicates: 100),
      );
      expect(report.attemptedReplicates, greaterThanOrEqualTo(300));
      expect(report.validReplicates + report.failedReplicates, report.attemptedReplicates);
      expect(report.confidenceLevel, 0.9);
      expect(report.individual.length, 3);
      final ab = report.pairwise[pairwiseKey('a', 'b')]!;
      expect(ab.pointwise.isFinite, isTrue);
      expect(ab.difference, greaterThan(0));
      // The simultaneous interval can only be at least as wide.
      expect(ab.simultaneous.halfWidth + 1e-9,
          greaterThanOrEqualTo(ab.pointwise.halfWidth));
    });

    test('pointwise coverage recovers a known difference', () async {
      var covered = 0;
      const trials = 20;
      for (var t = 0; t < trials; t++) {
        final games = simulate(
          trueRatings: {'a': 1600, 'b': 1500},
          edges: [('a', 'b')],
          clusters: 40,
          seed: 100 + t,
        );
        final report = await runClusterBootstrap(
          games: games,
          participants: ['a', 'b'],
          precision: const PrecisionSettings(objective: PrecisionObjective.pairwise),
          settings: const BootstrapSettings(replicates: 200, minValidReplicates: 100),
        );
        if (!report.reliable) continue;
        final interval = report.pairwise[pairwiseKey('a', 'b')]!.pointwise;
        if (interval.low <= 100 && interval.high >= 100) covered++;
      }
      // Nominal 95%; 200 replicates and 20 trials leave room for noise, but the
      // interval must not be systematically too narrow.
      expect(covered, greaterThanOrEqualTo(15));
    });
  });

  group('precision evaluation', () {
    test('achieves only when the bootstrap supports the tolerance', () async {
      final games = simulate(
        trueRatings: {'a': 1600, 'b': 1500, 'c': 1400},
        edges: [('a', 'b'), ('b', 'c'), ('a', 'c')],
        clusters: 50,
      );
      final fit = fitElo(games: [for (final g in games) (white: g.white, black: g.black, score: g.score)],
          labels: {'a': 'A', 'b': 'B', 'c': 'C'}, participants: ['a', 'b', 'c']);
      final report = await runClusterBootstrap(
        games: games,
        participants: ['a', 'b', 'c'],
        precision: const PrecisionSettings(
          individualToleranceElo: 5, pairwiseToleranceElo: 5,
          pairwiseScope: PairwiseIntervalScope.pointwise,
        ),
        settings: const BootstrapSettings(replicates: 300, minValidReplicates: 100),
      );
      final strict = evaluatePrecision(
        fit: fit.withBootstrap(report),
        precision: const PrecisionSettings(individualToleranceElo: 5, pairwiseToleranceElo: 5),
        participantIds: ['a', 'b', 'c'], targetIds: ['a'], ratedGames: 300,
      );
      expect(strict.achieved, isFalse);
      expect(strict.unmet, isNotEmpty);
      expect(strict.additionalGamesEstimate, isNotNull);

      final loose = evaluatePrecision(
        fit: fit.withBootstrap(report),
        precision: const PrecisionSettings(individualToleranceElo: 1000, pairwiseToleranceElo: 1000),
        participantIds: ['a', 'b', 'c'], targetIds: ['a'], ratedGames: 300,
      );
      expect(loose.achieved, isTrue);
    });

    test('an unreliable bootstrap never reports success', () async {
      final games = simulate(
        trueRatings: {'a': 1600, 'b': 1500}, edges: [('a', 'b')], clusters: 6,
      );
      final fit = fitElo(games: [for (final g in games) (white: g.white, black: g.black, score: g.score)],
          labels: {'a': 'A', 'b': 'B'});
      final report = await runClusterBootstrap(
        games: games, participants: ['a', 'b'],
        precision: const PrecisionSettings(),
        settings: const BootstrapSettings(replicates: 200, minValidReplicates: 99),
      );
      final evaluation = evaluatePrecision(
        fit: fit.withBootstrap(report),
        precision: const PrecisionSettings(individualToleranceElo: 1000, pairwiseToleranceElo: 1000),
        participantIds: ['a', 'b'], targetIds: ['a'], ratedGames: games.length,
      );
      expect(evaluation.achieved, isFalse);
    });
  });
}
