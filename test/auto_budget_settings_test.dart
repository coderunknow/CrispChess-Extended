import 'package:crispchess/bench/benchmark_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored automatic budgets are clamped to the effective run caps', () {
    final settings = AutoBenchmarkSettings.fromJson({
      'maxGames': 400,
      'maxDurationMinutes': 240,
    });
    expect(settings.maxGames, 24);
    expect(settings.maxDuration, const Duration(minutes: 10));
  });

  test('invalid automatic budgets keep the safe defaults', () {
    final settings = AutoBenchmarkSettings.fromJson({
      'maxGames': 'lots',
      'maxDurationMinutes': null,
    });
    expect(settings.maxGames, 24);
    expect(settings.maxDuration, const Duration(minutes: 10));
  });
}
