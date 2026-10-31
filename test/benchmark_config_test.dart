// Configuration validation and the time estimate shown before a run starts.
//
// Two things matter here beyond "it compiles": a configuration that would
// produce a meaningless number is refused before the user spends an hour on
// it, and the estimate is honest about the worst case rather than quoting the
// optimistic one.
import 'package:crispchess/bench/benchmark_config.dart';
import 'package:flutter_test/flutter_test.dart';

BenchmarkConfig _custom({
  Duration timePerMove = const Duration(milliseconds: 100),
  int? searchDepth,
  int gamesPerPairing = 4,
  int? maxGames,
  Duration? maxDuration,
  int plyCap = 200,
  String openingSuiteId = 'balanced-8',
  int seed = 1,
  bool balanceColors = true,
}) =>
    BenchmarkConfig(
      preset: BenchmarkPreset.custom,
      timePerMove: timePerMove,
      searchDepth: searchDepth,
      gamesPerPairing: gamesPerPairing,
      maxGames: maxGames,
      maxDuration: maxDuration,
      plyCap: plyCap,
      openingSuiteId: openingSuiteId,
      seed: seed,
      balanceColors: balanceColors,
      adaptiveStopping: false,
    );

void main() {
  group('validation refuses what cannot be measured', () {
    test('a benchmark needs two engines', () {
      final result = validateConfig(_custom(), engineCount: 1);
      expect(result.isValid, isFalse);
      expect(result.errors.join(' '), contains('two engines'));
    });

    test('a sensible configuration passes', () {
      final result = validateConfig(_custom(), engineCount: 2);
      expect(result.isValid, isTrue, reason: result.errors.join(' '));
    });

    test('a move budget below 10 ms is refused', () {
      final result = validateConfig(
        _custom(timePerMove: const Duration(milliseconds: 5)),
        engineCount: 2,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.join(' '), contains('10 ms'));
    });

    test('a fixed depth is accepted but warned about', () {
      final result = validateConfig(_custom(searchDepth: 12), engineCount: 2);
      expect(result.isValid, isTrue);
      expect(result.warnings.join(' '), contains('depth'));
    });

    test('a ply cap that would adjudicate everything is refused', () {
      final result = validateConfig(_custom(plyCap: 4), engineCount: 2);
      expect(result.isValid, isFalse);
    });

    test('one-sided play is allowed but warned about', () {
      final result = validateConfig(
        _custom(balanceColors: false),
        engineCount: 2,
      );
      expect(result.isValid, isTrue);
      expect(result.warnings, isNotEmpty);
    });

    test('an odd number of games per pairing is rounded, not silently split',
        () {
      final result = validateConfig(_custom(gamesPerPairing: 3), engineCount: 2);
      expect(result.isValid, isTrue);
      expect(result.warnings.join(' '), contains('colour'));
    });
  });

  group('the estimate', () {
    test('a capped run does not estimate more games than it can play', () {
      final config = _custom(gamesPerPairing: 20, maxGames: 10);
      final estimate = estimateWorkload(config, engineCount: 3, pairings: 3);
      expect(estimate.scoredGames, lessThanOrEqualTo(10));
      expect(estimate.plannedGames, greaterThan(10));
    });

    test('the worst case is longer than the estimate', () {
      final estimate = estimateWorkload(
        _custom(gamesPerPairing: 4, plyCap: 300),
        engineCount: 2,
        pairings: 1,
      );
      expect(estimate.worstCase, greaterThan(estimate.estimated));
    });

    test('more games never estimate less time', () {
      final small = estimateWorkload(
        _custom(gamesPerPairing: 2),
        engineCount: 2,
        pairings: 1,
      );
      final large = estimateWorkload(
        _custom(gamesPerPairing: 8),
        engineCount: 2,
        pairings: 1,
      );
      expect(large.estimated, greaterThanOrEqualTo(small.estimated));
    });
  });

  group('presets', () {
    test('the presets are ordered by how much they cost', () {
      expect(BenchmarkConfig.quick.timePerMove,
          lessThan(BenchmarkConfig.standard.timePerMove));
      expect(BenchmarkConfig.standard.timePerMove,
          lessThan(BenchmarkConfig.accurate.timePerMove));
      expect(BenchmarkConfig.quick.gamesPerPairing,
          lessThanOrEqualTo(BenchmarkConfig.standard.gamesPerPairing));
      expect(BenchmarkConfig.standard.gamesPerPairing,
          lessThanOrEqualTo(BenchmarkConfig.accurate.gamesPerPairing));
    });

    test('every preset validates for a two-engine run', () {
      for (final preset in [
        BenchmarkConfig.quick,
        BenchmarkConfig.standard,
        BenchmarkConfig.accurate,
      ]) {
        final result = validateConfig(preset, engineCount: 2);
        expect(result.isValid, isTrue,
            reason: '${preset.preset.id}: ${result.errors.join(' ')}');
      }
    });

    test('a preset survives a JSON round trip', () {
      final restored = BenchmarkConfig.fromJson(BenchmarkConfig.standard.toJson());
      expect(restored.preset, BenchmarkConfig.standard.preset);
      expect(restored.gamesPerPairing, BenchmarkConfig.standard.gamesPerPairing);
      expect(restored.timePerMove, BenchmarkConfig.standard.timePerMove);
      expect(restored.openingSuiteId,
          BenchmarkConfig.standard.openingSuiteId);
    });

    test('requested options only name what was actually asked for', () {
      final config = _custom().copyWith(
        threads: 4,
        hashMb: 512,
        optionOverrides: const {'UCI_ShowWDL': 'true'},
      );
      final options = config.requestedOptions();
      expect(options['Threads'], '4');
      expect(options['Hash'], '512');
      expect(options['UCI_ShowWDL'], 'true');
      // Zero means "leave the engine alone", not "set it to zero".
      expect(_custom().requestedOptions(), isEmpty);
    });
  });
}
