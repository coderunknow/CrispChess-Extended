import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/services/rating_fit.dart';

RatedGame g(String w, String b, double s) => (white: w, black: b, score: s);

void main() {
  test('3 of 4 wins is a 191-point gap without the prior', () {
    final r = fitRatings([
      g('A', 'B', 1), g('B', 'A', 0), g('A', 'B', 1), g('B', 'A', 1),
    ], prior: 0);
    final a = r.firstWhere((p) => p.name == 'A');
    final b = r.firstWhere((p) => p.name == 'B');
    expect(a.rating - b.rating, closeTo(400 * math.log(3) / math.ln10, 0.01));
    expect((a.rating + b.rating) / 2, closeTo(1500, 1e-6));
    expect(a.wins, 3);
    expect(b.losses, 3);
  });

  test('standard errors use the centered joint Fisher information', () {
    final ratings = fitRatings([
      g('A', 'B', 0.5),
      g('B', 'A', 0.5),
      g('A', 'B', 0.5),
      g('B', 'A', 0.5),
    ], prior: 0);
    expect(ratings[0].stdErr, closeTo((400 / math.ln10) / 2, 1e-6));
    expect(ratings[1].stdErr, closeTo(ratings[0].stdErr, 1e-9));
  });

  test('the prior keeps an unbeaten player finite', () {
    final r = fitRatings([g('A', 'B', 1), g('B', 'A', 0)]);
    expect(r.first.name, 'A');
    expect(r.first.rating.isFinite, isTrue);
    expect(r.first.stdErr.isFinite, isTrue);
  });

  test('evenly matched players rate the same', () {
    final r = fitRatings([g('A', 'B', 0.5), g('B', 'A', 0.5), g('A', 'B', 1), g('B', 'A', 1)]);
    expect(r[0].rating, closeTo(r[1].rating, 1e-6));
  });

  test('a round robin orders the players and anchors on one of them', () {
    final games = [
      for (var k = 0; k < 4; k++) ...[
        g('Strong', 'Mid', k < 3 ? 1 : 0.5),
        g('Mid', 'Weak', k < 3 ? 1 : 0),
        g('Strong', 'Weak', 1),
      ]
    ];
    final r = fitRatings(games, anchorPlayer: 'Mid', anchor: 1440);
    expect(r.map((p) => p.name), ['Strong', 'Mid', 'Weak']);
    expect(r[1].rating, closeTo(1440, 1e-6));
    // More games against the pool shrink the error bars.
    final r2 = fitRatings([...games, ...games, ...games], anchorPlayer: 'Mid', anchor: 1440);
    expect(r2.first.stdErr, lessThan(r.first.stdErr));
  });

  test('expected score is the Elo curve', () {
    expect(expectedScore(1500, 1500), 0.5);
    expect(expectedScore(1700, 1500), closeTo(0.76, 0.01));
  });

  test('disconnected comparison groups are independently anchored and marked', () {
    final ratings = fitRatings([
      g('id-a1', 'id-a2', 1),
      g('id-b1', 'id-b2', 0),
    ]);
    expect(ratings.map((r) => r.name).toSet(), {'id-a1', 'id-a2', 'id-b1', 'id-b2'});
    expect(ratings.map((r) => r.component).toSet().length, 2);
    for (final group in [
      ratings.where((r) => r.component == 0),
      ratings.where((r) => r.component == 1),
    ]) {
      expect(group.map((r) => r.rating).reduce((a, b) => a + b) / 2, closeTo(1500, 1e-6));
    }
  });

  test('rejects invalid outcomes and self-play identity collisions', () {
    expect(() => fitRatings([g('same', 'same', 0.5)]), throwsArgumentError);
    expect(() => fitRatings([g('A', 'B', 0.25)]), throwsArgumentError);
  });

  test('no games, no ratings', () => expect(fitRatings(const []), isEmpty));
}
