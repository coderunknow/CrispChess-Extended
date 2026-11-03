/// The service level of dev5: intelligent preparation, budgets, precision
/// validation and the export/document regressions fixed in this increment.
@TestOn('vm')
library;

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';

import 'package:crispchess/bench/precision.dart';
import 'package:crispchess/bench/calibration.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

BenchmarkConfig budgeted({
  int? maxGames = 40,
  double individual = 20,
  double pairwise = 20,
  PrecisionObjective objective = PrecisionObjective.both,
}) =>
    BenchmarkConfig.quick.copyWith(
      preset: BenchmarkPreset.custom,
      maxGames: () => maxGames,
      maxDuration: () => null,
      warmUpGames: 0,
      repetitions: 1,
      openingSuiteId: 'cluster-40',
      precision: PrecisionSettings(
        objective: objective,
        individualToleranceElo: individual,
        pairwiseToleranceElo: pairwise,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BenchmarkService service;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = BenchmarkService(
      store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
      profileStore: EngineProfileStore(),
    );
  });

  test('a run with no budget at all is refused before anything starts', () async {
    await expectLater(
      service.prepareIntelligent(
        targetIds: const ['builtin:Built-in'],
        config: BenchmarkConfig.standard.copyWith(
          maxGames: () => null,
          maxDuration: () => null,
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('an invalid precision objective is refused with its reason', () async {
    await expectLater(
      service.prepareIntelligent(
        targetIds: const ['builtin:Built-in'],
        config: budgeted().copyWith(
          precision: const PrecisionSettings(confidenceLevel: 2),
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('preparation separates targets, opponents and participants', () async {
    final available = (await service.candidates()).where((c) => c.available).toList();
    if (available.length < 2) return; // platform without runnable built-ins
    final target = available.first.engineId;
    final preparation = await service.prepareIntelligent(
      targetIds: [target],
      config: budgeted(),
    );
    expect(preparation.plan.format, TournamentFormat.intelligent);
    expect(preparation.plan.targetEngineIds, [target]);
    expect(preparation.plan.engines.length, greaterThanOrEqualTo(2));
    expect(preparation.plan.games, isNotEmpty);
    // The planner refuses to build an intelligent plan behind the scheduler's
    // back, so nothing can silently fall back to a fixed bracket.
    expect(
      () => buildPlan(
        config: preparation.config,
        engines: preparation.plan.engines,
        format: TournamentFormat.intelligent,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('the stored CSV has one header per value (duplicate std_err fixed)', () {
    const config = BenchmarkConfig.quick;
    final run = BenchmarkRun(
      id: 'r1', startedAt: DateTime(2026, 1, 1), finishedAt: DateTime(2026, 1, 1),
      config: config, format: TournamentFormat.roundRobin,
      engines: const [], engineStatus: const {}, games: const [],
      ratings: EloFit.empty,
      calibration: CalibrationOutcome.unavailable('none'),
      environment: BenchmarkEnvironment.unknown,
    );
    final header = run.gamesCsv().split('\n').first;
    final columns = header.split(',');
    expect(columns.toSet().length, columns.length,
        reason: 'no column may appear twice in the CSV header');
    expect(columns, contains('cluster_id'));
    expect(columns, contains('pair_id'));
  });
}
