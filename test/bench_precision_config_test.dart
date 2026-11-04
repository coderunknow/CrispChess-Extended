/// Precision objectives and resource budgets survive storage, and their
/// validation is real rather than decorative.
library;

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/precision.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults are 95% and ±20 Elo without forcing them', () {
    const settings = PrecisionSettings();
    expect(settings.confidenceLevel, 0.95);
    expect(settings.individualToleranceElo, 20);
    expect(settings.pairwiseToleranceElo, 20);
    expect(settings.objective, PrecisionObjective.both);
    expect(settings.validationErrors(), isEmpty);
  });

  test('invalid values are rejected with a reason', () {
    const settings = PrecisionSettings(
      confidenceLevel: 1.5,
      individualToleranceElo: 0,
      pairwiseToleranceElo: 5000,
    );
    expect(settings.validationErrors().length, 3);
    expect(
      validateConfig(BenchmarkConfig.standard.copyWith(
        precision: settings,
      ), engineCount: 2).isValid,
      isFalse,
    );
  });

  test('round-trips through JSON, including resource budgets', () {
    const settings = PrecisionSettings(
      objective: PrecisionObjective.pairwise,
      confidenceLevel: 0.9,
      individualToleranceElo: 12,
      pairwiseToleranceElo: 35,
      pairwiseScope: PairwiseIntervalScope.simultaneous,
      comparisonSet: PairwiseComparisonSet.targetPairs,
    );
    const budget = ResourceBudget(maxEngineMillis: 60000, maxMemoryMb: 512);
    final restored = PrecisionSettings.fromJson(settings.toJson());
    expect(restored.objective, PrecisionObjective.pairwise);
    expect(restored.pairwiseScope, PairwiseIntervalScope.simultaneous);
    expect(restored.comparisonSet, PairwiseComparisonSet.targetPairs);
    expect(restored.pairwiseToleranceElo, 35);
    final budget2 = ResourceBudget.fromJson(budget.toJson());
    expect(budget2.maxEngineMillis, 60000);
    expect(budget2.maxMemoryMb, 512);
    expect(budget2.maxGpuMillis, isNull);
  });

  test('older documents load with the defaults', () {
    final settings = PrecisionSettings.fromJson(const {});
    expect(settings.objective, PrecisionObjective.both);
    expect(settings.confidenceLevel, 0.95);
  });

  test('objective selects which tolerances are validated', () {
    const individualOnly = PrecisionSettings(
      objective: PrecisionObjective.individual,
      pairwiseToleranceElo: -5,
    );
    expect(individualOnly.validationErrors(), isEmpty);
    expect(individualOnly.wantsPairwise, isFalse);
  });

  test('a stored run keeps its precision objective and interval provenance', () {
    final config = BenchmarkConfig.standard.copyWith(
      precision: const PrecisionSettings(confidenceLevel: 0.9),
    );
    final restored = BenchmarkConfig.fromJson(config.toJson());
    expect(restored.precision.confidenceLevel, 0.9);
    expect(restored.precision.summary, contains('90%'));
  });

  test('the Fisher diagnostic is labelled, never called a cluster interval', () {
    expect(const PrecisionSettings().summary,
        allOf(contains('individual'), contains('pairwise')));
    expect(
      const PrecisionSettings(objective: PrecisionObjective.individual).summary,
      isNot(contains('pairwise')),
    );
  });

  test('run summaries only claim comparability inside one cohort', () {
    BenchmarkRunSummary summary(List<String> cohorts, List<String> ids) =>
        BenchmarkRunSummary(
          id: 'r', startedAt: DateTime(2026), finishedAt: DateTime(2026),
          engineLabels: ids, engineIds: ids, preset: 'standard',
          gamesPlayed: 10, ratedGames: 10, forfeits: 0, aborted: 0,
          stopReason: 'completed', cohortKeys: cohorts,
        );
    expect(summary(['linux/x64'], ['a', 'b']).comparableWith(summary(['linux/x64'], ['b'])), isTrue);
    expect(summary(['linux/x64'], ['a', 'b']).comparableWith(summary(['linux/x64', 'web'], ['b'])), isFalse);
    expect(summary(['linux/x64'], ['a']).comparableWith(summary(['linux/x64'], ['c'])), isFalse);
  });
}
