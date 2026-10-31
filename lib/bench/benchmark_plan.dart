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

  /// Which game of [pairingIndex] this is (0-based, before repetitions).
  ///
  /// The opening is chosen from this, not from [index]: the two colour-swapped
  /// games of a pairing are games 0 and 1, so they share one opening and the
  /// comparison measures engines instead of book luck.
  final int gameInPairing;

  /// Which whole-run repetition this belongs to (0-based). Each repetition
  /// replays the schedule with its own seed.
  final int repetition;

  final bool isWarmUp;

  const PlannedGame({
    required this.index,
    required this.whiteId,
    required this.blackId,
    required this.pairingIndex,
    this.gameInPairing = 0,
    this.repetition = 0,
    this.isWarmUp = false,
  });

  /// Key of the opening this game uses. Two games share a key exactly when
  /// they are the same opening, which is what makes "the colour-swapped pair
  /// used the same opening" checkable.
  String get openingKey => '$repetition/$pairingIndex/${gameInPairing ~/ 2}';
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
              'gameInPairing': game.gameInPairing,
              'repetition': game.repetition,
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

  final perPairing = effectiveGamesPerPairing(config);
  final repetitions = math.max(1, config.repetitions);
  final warmUps = effectiveWarmUpGames(config);
  final recordedCap = effectiveRecordedGameCap(config);

  final games = <PlannedGame>[];
  final warnings = <String>[];

  if (warmUps < config.warmUpGames) {
    warnings.add('The game cap of ${config.maxGames} covers warm-up games, so '
        '$warmUps of the ${config.warmUpGames} requested warm-up(s) are '
        'scheduled.');
  }

  // Warm-ups first: they exist to warm caches, so they must run before the
  // games that count. They are part of the same cap, so they are scheduled
  // before the cap is spent on recorded games.
  for (var i = 0; i < warmUps && pairings.isNotEmpty; i++) {
    final pairing = pairings[i % pairings.length];
    games.add(PlannedGame(
      index: 0,
      whiteId: pairing[0],
      blackId: pairing[1],
      pairingIndex: i % pairings.length,
      gameInPairing: 0,
      isWarmUp: true,
    ));
  }

  var index = 0;
  var capped = false;
  for (var repetition = 0; repetition < repetitions; repetition++) {
    if (capped) break;
    for (var p = 0; p < pairings.length; p++) {
      if (capped) break;
      for (var g = 0; g < perPairing; g++) {
        if (recordedCap != null && index >= recordedCap) {
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
          gameInPairing: g,
          repetition: repetition,
        ));
      }
    }
  }

  if (capped) {
    warnings.add('The game cap (${config.maxGames}) was reached before every '
        'pairing finished, so some pairings play fewer games than requested. '
        'Ratings are still fitted over what was played; the report lists the '
        'shortfall.');
  }
  if (repetitions > 1 && index < pairings.length * perPairing * repetitions) {
    warnings.add('The game cap ended the run before all $repetitions '
        'repetitions were played; the report records how many were completed.');
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
  if (config.plyCap <= 0) {
    warnings.add('A ply cap of ${config.plyCap} adjudicates immediately; no '
        'game can produce a result.');
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
///
/// [PlannedGame.gameInPairing] is 0-based *within* the pairing, so the two
/// colour-swapped games of a pairing (ordinals 0 and 1) resolve to the same
/// opening, and the next pair of games (2 and 3) to the next one. Passing the
/// run-wide 1-based index here — which is what the first version did — made
/// every colour-swapped pair use two different openings and confounded colour
/// with opening in the fit.
Opening openingForGame(BenchmarkPlan plan, PlannedGame game) =>
    plan.suite.openingFor(
      seed: plan.config.seedForRepetition(game.repetition),
      pairingIndex: game.pairingIndex,
      gameIndex: game.gameInPairing,
    );
