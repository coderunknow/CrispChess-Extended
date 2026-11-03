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
      // A's *expected score*, which is what a rating difference predicts.
      final expectedA = 1 / (1 + math.pow(10, (b - a) / 400));
      // Draws must not erase the strength difference: a game is drawn with
      // probability [drawRate] and otherwise decided by the stronger player at
      // exactly the rate that keeps E[score] = [expectedA]. Sampling the winner
      // from [expectedA] directly would count the drawn half of every game as
      // "no information", shrinking a true 100-Elo gap to about 49 and making a
      // coverage test unwinnable.
      final decisiveA = drawRate >= 1
          ? 0.5
          : ((expectedA - drawRate / 2) / (1 - drawRate)).clamp(0.0, 1.0);
      for (final whiteFirst in [true, false]) {
        // The pair is colour-reversed, so the *player* carries the strength, not
        // the colour.
        final white = whiteFirst ? edge.$1 : edge.$2;
        final black = whiteFirst ? edge.$2 : edge.$1;
        final aWins = random.nextDouble() < decisiveA;
        final score = random.nextDouble() < drawRate
            ? 0.5
            // White's score: A won on White, or B won on Black.
            : (aWins == whiteFirst) ? 1.0 : 0.0;
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
      final independence = model.covariance[a][a] + model.covariance[c][c];
      // The sign is the whole point, and it is not the intuitive one. A and C
      // are both measured only against B, so their mean-centred errors move
      // together: the covariance is *negative*, and Var(A - C) is therefore
      // LARGER than two independent intervals would make it. Treating the
      // covariance as zero would understate the pairwise interval by 44% here.
      expect(model.covariance[a][c], lessThan(0),
          reason: 'a shared opponent correlates the two errors');
      expect(covarianceVariance, greaterThan(independence),
          reason: 'ignoring a negative covariance understates the pairwise '
              'interval');
      // A-B and B-C each have variance 1/w, and Var(A-C) = 1/w + 1/w exactly
      // because the shared B cancels. Checked against the closed form, not
      // against another implementation of the same formula.
      final w = 40.0 * 0.25;
      final scale = ratingEloScale;
      expect(covarianceVariance,
          closeTo(2 / w * scale * scale, 1e-6));
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

    test('a perfect record is flagged separated, and the prior says so', () {
      // The point prior is deliberate: it keeps the displayed estimate and its
      // interval finite so a report has something to show. What it must never do
      // is hide that the record was perfect — `separated` is the flag that tells
      // a reader the number rests on the prior, not on data.
      final model = fitRatingModel([
        for (var i = 0; i < 30; i++) (white: 'a', black: 'b', score: 1.0),
      ]);
      expect(model.separated, isTrue);
      final a = model.ratingFor('a')!;
      expect(a.rating.isFinite, isTrue);
      // With no prior the observed curvature is genuinely near-singular: the
      // interval explodes by an order of magnitude and the estimate is no longer
      // something to publish. The prior is what makes the difference, and
      // `separated` is how a reader learns the number rests on it.
      final unregularized = fitRatingModel(
        [for (var i = 0; i < 30; i++) (white: 'a', black: 'b', score: 1.0)],
        prior: 0,
      );
      expect(unregularized.separated, isTrue);
      final raw = unregularized.ratingFor('a')!;
      expect(raw.stdErr, greaterThan(5 * a.stdErr),
          reason: 'without the prior the separated interval must explode');
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
      // 4 clusters is below the 20-cluster minimum, so no interval may be
      // published at all: a narrow interval from four openings would be a
      // precision claim the data cannot support.
      expect(report.reliable, isFalse);
      expect(report.completed, isFalse);
      expect(report.attemptedReplicates, 0);
      expect(report.warnings.join(' '), contains('clusters'));
      expect(report.individual, isEmpty);
      expect(report.pairwise, isEmpty);
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
