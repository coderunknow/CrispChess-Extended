// What leaves the app when someone exports a benchmark.
//
// Three things can go badly wrong in an export, and all three are silent:
//
//  * a spreadsheet *executes* a cell that starts with `=`, `+`, `-`, `@`, a tab
//    or a carriage return — and engine names, opening names and error messages
//    are all text from outside the app;
//  * a report that prints a bare number under "Elo" claims a calibrated rating
//    the run never had;
//  * a game that was forfeited, adjudicated or aborted must not be printed with
//    a result it did not earn.
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

void main() {
  group('CSV', () {
    test('a game row per played game, warm-ups excluded', () async {
      final result = await runScriptedBenchmark(
        config: benchConfig(warmUpGames: 1),
      );
      await result.runner.dispose();
      final csv = result.run.gamesCsv();
      final lines = csv.trim().split('\n');
      expect(lines.first.split(','), contains('white_id'));
      expect(lines.length - 1, result.run.games.where((g) => !g.warmUp).length);
    });

    test('an engine that calls itself a formula cannot run one', () async {
      // A UCI engine picks its own `id name`, so this string is attacker
      // controlled in the sense that matters: it comes from another process.
      final result = await runScriptedBenchmark(alphaName: '=cmd|\'/c calc\'!A1');
      await result.runner.dispose();

      for (final csv in [
        result.run.gamesCsv(),
        result.run.enginesCsv(),
      ]) {
        expect(csv.contains(',=cmd'), isFalse,
            reason: 'an unescaped formula cell is executable');
        expect(csv.contains("'=cmd"), isTrue,
            reason: 'the cell must be kept readable but inert');
      }
    });

    test('every spreadsheet trigger is neutralised', () async {
      for (final trigger in ['=', '+', '-', '@', '\t', '\r']) {
        final run = (await runScriptedBenchmark(alphaName: '${trigger}SUM(A1)'))
            .run;
        expect(run.enginesCsv(), contains("'$trigger"),
            reason: 'trigger "${trigger.codeUnitAt(0)}"');
      }
    });

    test('commas and quotes are quoted the CSV way', () async {
      final run = (await runScriptedBenchmark(alphaName: 'Alpha, "the" one')).run;
      final csv = run.enginesCsv();
      // The label the report prints is the display name plus the version.
      expect(csv, contains('"Alpha, ""the"" one 1.0"'));
    });

    test('the relative rating column is named as relative', () async {
      final run = (await runScriptedBenchmark()).run;
      final header = run.enginesCsv().split('\n').first.split(',');
      expect(header, contains('relative_elo'));
      expect(header, isNot(contains('elo')));
    });
  });

  group('markdown', () {
    test('the standings say the rating is relative, not absolute', () async {
      final result = await runScriptedBenchmark();
      await result.runner.dispose();
      final report = result.run.reportMarkdown();
      expect(report, contains('| Relative rating |'));
      expect(report.toLowerCase(), contains('relative'));
      // The anchor is stated, so a reader knows what the numbers are relative to.
      expect(report, contains('${result.run.ratings.anchor.toStringAsFixed(0)}'));
      expect(report, isNot(contains('| Elo rating |')));
    });

    test('the report records how the run was produced', () async {
      final run = (await runScriptedBenchmark()).run;
      final report = run.reportMarkdown();
      expect(report, contains('- Stopped because: ${run.stopReason}'));
      expect(report, contains('- Platform:'));
      expect(report, contains('- Configuration:'));
      expect(report, contains(run.config.openingSuiteId));
    });

    test('a pipe in a label does not break the table', () async {
      final run =
          (await runScriptedBenchmark(alphaName: 'Alpha|Beta')).run;
      final report = run.reportMarkdown();
      expect(report, contains(r'Alpha\|Beta'));
      // The escaped pipe is still a character in the line, so the check is that
      // every standings row matches the header's column count plus the escaped
      // pipes in the labels it prints.
      final lines = report.split('\n');
      final header =
          lines.firstWhere((line) => line.startsWith('| # | Engine |'));
      final columns = '|'.allMatches(header).length;
      final rows = lines.where((line) =>
          line.startsWith('| 1 |') || line.startsWith('| 2 |'));
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect('|'.allMatches(row).length, columns + 1, reason: row);
      }
    });
  });

  group('PGN', () {
    test('a decided game has its result and both players', () async {
      final result = await runScriptedBenchmark();
      await result.runner.dispose();
      final pgn = result.run.pgn();
      expect(pgn, contains('[Result "1-0"]'));
      expect(pgn, contains('[White "Alpha 1.0"]'));
      expect(pgn, contains('[Black "Beta 1.0"]'));
    });

    test('a game without a result is not given one', () async {
      final run = (await runScriptedBenchmark(
        config: benchConfig(plyCap: 4),
      ))
          .run;
      expect(run.games.every((g) => g.outcome == GameOutcome.adjudicated),
          isTrue);
      expect(run.pgn(), contains('[Result "*"]'));
      expect(run.pgn(), isNot(contains('1/2-1/2')));
    });
  });

  group('JSON', () {
    test('a run survives a round trip through its own JSON', () async {
      final run = (await runScriptedBenchmark()).run;
      final restored = BenchmarkRun.fromJson(run.toJson());
      expect(restored.id, run.id);
      expect(restored.games.length, run.games.length);
      expect(restored.games.first.outcome, run.games.first.outcome);
      expect(restored.ratings.ratings.length, run.ratings.ratings.length);
      expect(restored.config.seed, run.config.seed);
      expect(restored.stopReason, run.stopReason);
    });

    test('an aborted game does not turn into a draw on the way out', () async {
      final alpha = ScriptedEngine('Alpha')
        ..initFailure = StateError('no binary');
      final result = await runScriptedBenchmark(alpha: alpha);
      await result.runner.dispose();

      expect(result.run.games.first.outcome, GameOutcome.aborted);
      final restored = BenchmarkRun.fromJson(result.run.toJson());
      expect(restored.games.first.outcome, GameOutcome.aborted);
      expect(restored.games.first.outcome.pgnResult, '*');
    });
  });
}
