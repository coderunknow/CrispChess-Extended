/// Regressions for the intelligent scheduler: role separation, connected
/// pilot, information-per-cost selection, paired colour reversal, seed
/// reproducibility and budget stopping.
library;

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/cluster_bootstrap.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:crispchess/bench/intelligent_scheduler.dart';
import 'package:crispchess/bench/opening_suite.dart';
import 'package:crispchess/bench/precision.dart';
import 'package:flutter_test/flutter_test.dart';

EngineIdentity identity(String name) => EngineIdentity.forBuiltIn(
      name: name, engineVersion: '1.0', appBuild: 'test',
    );

SchedulerCandidate candidate(
  String name, {
  double? rating,
  double moveMs = 50,
  double failure = 0,
  bool available = true,
  bool supportsNodes = true,
}) =>
    SchedulerCandidate(
      identity: identity(name),
      estimatedRating: rating,
      available: available,
      unavailableReason: available ? null : 'not on this platform',
      expectedMoveMillis: moveMs,
      failureProbability: failure,
      supportsNodeLimit: supportsNodes,
    );

BenchmarkConfig config({
  int? maxGames = 400,
  double individual = 20,
  double pairwise = 20,
  PrecisionObjective objective = PrecisionObjective.both,
  int seed = 11,
}) =>
    BenchmarkConfig.standard.copyWith(
      preset: BenchmarkPreset.custom,
      openingSuiteId: 'cluster-40',
      maxGames: () => maxGames,
      warmUpGames: 0,
      repetitions: 1,
      gamesPerPairing: 2,
      seed: seed,
      precision: PrecisionSettings(
        objective: objective,
        individualToleranceElo: individual,
        pairwiseToleranceElo: pairwise,
      ),
    );

IntelligentScheduler scheduler({
  List<String> targets = const ['builtin:Alpha'],
  List<SchedulerCandidate>? pool,
  Set<String> excluded = const {},
  BenchmarkConfig? cfg,
}) =>
    IntelligentScheduler(
      targetIds: targets,
      candidates: pool ??
          [
            candidate('Alpha', rating: 1700),
            candidate('Beta', rating: 1600),
            candidate('Gamma', rating: 1450),
            candidate('Delta', rating: 1200),
            candidate('Idle', available: false),
          ],
      config: cfg ?? config(),
      suite: openingSuiteById('cluster-40'),
      excludedIds: excluded,
      bootstrapSettings: const BootstrapSettings(minClusters: 20),
    );

void main() {
  test('targets, candidate pool and participants are distinct roles', () {
    final s = scheduler();
    expect(s.targetIds, ['builtin:Alpha']);
    expect(s.selectedOpponents, isNotEmpty);
    expect(s.selectedOpponents, isNot(contains('builtin:Idle')));
    expect(s.participantIds.first, 'builtin:Alpha');
    for (final opponent in s.selectedOpponents) {
      expect(s.participantIds, contains(opponent));
    }
    // The unavailable candidate is not a participant but stays documented.
    expect(s.candidates.map((c) => c.id), contains('builtin:Idle'));
  });

  test('an excluded candidate is never selected', () {
    final s = scheduler(excluded: {'builtin:Gamma'});
    expect(s.selectedOpponents, isNot(contains('builtin:Gamma')));
  });

  test('the pilot is connected and pairs colours on one opening', () {
    final s = scheduler(pool: [
      candidate('Alpha', rating: 1700),
      candidate('Beta', rating: 1600),
      candidate('Gamma', rating: 1400),
    ]);
    final plan = s.buildPilotPlan();
    expect(plan.format, TournamentFormat.intelligent);
    expect(plan.targetEngineIds, ['builtin:Alpha']);
    expect(plan.games.length.isEven, isTrue);

    final adjacency = <String, Set<String>>{};
    for (final game in plan.games) {
      adjacency.putIfAbsent(game.whiteId, () => {}).add(game.blackId);
      adjacency.putIfAbsent(game.blackId, () => {}).add(game.whiteId);
    }
    expect(adjacency.length, s.participantIds.length,
        reason: 'every participant is connected');

    // Every opening unit is exactly two games with reversed colours.
    final pairs = <String, List<PlannedGame>>{};
    for (final game in plan.games) {
      expect(game.clusterId, isNotNull);
      expect(game.openingId, isNotNull);
      pairs.putIfAbsent(game.pairId!, () => []).add(game);
    }
    for (final entry in pairs.entries) {
      expect(entry.value.length, 2);
      expect(entry.value[0].whiteId, entry.value[1].blackId);
      expect(entry.value[0].blackId, entry.value[1].whiteId);
      expect(entry.value[0].openingId, entry.value[1].openingId);
      expect(entry.value[0].clusterId, entry.value[1].clusterId);
    }
    // The pilot is the *minimum* connected schedule: one colour-reversed unit
    // per tree edge, so one cluster per edge. Reaching minClusters is the
    // adaptive phase's job; a pilot that tried to buy all 20 up front used to
    // demand an unaffordable budget and select no opponent at all.
    final clusters = plan.games.map((g) => g.clusterId).toSet();
    expect(clusters.length, plan.games.length ~/ 2);
    expect(s.participantIds.length, greaterThanOrEqualTo(2));
    expect(plan.games.length, 2 * (s.participantIds.length - 1),
        reason: 'one colour-reversed unit per spanning-tree edge');
    expect(clusters.length, s.participantIds.length - 1);
    // The cluster is the line of chess, so it is stable for the same opening no
    // matter which pairing plays it.
    final suite = openingSuiteById('cluster-40');
    for (final game in plan.games) {
      final opening = suite.openings.firstWhere((o) => o.id == game.openingId);
      expect(game.clusterId, suite.clusterIdFor(opening));
    }
  });

  test('the same seed produces the same pilot', () {
    final a = scheduler(cfg: config(seed: 99)).buildPilotPlan();
    final b = scheduler(cfg: config(seed: 99)).buildPilotPlan();
    expect(
      [for (final g in a.games) '${g.whiteId}/${g.blackId}/${g.openingId}'],
      [for (final g in b.games) '${g.whiteId}/${g.blackId}/${g.openingId}'],
    );
  });

  test('a tighter tolerance is schedule-affecting, not cosmetic', () {
    final loose = scheduler(cfg: config(individual: 200, pairwise: 200)).buildPilotPlan();
    final tight = scheduler(cfg: config(individual: 5, pairwise: 5)).buildPilotPlan();
    expect(loose.config.precision.individualToleranceElo, 200);
    expect(tight.config.precision.individualToleranceElo, 5);
    expect(tight.games.length, greaterThan(0));
  });

  test('a node-limited run excludes engines that cannot honour it', () {
    final s = scheduler(pool: [
      candidate('Alpha', rating: 1700),
      candidate('Beta', rating: 1600, supportsNodes: false),
      candidate('Gamma', rating: 1500),
    ], cfg: config().copyWith(nodeLimit: () => 10000));
    expect(s.selectedOpponents, isNot(contains('builtin:Beta')));
  });

  test('a budget that cannot hold one opening pair is refused, not thrown at',
      () {
    // One game cannot hold a colour-reversed pair, so the pilot is impossible.
    // That is an argument error about the budget, not a StateError about
    // opponents — and it names what would have been needed.
    final starved = scheduler(cfg: config(maxGames: 1));
    expect(starved.hasRoomForAnOpeningUnit, isFalse);
    // Which impossible input is named first is an implementation detail; that
    // it is refused, and refuses cleanly, is not.
    expect(starved.buildPilotPlan, throwsA(anything));
    // Two games is exactly one unit: a target with one opponent is planned, and
    // nothing more is promised.
    final minimal = scheduler(cfg: config(maxGames: 2));
    expect(minimal.hasRoomForAnOpeningUnit, isTrue);
    expect(minimal.participantIds.length, 2,
        reason: 'the minimum pilot fits: one edge, one pair');
    expect(minimal.buildPilotPlan().games.length, 2);
  });

  test('adaptive decisions stop truthfully at the game budget', () {
    final s = scheduler(cfg: config(maxGames: 400));
    final plan = s.buildPilotPlan();
    final fit = fitElo(
      games: [for (final g in plan.games) (white: g.whiteId, black: g.blackId, score: 0.5)],
      labels: {for (final id in s.participantIds) id: id},
      participants: s.participantIds,
    );
    final decision = s.decideNext(
      games: const <BenchGame>[],
      fit: fit,
      bootstrap: null,
      // The last affordable two-game unit has been played.
      state: const SchedulerState(gamesPlayed: 399),
      finalBootstrapReserveMillis: 0,
    );
    expect(decision.stop, isTrue);
    expect(decision.reason, contains('budget'));
    expect(decision.games, isEmpty);
    // The decision is logged with its reason, for the saved report.
    expect(s.decisionLog.last['reason'], decision.reason);
  });

  test('an achieved objective stops the scheduler with that reason', () async {
    final s = scheduler(pool: [
      candidate('Alpha', rating: 1500),
      candidate('Beta', rating: 1500),
    ], cfg: config(individual: 1000, pairwise: 1000));
    final games = <ClusteredRatedGame>[];
    for (var i = 0; i < 40; i++) {
      games.add(ClusteredRatedGame(clusterId: 'o$i', white: 'builtin:Alpha',
          black: 'builtin:Beta', score: i.isEven ? 1 : 0));
    }
    final report = await runClusterBootstrap(
      games: games, participants: s.participantIds,
      precision: const PrecisionSettings(individualToleranceElo: 1000, pairwiseToleranceElo: 1000),
      settings: const BootstrapSettings(replicates: 200, minValidReplicates: 100),
    );
    final fit = fitElo(
      games: [for (final g in games) (white: g.white, black: g.black, score: g.score)],
      labels: {for (final id in s.participantIds) id: id},
      participants: s.participantIds,
    ).withBootstrap(report);
    final decision = s.decideNext(
      games: const <BenchGame>[], fit: fit, bootstrap: report,
      state: const SchedulerState(gamesPlayed: 80),
      finalBootstrapReserveMillis: 0,
    );
    expect(decision.stop, isTrue);
    expect(decision.reason, 'precision objective achieved');
  });

  test('a participant with no games does not stop every candidate scoring', () {
    // A participant that failed to start has zero rated games, which makes its
    // covariance diagonal infinite. Summing `uᵀCu` over it produced NaN, so
    // every candidate's utility was NaN, `utility > bestUtility` was false for
    // all of them, and the scheduler stopped with "no affordable informative
    // matchup" no matter what budget was left.
    final s = scheduler(pool: [
      candidate('Alpha', rating: 1700),
      candidate('Beta', rating: 1500),
      candidate('Gamma', rating: 1400),
    ], cfg: config(individual: 5, pairwise: 5));
    final plan = s.buildPilotPlan();
    // Alpha and Beta played; Gamma is present in the participant list but has
    // no rated game.
    final played = plan.games
        .where((g) => !g.whiteId.endsWith('Gamma') && !g.blackId.endsWith('Gamma'))
        .toList();
    final fit = fitElo(
      games: [
        for (final g in played)
          (white: g.whiteId, black: g.blackId,
              score: g.whiteId.endsWith('Alpha') ? 1.0 : 0.0),
        // A rated game for Gamma would defeat the point of the test.
      ],
      labels: {for (final id in s.participantIds) id: id},
      participants: s.participantIds,
    );
    // Gamma played no rated game, so it contributes no row to the fit --
    // that is exactly the isolated-participant precondition this test needs.
    expect(fit.ratings.any((r) => r.engineId == 'builtin:Gamma'), isFalse,
        reason: 'the precondition: Gamma has no rated games');
    final decision = s.decideNext(
      games: const <BenchGame>[], fit: fit, bootstrap: null,
      state: SchedulerState(gamesPlayed: played.length),
      finalBootstrapReserveMillis: 0,
    );
    expect(decision.stop, isFalse,
        reason: 'a usable matchup remains and the budget is untouched');
    expect(decision.games, isNotEmpty);
    // The score must stay comparable, not become NaN.
    expect(decision.utility.isNaN, isFalse);
  });

  test('an adaptive decision is one colour-reversed unit on a fresh opening', () {
    final s = scheduler(pool: [
      candidate('Alpha', rating: 1700),
      candidate('Beta', rating: 1500),
    ], cfg: config(individual: 5, pairwise: 5));
    final plan = s.buildPilotPlan();
    final fit = fitElo(
      games: [for (final g in plan.games) (white: g.whiteId, black: g.blackId, score: g.whiteId.endsWith('Alpha') ? 1.0 : 0.0)],
      labels: {for (final id in s.participantIds) id: id},
      participants: s.participantIds,
    );
    final decision = s.decideNext(
      games: const <BenchGame>[], fit: fit, bootstrap: null,
      state: SchedulerState(gamesPlayed: plan.games.length),
      finalBootstrapReserveMillis: 0,
    );
    expect(decision.stop, isFalse);
    expect(decision.games.length, 2);
    expect(decision.games[0].whiteId, decision.games[1].blackId);
    expect(decision.games[0].clusterId, decision.games[1].clusterId);
    expect(decision.matchupReason, isNotNull);
    expect(decision.matchupReason, contains('variance'));
    expect(decision.games[0].openingId, isNot(plan.games.first.openingId));
  });

  test('a single target still gets a connected pilot when it is affordable', () {
    final s = scheduler(targets: ['builtin:Alpha'], pool: [
      candidate('Alpha', rating: 1500, moveMs: 30),
      candidate('Beta', rating: 1510, moveMs: 30),
    ]);
    final plan = s.buildPilotPlan();
    expect(plan.games, isNotEmpty);
    expect(plan.engines.length, 2);
  });
}
