import 'package:crispchess/bench/opening_suite.dart';
import 'package:crispchess/bench/benchmark_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('built-in opening suites are legal', () {
    for (final suite in [kBalancedSuite, kDiverseSuite, kStartPositionSuite]) {
      expect(suite.validationErrors(), isEmpty, reason: suite.id);
    }
  });
  test('illegal custom opening is rejected with its id and ply', () {
    const suite = OpeningSuite(id: 'bad', name: 'bad', description: '',
      openings: [Opening(id: 'bad-line', name: 'bad', category: 'test', moves: ['e2e5'])]);
    expect(suite.validationErrors().single, contains('bad-line: illegal move 1'));
  });
  test('suite length sharing seven does not repeat a subset', () {
    final suite = OpeningSuite(id: 'seven', name: 'seven', description: '',
      openings: [for (var i = 0; i < 7; i++) Opening(id: '$i', name: '$i', category: 'test')]);
    final ids = {for (var i = 0; i < 7; i++) suite.openingFor(seed: 1, pairingIndex: 0, gameIndex: i * 2).id};
    expect(ids.length, 7);
  });
  test('automatic policy cannot exceed its advertised caps', () {
    final config = const AutoBenchmarkSettings(maxGames: 400,
      maxDuration: Duration(hours: 4)).toConfig();
    expect(config.maxGames, 24);
    expect(config.maxDuration, const Duration(minutes: 10));
  });
}
