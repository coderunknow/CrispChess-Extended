/// Joint Bradley–Terry ratings and their observed Fisher covariance.
///
/// The public [fitRatings] API is retained. [fitRatingModel] additionally
/// exposes the full mean-centred covariance, convergence and component data so
/// comparisons and the opening-cluster bootstrap use the same fitted model.
/// The small draw prior stabilizes point estimates only; it never contributes
/// to standard errors or bootstrap evidence.
library;

import 'dart:math' as math;

/// One game: [white] against [black], [score] from White's side.
typedef RatedGame = ({String white, String black, double score});

class PlayerRating {
  final String name;
  final double rating;

  /// Observed-information Fisher standard error. This is a diagnostic when
  /// games share opening clusters; the primary interval is the cluster
  /// bootstrap. Infinite means no finite observed information.
  final double stdErr;
  final int wins, draws, losses;
  final int component;

  const PlayerRating(this.name, this.rating, this.stdErr, this.wins, this.draws,
      this.losses, {this.component = 0});

  int get games => wins + draws + losses;
  double get score => games == 0 ? 0 : (wins + draws / 2) / games;
  double get ci95Low => rating - 1.96 * stdErr;
  double get ci95High => rating + 1.96 * stdErr;
  bool get hasUsableEstimate => games >= 2 && stdErr.isFinite;
  String get sampleQuality => games < 8
      ? 'very low'
      : games < 30
          ? 'low'
          : games < 100
              ? 'moderate'
              : 'strong';
}

const double ratingEloScale = 400 / math.ln10;
const double _scale = ratingEloScale;

/// Sufficient statistics for one set of games. Bootstrap replicates aggregate
/// these counts instead of allocating thousands of temporary game objects.
class RatingTally {
  final List<String> players;
  final Map<String, int> index;
  final List<double> wins;
  final List<List<double>> observed;
  final List<List<double>> played;
  final List<List<int>> record;

  RatingTally(Iterable<String> players)
      : players = players.toSet().toList()..sort(),
        index = {},
        wins = List<double>.filled(players.toSet().length, 0),
        observed = List.generate(players.toSet().length,
            (_) => List<double>.filled(players.toSet().length, 0)),
        played = List.generate(players.toSet().length,
            (_) => List<double>.filled(players.toSet().length, 0)),
        record = List.generate(players.toSet().length, (_) => [0, 0, 0]) {
    for (var i = 0; i < this.players.length; i++) {
      index[this.players[i]] = i;
    }
  }

  void add(String white, String black, double score, {int multiplier = 1}) {
    if (multiplier == 0) return;
    if (multiplier < 0) throw ArgumentError.value(multiplier, 'multiplier');
    final i = index[white], j = index[black];
    if (i == null || j == null || i == j) {
      throw ArgumentError('Tally requires two distinct registered players');
    }
    if (!score.isFinite || (score != 0 && score != 0.5 && score != 1)) {
      throw ArgumentError.value(score, 'score');
    }
    final m = multiplier.toDouble();
    observed[i][j] += m;
    observed[j][i] += m;
    played[i][j] += m;
    played[j][i] += m;
    wins[i] += score * m;
    wins[j] += (1 - score) * m;
    if (score == 1) {
      record[i][0] += multiplier;
      record[j][2] += multiplier;
    } else if (score == 0) {
      record[i][2] += multiplier;
      record[j][0] += multiplier;
    } else {
      record[i][1] += multiplier;
      record[j][1] += multiplier;
    }
  }

  void addFrom(RatingTally other, {int multiplier = 1}) {
    if (multiplier == 0) return;
    if (other.players.length != players.length) {
      throw ArgumentError('Tallies must describe the same participants');
    }
    for (var k = 0; k < players.length; k++) {
      if (other.players[k] != players[k]) {
        throw ArgumentError('Tallies must describe the same participants');
      }
    }
    final m = multiplier.toDouble();
    for (var i = 0; i < players.length; i++) {
      wins[i] += other.wins[i] * m;
      for (var j = 0; j < players.length; j++) {
        observed[i][j] += other.observed[i][j] * m;
        played[i][j] += other.played[i][j] * m;
      }
      for (var k = 0; k < 3; k++) {
        record[i][k] += other.record[i][k] * multiplier;
      }
    }
  }

  int get games => observed.fold(0.0, (s, row) => s + row.fold(0.0, (a, b) => a + b)) ~/ 2;
}

/// A joint fit, including covariance in Elo-squared units.
class RatingModelFit {
  final List<String> players;
  final List<PlayerRating> ratings;
  final List<List<double>> covariance;
  final List<List<String>> components;
  final Map<String, int> componentOf;
  final bool converged;
  final bool separated;
  final int iterations;
  final int games;

  const RatingModelFit({
    required this.players,
    required this.ratings,
    required this.covariance,
    required this.components,
    required this.componentOf,
    required this.converged,
    required this.separated,
    required this.iterations,
    required this.games,
  });

  PlayerRating? ratingFor(String id) {
    for (final rating in ratings) {
      if (rating.name == id) return rating;
    }
    return null;
  }

  bool connected(String a, String b) =>
      componentOf.containsKey(a) && componentOf[a] == componentOf[b];

  /// Var(cᵀ rating), using the joint covariance. Null for unknown players;
  /// infinite across disconnected components or when information is singular.
  double contrastVariance(Map<String, double> coefficients) {
    var variance = 0.0;
    for (final a in coefficients.entries) {
      final i = players.indexOf(a.key);
      if (i < 0 || a.value == 0) continue;
      for (final b in coefficients.entries) {
        final j = players.indexOf(b.key);
        if (j < 0 || b.value == 0) continue;
        if (!connected(a.key, b.key)) return double.infinity;
        variance += a.value * b.value * covariance[i][j];
      }
    }
    return variance < 0 && variance > -1e-8 ? 0 : variance;
  }
}

/// Legacy public fit API.
List<PlayerRating> fitRatings(
  List<RatedGame> games, {
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  double tolerance = 1e-11,
  int maxIterations = 10000,
}) =>
    fitRatingModel(games,
            anchor: anchor,
            anchorPlayer: anchorPlayer,
            prior: prior,
            tolerance: tolerance,
            maxIterations: maxIterations)
        .ratings;

/// Fits every participant, including engines with no eligible game yet.
RatingModelFit fitRatingModel(
  List<RatedGame> games, {
  Iterable<String> participants = const [],
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  double tolerance = 1e-11,
  int maxIterations = 10000,
}) {
  final ids = <String>{...participants, for (final g in games) ...[g.white, g.black]};
  final tally = RatingTally(ids);
  for (final game in games) {
    tally.add(game.white, game.black, game.score);
  }
  return fitRatingModelFromTally(tally,
      anchor: anchor,
      anchorPlayer: anchorPlayer,
      prior: prior,
      tolerance: tolerance,
      maxIterations: maxIterations);
}

/// Fit from sufficient statistics. Used by both the public fitter and every
/// bootstrap replicate, so there is no second rating algorithm to drift.
RatingModelFit fitRatingModelFromTally(
  RatingTally tally, {
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  double tolerance = 1e-11,
  int maxIterations = 10000,
}) {
  if (!anchor.isFinite ||
      !prior.isFinite ||
      prior < 0 ||
      !tolerance.isFinite ||
      tolerance <= 0 ||
      maxIterations < 1) {
    throw ArgumentError('Rating fit parameters must be finite with a '
        'non-negative prior and positive limits');
  }
  final players = tally.players;
  final n = players.length;
  if (n == 0) {
    return const RatingModelFit(
        players: [], ratings: [], covariance: [], components: [],
        componentOf: {}, converged: true, separated: false,
        iterations: 0, games: 0);
  }
  final adjacency = {for (final p in players) p: <String>{}};
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (tally.observed[i][j] > 0) {
        adjacency[players[i]]!.add(players[j]);
        adjacency[players[j]]!.add(players[i]);
      }
    }
  }
  final components = <List<String>>[];
  final visited = <String>{};
  for (final player in players) {
    if (!visited.add(player)) continue;
    final pending = [player];
    final component = <String>[];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      component.add(current);
      for (final neighbour in adjacency[current]!) {
        if (visited.add(neighbour)) pending.add(neighbour);
      }
    }
    components.add(component..sort());
  }
  final componentOf = <String, int>{};
  for (var c = 0; c < components.length; c++) {
    for (final p in components[c]) {
      componentOf[p] = c;
    }
  }
  final covariance = List.generate(n, (_) => List<double>.filled(n, 0));
  final ratings = <PlayerRating>[];
  var converged = true;
  var separated = false;
  var iterations = 0;
  for (var c = 0; c < components.length; c++) {
    final members = components[c];
    final indexes = [for (final p in members) tally.index[p]!];
    if (members.length == 1) {
      final i = indexes.single;
      ratings.add(PlayerRating(members.single, anchor, double.infinity,
          tally.record[i][0], tally.record[i][1], tally.record[i][2], component: c));
      covariance[i][i] = double.infinity;
      continue;
    }
    final local = _ComponentTally.from(tally, indexes);
    final result = _fitComponent(local, members,
        anchor: anchor,
        anchorPlayer: anchorPlayer,
        prior: prior,
        tolerance: tolerance,
        maxIterations: maxIterations);
    converged &= result.converged;
    separated |= result.separated;
    iterations = math.max(iterations, result.iterations);
    for (var a = 0; a < members.length; a++) {
      final i = indexes[a];
      final r = result.ratings[a];
      ratings.add(PlayerRating(r.name, r.rating, r.stdErr, r.wins, r.draws,
          r.losses, component: c));
      for (var b = 0; b < members.length; b++) {
        covariance[i][indexes[b]] = result.covariance[a][b];
      }
    }
  }
  ratings.sort((a, b) {
    final finiteA = a.rating.isFinite, finiteB = b.rating.isFinite;
    if (finiteA != finiteB) return finiteA ? -1 : 1;
    final byRating = b.rating.compareTo(a.rating);
    return byRating != 0 ? byRating : a.name.compareTo(b.name);
  });
  return RatingModelFit(
    players: players,
    ratings: ratings,
    covariance: covariance,
    components: components,
    componentOf: componentOf,
    converged: converged,
    separated: separated,
    iterations: iterations,
    games: tally.games,
  );
}

class _ComponentTally {
  final List<double> wins;
  final List<List<double>> observed, played;
  final List<List<int>> record;
  const _ComponentTally(this.wins, this.observed, this.played, this.record);

  factory _ComponentTally.from(RatingTally tally, List<int> indexes) {
    final n = indexes.length;
    return _ComponentTally(
      [for (final i in indexes) tally.wins[i]],
      [for (final i in indexes) [for (final j in indexes) tally.observed[i][j]]],
      [for (final i in indexes) [for (final j in indexes) tally.played[i][j]]],
      [for (final i in indexes) List<int>.of(tally.record[i])],
    );
  }
}

class _ComponentFit {
  final List<PlayerRating> ratings;
  final List<List<double>> covariance;
  final bool converged, separated;
  final int iterations;
  const _ComponentFit(this.ratings, this.covariance, this.converged,
      this.separated, this.iterations);
}

_ComponentFit _fitComponent(
  _ComponentTally tally,
  List<String> players, {
  required double anchor,
  required String? anchorPlayer,
  required double prior,
  required double tolerance,
  required int maxIterations,
}) {
  final n = players.length;
  final wins = List<double>.of(tally.wins);
  final played = [for (final row in tally.played) List<double>.of(row)];
  // Ford's condition: an engine with no points or a perfect observed record
  // sends the unregularized MLE to infinity. The prior keeps the displayed
  // estimate finite, but never turns that into statistical information.
  //
  // The test is deliberately run on the *observed* tallies, before the prior is
  // added: once the pseudo-counts are mixed in, "wins >= games" can no longer
  // be true, and a perfect record would be reported as an ordinary finite SE.
  var separated = false;
  for (var i = 0; i < n; i++) {
    var games = 0.0;
    for (var j = 0; j < n; j++) {
      if (i != j) games += tally.observed[i][j];
    }
    if (games > 0 && (tally.wins[i] <= 0 || tally.wins[i] >= games)) {
      separated = true;
    }
  }
  if (prior > 0) {
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        if (i != j) played[i][j] += prior;
      }
      wins[i] += prior * (n - 1) / 2;
    }
  }
  var gamma = List<double>.filled(n, 1);
  var converged = false;
  var iterations = 0;
  for (var it = 0; it < maxIterations; it++) {
    iterations = it + 1;
    final next = List<double>.of(gamma);
    for (var i = 0; i < n; i++) {
      var denom = 0.0;
      for (var j = 0; j < n; j++) {
        if (i != j && played[i][j] > 0) {
          denom += played[i][j] / (gamma[i] + gamma[j]);
        }
      }
      if (denom > 0 && wins[i] > 0) next[i] = wins[i] / denom;
    }
    final geo = math.exp(next.fold(0.0, (s, g) => s + math.log(math.max(g, 1e-300))) / n);
    for (var i = 0; i < n; i++) {
      next[i] /= geo;
    }
    var delta = 0.0;
    for (var i = 0; i < n; i++) {
      delta = math.max(delta,
          (math.log(math.max(next[i], 1e-300)) - math.log(math.max(gamma[i], 1e-300))).abs());
    }
    gamma = next;
    if (delta < tolerance) {
      converged = true;
      break;
    }
  }
  final raw = [for (final g in gamma) _scale * math.log(g)];
  // The curvature is the priored one, so a separated player still gets a finite
  // interval — that is what `prior` is for, and `PlayerRating.stdErr` is
  // documented as a diagnostic, not as observed information. What must not
  // happen is silence: `separated` travels with the fit so a report can say the
  // record was perfect and the number rests on the prior rather than on data.
  final covariance = _jointCovariance(tally.observed, gamma);
  final shift = anchorPlayer != null && players.contains(anchorPlayer)
      ? anchor - raw[players.indexOf(anchorPlayer)]
      : anchor - raw.fold(0.0, (a, b) => a + b) / n;
  final ratings = [
    for (var i = 0; i < n; i++)
      PlayerRating(players[i], raw[i] + shift,
          math.sqrt(math.max(0, covariance[i][i])),
          tally.record[i][0], tally.record[i][1], tally.record[i][2]),
  ];
  return _ComponentFit(ratings, covariance, converged, separated, iterations);
}

/// Invert the observed Fisher Laplacian with one temporary reference, then
/// transform to mean-centred coordinates. Returns Elo-squared covariance.
List<List<double>> _jointCovariance(List<List<double>> observed, List<double> gamma) {
  final n = gamma.length;
  if (n < 2) return [[double.infinity]];
  final reduced = n - 1;
  final information = List.generate(reduced, (_) => List<double>.filled(reduced, 0));
  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (observed[i][j] <= 0) continue;
      final p = gamma[i] / (gamma[i] + gamma[j]);
      final weight = observed[i][j] * p * (1 - p);
      if (i < reduced) information[i][i] += weight;
      if (j < reduced) information[j][j] += weight;
      if (i < reduced && j < reduced) {
        information[i][j] -= weight;
        information[j][i] -= weight;
      }
    }
  }
  final augmented = List.generate(reduced, (row) => [
        ...information[row],
        for (var col = 0; col < reduced; col++) row == col ? 1.0 : 0.0,
      ]);
  for (var col = 0; col < reduced; col++) {
    var pivot = col;
    for (var row = col + 1; row < reduced; row++) {
      if (augmented[row][col].abs() > augmented[pivot][col].abs()) pivot = row;
    }
    if (augmented[pivot][col].abs() < 1e-14) {
      return List.generate(n, (_) => List<double>.filled(n, double.infinity));
    }
    if (pivot != col) {
      final row = augmented[col];
      augmented[col] = augmented[pivot];
      augmented[pivot] = row;
    }
    final divisor = augmented[col][col];
    for (var k = 0; k < 2 * reduced; k++) {
      augmented[col][k] /= divisor;
    }
    for (var row = 0; row < reduced; row++) {
      if (row == col) continue;
      final factor = augmented[row][col];
      for (var k = 0; k < 2 * reduced; k++) {
        augmented[row][k] -= factor * augmented[col][k];
      }
    }
  }
  final inverse = [for (var row = 0; row < reduced; row++) augmented[row].sublist(reduced)];
  return List.generate(n, (i) => List.generate(n, (j) {
    var value = 0.0;
    for (var a = 0; a < reduced; a++) {
      final ca = (i == a ? 1.0 : 0.0) - 1 / n;
      for (var b = 0; b < reduced; b++) {
        final cb = (j == b ? 1.0 : 0.0) - 1 / n;
        value += ca * inverse[a][b] * cb;
      }
    }
    return value * _scale * _scale;
  }));
}

/// Expected score of a player rated [a] against one rated [b].
double expectedScore(double a, double b) => 1 / (1 + math.pow(10, (b - a) / 400));
