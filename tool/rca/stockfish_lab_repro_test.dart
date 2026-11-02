// Root-cause reproduction for "Stockfish 16: failed — Bad state: initialize
// returned with state error".
//
// Copied into a checkout of either the dev3 baseline (5ee20cd) or the dev4
// candidate by .github/workflows/stockfish-rca.yml and run there with
// `flutter test`. It drives the real Engine Lab runner with the real built-in
// Stockfish adapter and the built-in Dart engine on a machine where no
// Stockfish executable is installed (the state of every desktop release:
// Stockfish is GPL and is not bundled), and writes what the Lab recorded to
// rca-result.json. RCA_EXPECT selects the assertion:
//
//   baseline  — the Lab reports the bare contract violation (the bug).
//   candidate — the Lab reports a structured runtimeMissing failure.
//
// Only the public bench API that exists in both trees is used.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/stockfish_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Engine Lab with the built-in Stockfish and no Stockfish installed',
      () async {
    final expectation = Platform.environment['RCA_EXPECT'] ?? 'candidate';
    final stockfish = EngineIdentity.forBuiltIn(
        name: 'Stockfish', engineVersion: '16', appBuild: 'rca');
    final dart = EngineIdentity.forBuiltIn(
        name: 'Built-in', engineVersion: '1', appBuild: 'rca');
    final plan = buildPlan(
      config: const BenchmarkConfig(
        preset: BenchmarkPreset.custom,
        timePerMove: Duration(milliseconds: 20),
        gamesPerPairing: 2,
        plyCap: 40,
        openingSuiteId: 'startpos',
        seed: 7,
        warmUpGames: 0,
        repetitions: 1,
        adaptiveStopping: false,
      ),
      engines: [stockfish, dart],
    );
    final runner = BenchmarkRunner(
      plan: plan,
      slots: {
        stockfish.engineId:
            BenchEngineSlot(identity: stockfish, build: () => StockfishEngine()),
        dart.engineId: BenchEngineSlot(identity: dart, build: DartEngine.new),
      },
      environment: BenchmarkEnvironment.unknown,
    );
    final run = await runner.run();
    runner.dispose();
    final status = run.engineStatus[stockfish.engineId]!;
    final json = status.toJson();
    File('rca-result.json').writeAsStringSync(const JsonEncoder.withIndent('  ')
        .convert({
      'expect': expectation,
      'os': Platform.operatingSystem,
      'stockfish': json,
    }));
    expect(status.status, 'failed');
    final reason = status.reason ?? '';
    if (expectation == 'baseline') {
      expect(reason, contains('initialize returned with state error'));
    } else {
      expect(reason, isNot(contains('initialize returned with state')));
      expect((json['diagnostic'] as Map?)?['kind'], 'runtimeMissing');
      expect(reason, contains('Stockfish'));
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
