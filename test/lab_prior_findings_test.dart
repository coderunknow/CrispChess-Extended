import 'dart:convert';
import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gauntlet validation uses actual pairing count', () {
    final config = BenchmarkConfig.quick.copyWith(gamesPerPairing: 2, maxGames: () => 8);
    expect(validateConfig(config, engineCount: 5, pairings: 4).warnings, isEmpty);
  });
  test('non-finite uncertainty survives JSON export', () {
    const rating = EloRating(engineId: 'x', label: 'x', rating: 0,
      stdErr: double.infinity, ciLow: double.negativeInfinity,
      ciHigh: double.infinity, games: 0);
    final json = jsonDecode(jsonEncode(rating.toJson())) as Map<String, dynamic>;
    expect(json['stdErr'], isNull);
    expect(EloRating.fromJson(json).stdErr, double.infinity);
  });
}
