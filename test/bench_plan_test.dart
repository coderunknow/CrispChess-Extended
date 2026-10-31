// The schedule a benchmark will play, before it plays it.
//
// Every assertion here is about a promise the Lab makes on the confirmation
// dialog or in the report: the number of games, which colour each engine plays,
// that the two colour-swapped games of a pairing share one opening, that a
// repetition really is a second sample, and that a "max games" cap bounds the
// whole run rather than the part of it someone remembered to count.
import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/opening_suite.dart';
import 'package:flutter_test/flutter_test.dart';

EngineIdentity _identity(String name) => EngineIdentity.forBuiltIn(
      name: name,
      engineVersion: '1.0',
      appBuild: 'test',
    );

List<EngineIdentity> _engines(int count) =>
    [for (var i = 0; i < count; i++) _identity('E${i + 1}')];

BenchmarkConfig _config({
  int gamesPerPairing = 2,
  int? maxGames,
  int warmUpGames = 0,
  int repetitions = 1,
  int plyCap = 160,
  int seed = 20261031,
  bool balanceColors = true,
  String openingSuiteId = 'balanced-8',
}) =>
    BenchmarkConfig(
      preset: BenchmarkPreset.custom,
      timePerMove: const Duration(milliseconds: 50),
      gamesPerPairing: gamesPerPairing,
      maxGames: maxGames,
      plyCap: plyCap,
      openingSuiteId: openingSuiteId,
      seed: seed,
      warmUpGames: warmUpGames,
      balanceColors: balanceColors,
      repetitions: repetitions,
      adaptiveStopping: false,
    );

void main() {
  group('round robin', () {
    test('every pair plays, once per colour', () {
      final plan = buildPlan(config: _config(), engines: _engines(3));
      expect(plan.pairings, 3);
      expect(plan.totalGames, 6);
      for (final engine in plan.engines) {
        expect(plan.gamesFor(engine.engineId), 4);
        expect(plan.whiteGamesFor(engine.engineId), 2);
        expect(plan.blackGamesFor(engine.engineId), 2);
      }
    });

    test('an odd number of games per pairing is raised so colours balance', () {
      final plan = buildPlan(config: _config(gamesPerPairing: 3), engines: _engines(2));
      expect(plan.totalGames, 4);
      expect(plan.whiteGamesFor(plan.engines.first.engineId), 2);
    });

    test('unbalanced colours are left alone when the user asked for them', () {
      final plan = buildPlan(
        config: _config(gamesPerPairing: 3, balanceColors: false),
        engines: _engines(2),
      );
      expect(plan.totalGames, 3);
      expect(plan.warnings.any((w) => w.contains('White')), isFalse);
    });

    test('fewer than two engines cannot be scheduled', () {
      expect(() => buildPlan(config: _config(), engines: _engines(1)),
          throwsArgumentError);
    });

    test('the same engine twice is refused rather than silently merged', () {
      final engines = _engines(2);
      expect(
        () => buildPlan(config: _config(), engines: [engines.first, engines.first]),
        throwsArgumentError,
      );
    });
  });

  group('gauntlet', () {
    test('the reference plays every challenger', () {
      final engines = _engines(4);
      final plan = buildPlan(
        config: _config(),
        engines: engines,
        format: TournamentFormat.gauntlet,
        referenceEngineId: engines.first.engineId,
      );
      expect(plan.pairings, 3);
      expect(plan.totalGames, 6);
      expect(plan.gamesFor(engines.first.engineId), 6);
      expect(plan.gamesFor(engines[1].engineId), 2);
    });

    test('a gauntlet without a reference is refused', () {
      expect(
        () => buildPlan(
          config: _config(),
          engines: _engines(3),
          format: TournamentFormat.gauntlet,
        ),
        throwsArgumentError,
      );
    });

    test('a reference outside the run is refused', () {
      expect(
        () => buildPlan(
          config: _config(),
          engines: _engines(3),
          format: TournamentFormat.gauntlet,
          referenceEngineId: _identity('Not Selected').engineId,
        ),
        throwsArgumentError,
      );
    });
  });

  group('openings', () {
    test('the two colour-swapped games of a pairing share one opening', () {
      final plan = buildPlan(config: _config(), engines: _engines(3));
      final byPairing = <int, Set<String>>{};
      for (final game in plan.recordedGames) {
        byPairing.putIfAbsent(game.pairingIndex, () => <String>{})
          ..add(openingForGame(plan, game).id);
      }
      for (final entry in byPairing.entries) {
        expect(entry.value.length, 1,
            reason: 'pairing ${entry.key} played ${entry.value}');
      }
    });

    test('both colours of a pairing really face the same line', () {
      final plan = buildPlan(
        config: _config(gamesPerPairing: 2),
        engines: _engines(2),
      );
      final games = plan.recordedGames;
      expect(games.length, 2);
      expect(games[0].whiteId, isNot(games[1].whiteId));
      expect(openingForGame(plan, games[0]).moves,
          openingForGame(plan, games[1]).moves);
      expect(games[0].openingKey, games[1].openingKey);
    });

    test('a second repetition samples a different opening', () {
      final plan = buildPlan(
        config: _config(repetitions: 2),
        engines: _engines(2),
      );
      final first = plan.recordedGames.firstWhere((g) => g.repetition == 0);
      final second = plan.recordedGames.firstWhere((g) => g.repetition == 1);
      expect(openingForGame(plan, first).id,
          isNot(openingForGame(plan, second).id));
    });

    test('the suite is deterministic for one seed and moves with it', () {
      final suite = openingSuiteById('balanced-8');
      final a = suite.openingFor(seed: 11, pairingIndex: 0, gameIndex: 0);
      final b = suite.openingFor(seed: 11, pairingIndex: 0, gameIndex: 0);
      expect(a.id, b.id);
      // Not a hard guarantee for every pair of seeds, so this checks the
      // mechanism (the offset formula) rather than a coincidence: several seeds
      // must not all land on the same opening.
      final ids = {
        for (var seed = 0; seed < 8; seed++)
          suite.openingFor(seed: seed, pairingIndex: 0, gameIndex: 0).id
      };
      expect(ids.length, greaterThan(1));
    });

    test('a warm-up from the same pairing uses the first opening', () {
      final plan = buildPlan(
        config: _config(warmUpGames: 1),
        engines: _engines(2),
      );
      final warmUp = plan.games.firstWhere((g) => g.isWarmUp);
      final firstRecorded = plan.recordedGames.first;
      expect(openingForGame(plan, warmUp).id,
          openingForGame(plan, firstRecorded).id);
    });
  });

  group('repetitions', () {
    test('every repetition is scheduled, and counted once in the totals', () {
      final plan = buildPlan(
        config: _config(repetitions: 3),
        engines: _engines(2),
      );
      expect(plan.totalGames, 6);
      expect(plan.recordedGames.map((g) => g.repetition).toSet(), {0, 1, 2});
      // Game indexes stay unique, so a report can name one game.
      expect(plan.recordedGames.map((g) => g.index).toSet().length, 6);
    });

    test('the estimate counts repetitions too', () {
      final single = estimateWorkload(
        _config(repetitions: 1),
        engineCount: 2,
        pairings: 1,
      );
      final triple = estimateWorkload(
        _config(repetitions: 3),
        engineCount: 2,
        pairings: 1,
      );
      expect(triple.plannedGames, single.plannedGames * 3);
      expect(triple.estimated, greaterThan(single.estimated));
    });
  });

  group('the game cap', () {
    test('warm-ups are counted against the cap, not added to it', () {
      final plan = buildPlan(
        config: _config(maxGames: 2, warmUpGames: 20),
        engines: _engines(2),
      );
      expect(plan.games.length, 2);
      // Twenty warm-ups would leave nothing to measure, so the cap keeps two
      // games for evidence and no warm-ups at all.
      expect(plan.warmUpGames, 0);
      expect(plan.totalGames, 2);
    });

    test('the cap trims warm-ups before it trims evidence', () {
      final plan = buildPlan(
        config: _config(maxGames: 6, warmUpGames: 4, gamesPerPairing: 4),
        engines: _engines(2),
      );
      expect(plan.games.length, 6);
      expect(plan.warmUpGames, 4);
      expect(plan.totalGames, 2);
    });

    test('a cap that cuts the schedule says so', () {
      final plan = buildPlan(
        config: _config(maxGames: 3, gamesPerPairing: 4),
        engines: _engines(2),
      );
      expect(plan.games.length, 3);
      expect(plan.warnings.any((w) => w.contains('game cap')), isTrue);
      // Colour balance is broken by the cut, and that is reported rather than
      // silently claimed.
      expect(plan.warnings.any((w) => w.contains('as White')), isTrue);
    });

    test('no cap means the whole schedule plays', () {
      final plan = buildPlan(
        config: _config(gamesPerPairing: 6),
        engines: _engines(4),
      );
      expect(plan.totalGames, 6 * 6);
    });

    test('the estimate agrees with the plan for the same configuration', () {
      final config = _config(maxGames: 6, warmUpGames: 4, gamesPerPairing: 4);
      final plan = buildPlan(config: config, engines: _engines(2));
      final estimate = plan.estimate();
      expect(estimate.totalGames, plan.games.length);
      expect(estimate.warmUpGames, plan.warmUpGames);
      expect(estimate.scoredGames, plan.recordedGames.length);
      expect(estimate.worstCase, greaterThanOrEqualTo(estimate.estimated));
    });
  });

  group('estimate', () {
    test('the worst case is never shorter than the estimate', () {
      final estimate = estimateWorkload(_config(), engineCount: 3, pairings: 3);
      expect(estimate.worstCase.inMilliseconds,
          greaterThanOrEqualTo(estimate.estimated.inMilliseconds));
      expect(estimate.notes, isNotEmpty);
    });

    test('the cap shortens the estimate and is explained', () {
      final capped =
          estimateWorkload(_config(maxGames: 4), engineCount: 3, pairings: 3);
      final uncapped = estimateWorkload(
          _config(gamesPerPairing: 4), engineCount: 3, pairings: 3);
      expect(capped.scoredGames, 4);
      expect(uncapped.scoredGames, 12);
      expect(capped.notes.any((n) => n.contains('game cap')), isTrue);
    });

    test('a depth budget is flagged as an estimate', () {
      final estimate = estimateWorkload(
        _config().copyWith(searchDepth: () => 6),
        engineCount: 2,
        pairings: 1,
      );
      expect(estimate.notes.any((n) => n.contains('depth-based')), isTrue);
    });

    test('a wall-clock cap is mentioned', () {
      final estimate = estimateWorkload(
        _config().copyWith(maxDuration: () => const Duration(minutes: 5)),
        engineCount: 2,
        pairings: 1,
      );
      expect(estimate.notes.any((n) => n.contains('wall-clock')), isTrue);
    });
  });

  group('cap helpers', () {
    test('warm-ups never eat the last two games', () {
      expect(effectiveWarmUpGames(_config(maxGames: 2, warmUpGames: 10)), 0);
      expect(effectiveWarmUpGames(_config(maxGames: 3, warmUpGames: 10)), 1);
      expect(effectiveWarmUpGames(_config(maxGames: 10, warmUpGames: 3)), 3);
      expect(effectiveWarmUpGames(_config(warmUpGames: 3)), 3);
    });

    test('the recorded cap subtracts the warm-ups that remain', () {
      expect(effectiveRecordedGameCap(_config(maxGames: 10, warmUpGames: 3)), 7);
      expect(effectiveRecordedGameCap(_config()), isNull);
    });
  });

  group('validation', () {
    test('repetitions outside the supported range are refused', () {
      expect(validateConfig(_config(repetitions: 0), engineCount: 2).isValid,
          isFalse);
      expect(validateConfig(_config(repetitions: 51), engineCount: 2).isValid,
          isFalse);
    });

    test('a cap that cannot cover a round warns with the real numbers', () {
      final validation = validateConfig(
        _config(maxGames: 3, gamesPerPairing: 4),
        engineCount: 4,
      );
      expect(validation.warnings.any((w) => w.contains('game cap')), isTrue);
    });

    test('a cap below the warm-ups explains the trimming', () {
      final validation = validateConfig(
        _config(maxGames: 4, warmUpGames: 10),
        engineCount: 2,
      );
      expect(validation.warnings.any((w) => w.contains('warm-up')), isTrue);
    });
  });
}
