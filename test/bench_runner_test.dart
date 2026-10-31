// What the runner does when things go wrong.
//
// The Engine Lab's honesty rests on this file: a game that was stopped, a game
// that timed out, a game where an engine crashed, and a run that was cancelled
// must all be recorded as what they were, and the two hard caps (games and
// wall-clock) must actually bound the run.
//
// The engines are scripted through `ChessEngine` (see support/bench_harness),
// not mocked at the service level: what is exercised is the runner's real event
// loop, the real game loop, the real forfeit classification and the real
// deadline timer.
import 'dart:async';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

BenchmarkConfig _config({
  int gamesPerPairing = 2,
  int repetitions = 1,
  int warmUpGames = 0,
  int plyCap = 200,
  Duration? maxDuration,
  int? maxGames,
}) =>
    benchConfig(
      gamesPerPairing: gamesPerPairing,
      repetitions: repetitions,
      warmUpGames: warmUpGames,
      plyCap: plyCap,
      maxDuration: maxDuration,
      maxGames: maxGames,
    );

BenchmarkRunner _runner(
  BenchmarkConfig config, {
  required ScriptedEngine white,
  required ScriptedEngine black,
}) {
  final identities = [testIdentity('Alpha'), testIdentity('Beta')];
  final plan = buildPlan(config: config, engines: identities);
  return BenchmarkRunner(
    plan: plan,
    slots: {
      identities[0].engineId:
          BenchEngineSlot(identity: identities[0], build: () => white),
      identities[1].engineId:
          BenchEngineSlot(identity: identities[1], build: () => black),
    },
    environment: BenchmarkEnvironment.unknown,
  );
}

void main() {
  group('a normal run', () {
    test('deadline-induced search errors are aborted, not forfeits', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      alpha.ask = (_, __) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        throw StateError('search stopped');
      };
      final runner = _runner(_config(maxDuration: const Duration(milliseconds: 40)),
          white: alpha, black: beta);
      addTearDown(runner.dispose);
      final run = await runner.run();
      expect(run.stopReason, 'time cap');
      expect(run.games.single.outcome, GameOutcome.aborted);
      expect(run.ratings.ratedGames, 0);
    });

    test('plays the schedule, fits ratings and releases both engines',
        () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(run.games.length, 2);
      expect(run.stopReason, 'completed');
      expect(run.engines.length, 2);
      // Both games reach mate, so both are results and both are in the fit.
      expect(run.games.every((g) => g.outcome.isRatingEligible), isTrue);
      expect(run.ratings.ratings.length, 2);
      expect(run.engineStatus.values.every((s) => s.status == 'completed'),
          isTrue);
      expect(alpha.disposed, isTrue);
      expect(beta.disposed, isTrue);
    });

    test('each colour wins one game, so the fit is centred', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(run.games.map((g) => g.outcome).toSet(), {GameOutcome.whiteWin});
      for (final rating in run.ratings.ratings) {
        // One win each from two games: the relative difference is about zero.
        expect(rating.rating, closeTo(run.ratings.anchor, 20));
      }
    });

    test('applies the options the engine advertises, and records them',
        () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config().copyWith(threads: 2, hashMb: 64),
          white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(alpha.appliedOptions['Threads'], '2');
      expect(alpha.appliedOptions['Hash'], '64');
      expect(run.engines.first.configuration, containsPair('Threads', '2'));
    });

    test('a warm-up game is played but never rated', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(warmUpGames: 1), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(run.games.where((g) => g.warmUp).length, 1);
      expect(run.gamesPlayed, 2, reason: 'warm-ups are not counted as games');
      expect(run.gamesCompleted, 2);
    });

    test('a repetition is a second sample of the schedule', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(repetitions: 2), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();
      expect(run.games.length, 4);
    });
  });

  group('failed initialisation', () {
    test('is recorded, not thrown, and its games are aborted', () async {
      final alpha = ScriptedEngine('Alpha')
        ..initFailure = StateError('no such binary');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(run.engineStatus[run.engines.first.engineId]?.status, 'failed');
      expect(run.games.every((g) => g.outcome == GameOutcome.aborted), isTrue);
      expect(run.games.every((g) => !g.outcome.isRatingEligible), isTrue);
      expect(run.ratings.ratings, isEmpty);
      expect(run.stopReason, isNot('completed'));
    });

    test('cancellation during one handshake does not start the next engine',
        () async {
      final alpha = ScriptedEngine('Alpha')..initGate = Completer<void>();
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);

      final future = runner.run();
      // Let the first handshake start, then cancel while it is pending.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      runner.cancel();
      alpha.initGate!.complete();
      final run = await future;
      await runner.dispose();

      expect(beta.initialised, isEmpty,
          reason: 'the second engine must not start after a cancellation');
      expect(run.stopReason, 'cancelled');
    });
  });

  group('cancellation', () {
    test('stops the run between games and keeps the games already played',
        () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(gamesPerPairing: 8), white: alpha, black: beta);

      final firstGame = Completer<void>();
      final subscription = runner.events.listen((event) {
        if (event is BenchmarkGameFinishedEvent && !firstGame.isCompleted) {
          firstGame.complete();
        }
      });
      final future = runner.run();
      await firstGame.future;
      runner.cancel();
      final run = await future;
      await subscription.cancel();
      await runner.dispose();

      expect(run.stopReason, 'cancelled');
      expect(run.gamesPlayed, greaterThanOrEqualTo(1));
      expect(run.gamesPlayed, lessThan(8));
    });

    test('a cancelled game is recorded as cancelled and is not rated',
        () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);

      var moves = 0;
      final subscription = runner.events.listen((event) {
        if (event is BenchmarkMoveEvent) {
          moves++;
          if (moves == 3) runner.cancel();
        }
      });
      final run = await runner.run();
      await subscription.cancel();
      await runner.dispose();

      expect(run.stopReason, 'cancelled');
      expect(run.games.last.outcome, GameOutcome.cancelled);
      expect(run.ratedGames.contains(run.games.last), isFalse,
          reason: 'a game stopped by the user is not a result');
    });
  });

  group('pause and resume', () {
    test('pausing before a game holds it until resume', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(gamesPerPairing: 2), white: alpha, black: beta);
      runner.pause();

      final future = runner.run();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(alpha.askedPositions, isEmpty,
          reason: 'a paused run must not start a game');
      expect(runner.isPaused, isTrue);

      runner.resume();
      final run = await future;
      await runner.dispose();
      expect(run.gamesPlayed, 2);
    });

    test('pausing during a game lets that game finish, then holds', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(gamesPerPairing: 4), white: alpha, black: beta);

      var paused = false;
      final subscription = runner.events.listen((event) {
        // Pause once: a listener that paused on every move would pause the run
        // again after the resume and deadlock the test.
        if (event is BenchmarkMoveEvent && !paused) {
          paused = true;
          runner.pause();
        }
      });
      final future = runner.run();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(runner.isPaused, isTrue);
      runner.resume();
      final run = await future;
      await subscription.cancel();
      await runner.dispose();
      expect(run.gamesPlayed, 4);
    });
  });

  group('game failures', () {
    test('an illegal move forfeits the game instead of ending the run',
        () async {
      final alpha = ScriptedEngine('Alpha')
        ..ask = (n, ply) async => n == 1 ? 'e2e5' : openingBookMove(ply)!;
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      final first = run.games.first;
      expect(first.outcome, GameOutcome.forfeit);
      expect(first.forfeitReason, ForfeitReason.illegalMove);
      expect(first.forfeitedBy, run.engines.first.engineId);
      // The other game is still played: one bad move is not a bad engine.
      expect(run.games.length, 2);
    });

    test('a timeout forfeits, and three in a row take the engine out',
        () async {
      final alpha = ScriptedEngine('Alpha')
        ..ask = (n, ply) async => throw TimeoutException('no bestmove');
      final beta = ScriptedEngine('Beta');
      final runner =
          _runner(_config(gamesPerPairing: 8), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      final forfeits =
          run.games.where((g) => g.outcome == GameOutcome.forfeit).toList();
      expect(forfeits.first.forfeitReason, ForfeitReason.timeOut);
      expect(forfeits.length, greaterThanOrEqualTo(3));
      expect(run.stopReason, 'engine failure');
      expect(run.engineStatus[run.engines.first.engineId]?.status, 'failed');
    });

    test('an engine that crashes forfeits with the crash as the reason',
        () async {
      final alpha = ScriptedEngine('Alpha')
        ..ask = (n, ply) async => throw EngineProcessDiedException('Alpha', 139, []);
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      final run = await runner.run();
      await runner.dispose();

      expect(run.games.first.forfeitReason, ForfeitReason.engineCrash);
    });

    test('an empty bestmove is a protocol failure, not a draw', () async {
      for (final answer in ['', '(none)', '0000']) {
        final alpha = ScriptedEngine('Alpha')..ask = (n, ply) async => answer;
        final beta = ScriptedEngine('Beta');
        final runner = _runner(_config(), white: alpha, black: beta);
        final run = await runner.run();
        await runner.dispose();
        expect(run.games.first.outcome, GameOutcome.forfeit,
            reason: 'answer "$answer"');
        expect(run.games.first.forfeitReason, ForfeitReason.noMoveReturned);
      }
    });

    test('a forfeiting engine is drained before the next game', () async {
      final alpha = ScriptedEngine('Alpha')
        ..ask = (n, ply) async => throw TimeoutException('no bestmove');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(_config(), white: alpha, black: beta);
      await runner.run();
      await runner.dispose();
      expect(alpha.drainCalls, greaterThan(0));
    });
  });

  group('the wall-clock cap', () {
    test('ends a game that is still searching, and that game is not rated',
        () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final gate = Completer<void>();
      alpha.stopGate = gate;
      alpha.ask = (n, ply) async {
        if (n == 2) {
          // The second search hangs until the runner stops the engine. The move
          // it finally returns is legal, so what ends the game is the cap and
          // not an illegal answer.
          await gate.future;
        }
        return openingBookMove(ply) ?? 'a7a6';
      };

      final runner = _runner(
        _config(
          gamesPerPairing: 4,
          maxDuration: const Duration(milliseconds: 150),
        ),
        white: alpha,
        black: beta,
      );
      final stopwatch = Stopwatch()..start();
      final run = await runner.run();
      stopwatch.stop();
      await runner.dispose();

      expect(run.stopReason, 'time cap');
      expect(alpha.stopCalls, greaterThan(0),
          reason: 'the deadline must stop an in-flight search');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      final aborted =
          run.games.where((g) => g.outcome == GameOutcome.aborted).toList();
      expect(aborted, isNotEmpty);
      for (final game in aborted) {
        expect(game.outcome.isRatingEligible, isFalse);
      }
    });

    test('a cap that expires between games stops the run', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(
        _config(
          gamesPerPairing: 6,
          maxDuration: const Duration(milliseconds: 1),
        ),
        white: alpha,
        black: beta,
      );
      final run = await runner.run();
      await runner.dispose();
      expect(run.stopReason, 'time cap');
    });
  });

  group('the game cap', () {
    test('the run never plays more than the cap, warm-ups included', () async {
      final alpha = ScriptedEngine('Alpha');
      final beta = ScriptedEngine('Beta');
      final runner = _runner(
        _config(gamesPerPairing: 8, warmUpGames: 3, maxGames: 5),
        white: alpha,
        black: beta,
      );
      final run = await runner.run();
      await runner.dispose();
      expect(run.games.length, lessThanOrEqualTo(5));
      expect(run.games.where((g) => g.warmUp).length, lessThanOrEqualTo(3));
    });
  });
}
