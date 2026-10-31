/// The game schedule for a benchmark: who plays whom, with which colour, from
/// which opening.
///
/// Built before anything starts, so the whole run can be inspected — how many
/// games, how long it will take, whether one engine is scheduled to play White
/// more often than another — and so the plan can be stored with the run and
/// replayed.
library;

import 'dart:math' as math;

import 'benchmark_config.dart';
import 'engine_identity.dart';
import 'opening_suite.dart';

/// Tournament shape.
enum TournamentFormat {
  /// Every engine plays every other engine.
  roundRobin,

  /// One reference engine plays each challenger.
  gauntlet;

  String get id => name;
}

/// One scheduled game.
class PlannedGame {
  /// 1-based position among *recorded* games; 0 for warm-ups.
  final int index;
  final String whiteId;
  final String blackId;

  /// Which pairing this belongs to (0-based), used for opening selection.
  final int pairingIndex;
  final bool isWarmUp;

  const PlannedGame({
    required this.index,
    required this.whiteId,
    required this.blackId,
    required this.pairingIndex,
    this.isWarmUp = false,
  });
}

/// A fully determined schedule.
class BenchmarkPlan {
  final BenchmarkConfig config;
  final TournamentFormat format;
  final List<EngineIdentity> engines;
  final String? referenceEngineId;
  final OpeningSuite suite;
  final List<PlannedGame> games;
  final List<String> warnings;

  const BenchmarkPlan({
    required this.config,
    required this.format,
    required this.engines,
    required this.suite,
    required this.games,
    this.referenceEngineId,
    this.warnings = const [],
  });

  /// Recorded games only.
  List<PlannedGame> get recordedGames =>
      [for (final game in games) if (!game.isWarmUp) game];

  int get totalGames => recordedGames.length;

  int get warmUpGames => games.length - recordedGames.length;

  int get pairings =>
      format == TournamentFormat.gauntlet
          ? math.max(0, engines.length - 1)
          : engines.length * (engines.length - 1) ~/ 2;

  Set<String> get engineIds => {for (final engine in engines) engine.engineId};

  /// Games scheduled for [engineId], recorded only.
  int gamesFor(String engineId) =>
      recordedGames.where((g) => g.whiteId == engineId || g.blackId == engineId).length;

  int whiteGamesFor(String engineId) =>
      recordedGames.where((g) => g.whiteId == engineId).length;

  int blackGamesFor(String engineId) =>
      recordedGames.where((g) => g.blackId == engineId).length;

  /// The size of the run, for the confirmation step in the UI.
  WorkloadEstimate estimate() => estimateWorkload(
        config,
        engineCount: engines.length,
        pairings: pairings,
      );

  Map<String, dynamic> toJson() => {
        'format': format.id,
        if (referenceEngineId != null) 'reference': referenceEngineId,
        'suite': suite.id,
        'games': [
          for (final game in games)
            {
              'index': game.index,
              'white': game.whiteId,
              'black': game.blackId,
              'pairing': game.pairingIndex,
              if (game.isWarmUp) 'warmUp': true,
            }
        ],
      };
}

/// Builds the schedule.
///
/// Throws [ArgumentError] when there is nothing to schedule: fewer than two
/// engines, or a gauntlet without a reference that is in the list. Failing here
/// is deliberate — a run that silently drops an engine is the failure mode the
/// report has to be able to rule out.
BenchmarkPlan buildPlan({
  required BenchmarkConfig config,
  required List<EngineIdentity> engines,
  TournamentFormat format = TournamentFormat.roundRobin,
  String? referenceEngineId,
  OpeningSuite? suite,
}) {
  if (engines.length < 2) {
    throw ArgumentError('A benchmark needs at least two engines.');
  }
  final ids = <String>{for (final engine in engines) engine.engineId};
  if (ids.length != engines.length) {
    throw ArgumentError(
        'The same engine was selected twice; each engine can appear once.');
  }
  if (format == TournamentFormat.gauntlet) {
    if (referenceEngineId == null || !ids.contains(referenceEngineId)) {
      throw ArgumentError(
          'A gauntlet needs a reference engine that is part of the run.');
    }
  }
  final openingSuite = suite ?? openingSuiteById(config.openingSuiteId);

  // Pairings, in a deterministic order.
  final pairings = <List<String>>[];
  if (format == TournamentFormat.gauntlet) {
    for (final engine in engines) {
      if (engine.engineId == referenceEngineId) continue;
      pairings.add([referenceEngineId!, engine.engineId]);
    }
  } else {
    for (var i = 0; i < engines.length; i++) {
      for (var j = i + 1; j < engines.length; j++) {
        pairings.add([engines[i].engineId, engines[j].engineId]);
      }
    }
  }

  var perPairing = math.max(1, config.gamesPerPairing);
  if (config.balanceColors && perPairing.isOdd) {
    // One more game so each engine plays White the same number of times.
    perPairing += 1;
  }

  final games = <PlannedGame>[];
  // Warm-ups first: they exist to warm caches, so they must run before the
  // games that count.
  for (var i = 0; i < config.warmUpGames && pairings.isNotEmpty; i++) {
    final pairing = pairings[i % pairings.length];
    games.add(PlannedGame(
      index: 0,
      whiteId: pairing[0],
      blackId: pairing[1],
      pairingIndex: i % pairings.length,
      isWarmUp: true,
    ));
  }

  var index = 0;
  final warnings = <String>[];
  var capped = false;
  for (var p = 0; p < pairings.length; p++) {
    for (var g = 0; g < perPairing; g++) {
      if (config.maxGames != null && index >= config.maxGames!) {
        capped = true;
        break;
      }
      // Alternate colours; odd game numbers swap the pairing.
      final swapped = config.balanceColors && g.isOdd;
      final white = swapped ? pairings[p][1] : pairings[p][0];
      final black = swapped ? pairings[p][0] : pairings[p][1];
      index++;
      games.add(PlannedGame(
        index: index,
        whiteId: white,
        blackId: black,
        pairingIndex: p,
      ));
    }
    if (capped) break;
  }

  if (capped) {
    warnings.add('The game cap (${config.maxGames}) was reached before every '
        'pairing finished, so some pairings play fewer games than requested. '
        'Ratings are still fitted over what was played; the report lists the '
        'shortfall.');
  }
  if (config.balanceColors) {
    // Verify the promise the config makes.
    for (final engine in engines) {
      final whites = games
          .where((g) => !g.isWarmUp && g.whiteId == engine.engineId)
          .length;
      final blacks = games
          .where((g) => !g.isWarmUp && g.blackId == engine.engineId)
          .length;
      if (whites != blacks) {
        warnings.add('${engine.label} is scheduled ${whites} time(s) as White '
            'and ${blacks} time(s) as Black; the game cap cut the last pairing '
            'before its colour swap.');
      }
    }
  }
  if (openingSuite.isEmpty) {
    warnings.add('The opening suite "${config.openingSuiteId}" is empty; every '
        'game starts from the initial position.');
  }

  return BenchmarkPlan(
    config: config,
    format: format,
    engines: engines,
    suite: openingSuite,
    games: games,
    referenceEngineId: referenceEngineId,
    warnings: warnings,
  );
}

/// The opening for a planned game.
Opening openingForGame(BenchmarkPlan plan, PlannedGame game) =>
    plan.suite.openingFor(
      seed: plan.config.seed,
      pairingIndex: game.pairingIndex,
      gameIndex: game.index,
    );
