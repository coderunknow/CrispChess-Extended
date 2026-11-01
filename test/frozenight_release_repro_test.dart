// Opt-in release-layout reproduction; never presented as a passing unit test
// when the native runtime was not supplied. The workflow supplies the extracted
// archive directory on PATH and CRISP_FROZENIGHT_EXPECT=missing or ready.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_registry.dart';
import 'package:crispchess/services/engine_match_service.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expected = Platform.environment['CRISP_FROZENIGHT_EXPECT'];
  test('real Frozenight through gameplay, all Lab presets, and Match', () async {
    final missing = expected == 'missing';
    final builtIn = createEngineForId('builtin:Built-in', profiles: const []);
    addTearDown(builtIn.dispose);
    await builtIn.initialize();
    expect(builtIn.state, EngineState.ready);

    final engine = createEngineForId('builtin:Frozenight', profiles: const []);
    final states = <String>[];
    engine.stateNotifier.addListener(() => states.add(engine.state.name));
    Object? original;
    final watch = Stopwatch()..start();
    try {
      await engine.initialize().timeout(const Duration(seconds: 30));
    } catch (error) {
      original = error;
    }
    final report = <String, Object?>{
      'experiment': 'A ordinary gameplay initialization',
      'instance': identityHashCode(engine),
      'expected': expected,
      'state': engine.state.name,
      'states': states,
      'original': original?.toString(),
      'micros': watch.elapsedMicroseconds,
    };
    // ignore: avoid_print
    print('FROZENIGHT_EVIDENCE ${jsonEncode(report)}');
    expect(engine.state, missing ? EngineState.error : EngineState.ready);
    if (missing) {
      // Baseline defect: the old initializer hides the original loader error.
      expect(original, isNull);
      engine.dispose();
      return;
    }
    final move = await engine.bestMove('position startpos', depth: 2);
    expect(move, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    engine.dispose();

    final service = EngineService(
      createEngineForId('builtin:Frozenight', profiles: const []),
    )..useOpeningBook = false;
    expect(await service.initialize(), isTrue);
    final serviceMove = Completer<String>();
    final subscription = service.events.listen((event) {
      if (event is BestMoveEvent && !serviceMove.isCompleted) {
        serviceMove.complete(event.move);
      }
    });
    await service.requestMove('position startpos', depth: 2);
    expect(await serviceMove.future.timeout(const Duration(seconds: 30)),
        matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
    await subscription.cancel();
    service.dispose();

    for (final preset in BenchmarkPreset.values) {
      final frozenight = createEngineForId('builtin:Frozenight', profiles: const []);
      final opponent = createEngineForId('builtin:Built-in', profiles: const []);
      final a = EngineIdentity.forBuiltIn(name: 'Frozenight', engineVersion: frozenight.version, appBuild: 'release-probe');
      final b = EngineIdentity.forBuiltIn(name: 'Built-in', engineVersion: opponent.version, appBuild: 'release-probe');
      // Retain each actual preset and budget; bound only the tournament size.
      final config = BenchmarkConfig.forPreset(preset).copyWith(
        gamesPerPairing: 2, warmUpGames: 0, maxGames: () => 2,
        adaptiveStopping: false, plyCap: 40,
      );
      final runner = BenchmarkRunner(
        plan: buildPlan(config: config, engines: [a, b]),
        slots: {
          a.engineId: BenchEngineSlot(identity: a, build: () => frozenight),
          b.engineId: BenchEngineSlot(identity: b, build: () => opponent),
        },
        environment: BenchmarkEnvironment.capture(appVersion: 'release-probe'),
      );
      final run = await runner.run().timeout(const Duration(minutes: 2));
      await runner.dispose();
      // ignore: avoid_print
      print('FROZENIGHT_EVIDENCE ${jsonEncode({
        'experiment': 'B Engine Lab', 'preset': preset.name,
        'stopReason': run.stopReason,
        'status': run.engineStatus.map((k, v) => MapEntry(k, v.toJson())),
        'games': run.games.length,
        'plies': run.games.map((g) => g.moves.length).toList(),
        'outcomes': run.games.map((g) => g.outcome.id).toList(),
      })}');
      expect(run.stopReason, 'completed');
      expect(run.games.length, 2);
      expect(run.games.every((g) => g.moves.isNotEmpty), isTrue);
      expect(frozenight.state, EngineState.disposed);
      expect(opponent.state, EngineState.disposed);
    }

    final match = EngineMatchService(
      engine1: createEngineForId('builtin:Frozenight', profiles: const []),
      engine2: createEngineForId('builtin:Built-in', profiles: const []),
      config: const MatchConfig(numGames: 1, depthPerMove: 2, plyCap: 40),
    );
    final results = await match.run().timeout(const Duration(minutes: 1));
    // ignore: avoid_print
    print('FROZENIGHT_EVIDENCE ${jsonEncode({
      'experiment': 'C engine-vs-engine Match',
      'results': results.map((r) => {'outcome': r.outcome.id, 'moves': r.moves, 'detail': r.detail}).toList(),
    })}');
    expect(results.single.moves, greaterThan(0));
    expect(results.single.outcome, isNot(GameOutcome.forfeit));
    match.engine1.dispose();
    match.engine2.dispose();
    match.dispose();
  }, skip: expected == null ? 'Opt-in: requires an actual extracted runtime on PATH' : false,
      timeout: const Timeout(Duration(minutes: 10)));
}
