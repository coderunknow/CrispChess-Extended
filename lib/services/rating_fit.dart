/// Ratings from a set of games, fitted jointly (Bradley–Terry).
///
/// Ported from `elo.py` of TobiasLogic's Chess Arena
/// (huggingface.co/spaces/TobiasLogic/chess-arena-gpu, MIT): minorisation–
/// maximisation iterations on the Bradley–Terry model, with a small prior of
/// shared draws within each connected comparison component so perfect records
/// stay finite. Ratings in disconnected components are independently centred
/// and must not be compared across components. Standard errors use observed
/// games only, not the stabilizing prior. Unlike running Elo updates, results
/// do not depend on game order.
library;

import 'dart:math' as math;

/// One game: [white] against [black], [score] from White's side
/// (1, 0.5 or 0).
typedef RatedGame = ({String white, String black, double score});

class PlayerRating {
  /// Stable engine identity (or the caller-supplied player key).
  final String name;
  final double rating;

  /// Approximate standard error from observed games only; the stabilizing
  /// prior is not counted as evidence. Infinite means no observed information.
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
  String get sampleQuality => games < 8 ? 'very low' : games < 30 ? 'low' : games < 100 ? 'moderate' : 'strong';
}

const double _scale = 400 / math.ln10;

/// Fits ratings to [games]. Ratings are centred on [anchor] on average, or,
/// when [anchorPlayer] is given, shifted so that player sits exactly at
/// [anchor]. [prior] is the number of phantom games (as draws) between every
/// pair.
List<PlayerRating> fitRatings(
  List<RatedGame> games, {
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  double tolerance = 1e-11,
  int maxIterations = 10000,
}) {
  if (!anchor.isFinite || !prior.isFinite || prior < 0 ||
      !tolerance.isFinite || tolerance <= 0 || maxIterations < 1) {
    throw ArgumentError('Rating fit parameters must be finite with non-negative prior and positive limits');
  }
  for (final game in games) {
    if (game.white == game.black ||
        !game.score.isFinite ||
        (game.score != 0 && game.score != 0.5 && game.score != 1)) {
      throw ArgumentError('Rated games require distinct players and score 0, 0.5 or 1');
    }
  }
  final players = {for (final g in games) ...[g.white, g.black]}.toList()..sort();
  if (players.isEmpty) return const [];

  // Bradley–Terry ratings have no information across disconnected parts of
  // the comparison graph. Never let the numerical prior manufacture a bridge
  // and make two unrelated engines look comparable. Fit each component on its
  // own 1500-centred relative scale and mark its component for consumers.
  final adjacency = {for (final player in players) player: <String>{}};
  for (final game in games) {
    adjacency[game.white]!.add(game.black);
    adjacency[game.black]!.add(game.white);
  }
  final components = <List<String>>[];
  final visited = <String>{};
  for (final player in players) {
    if (!visited.add(player)) continue;
    final pending = <String>[player];
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
  if (components.length > 1) {
    final result = <PlayerRating>[];
    for (var c = 0; c < components.length; c++) {
      final memberIds = components[c].toSet();
      final componentGames = games
          .where((g) => memberIds.contains(g.white) && memberIds.contains(g.black))
          .toList();
      result.addAll(fitRatings(
        componentGames,
        anchor: anchor,
        anchorPlayer: anchorPlayer != null && memberIds.contains(anchorPlayer)
            ? anchorPlayer
            : null,
        prior: prior,
        tolerance: tolerance,
        maxIterations: maxIterations,
      ).map((rating) => PlayerRating(
            rating.name,
            rating.rating,
            rating.stdErr,
            rating.wins,
            rating.draws,
            rating.losses,
            component: c,
          )));
    }
    return result..sort((a, b) => b.rating.compareTo(a.rating));
  }
  final n = players.length;
  final idx = {for (var i = 0; i < n; i++) players[i]: i};

  final wins = List<double>.filled(n, 0);
  final observed = List.generate(n, (_) => List<double>.filled(n, 0));
  final played = List.generate(n, (_) => List<double>.filled(n, 0));
  final record = List.generate(n, (_) => [0, 0, 0]);
  for (final g in games) {
    final i = idx[g.white]!, j = idx[g.black]!;
    observed[i][j] += 1;
    observed[j][i] += 1;
    played[i][j] += 1;
    played[j][i] += 1;
    wins[i] += g.score;
    wins[j] += 1 - g.score;
    if (g.score == 1) {
      record[i][0]++;
      record[j][2]++;
    } else if (g.score == 0) {
      record[i][2]++;
      record[j][0]++;
    } else {
      record[i][1]++;
      record[j][1]++;
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
  for (var it = 0; it < maxIterations; it++) {
    final next = List<double>.of(gamma);
    for (var i = 0; i < n; i++) {
      var denom = 0.0;
      for (var j = 0; j < n; j++) {
        if (i != j && played[i][j] > 0) denom += played[i][j] / (gamma[i] + gamma[j]);
      }
      if (denom > 0 && wins[i] > 0) next[i] = wins[i] / denom;
    }
    final geo = math.exp(
        next.fold(0.0, (s, g) => s + math.log(math.max(g, 1e-300))) / n);
    for (var i = 0; i < n; i++) {
      next[i] /= geo;
    }
    var delta = 0.0;
    for (var i = 0; i < n; i++) {
      delta = math.max(delta,
          (math.log(math.max(next[i], 1e-300)) - math.log(math.max(gamma[i], 1e-300))).abs());
    }
    gamma = next;
    if (delta < tolerance) break;
  }

  final raw = [for (final g in gamma) _scale * math.log(g)];
  final standardErrors = _standardErrors(observed, gamma);
  final shift = anchorPlayer != null && idx.containsKey(anchorPlayer)
      ? anchor - raw[idx[anchorPlayer]!]
      : anchor - raw.fold(0.0, (a, b) => a + b) / n;

  return [
    for (var i = 0; i < n; i++)
      PlayerRating(
        players[i],
        raw[i] + shift,
        standardErrors[i],
        record[i][0],
        record[i][1],
        record[i][2],
      ),
  ]..sort((a, b) => b.rating.compareTo(a.rating));
}

/// Approximate standard errors under a zero-sum (mean-centered) constraint.
///
/// The Bradley–Terry information matrix is a weighted graph Laplacian. Invert
/// the reduced matrix with the last player fixed as a temporary reference, then
/// transform that covariance into the mean-centered rating coordinates used by
/// [fitRatings]. Only observed games contribute information; the prior is a
/// numerical regularizer, not evidence.
List<double> _standardErrors(List<List<double>> observed, List<double> gamma) {
  final n = gamma.length;
  if (n < 2) return List<double>.filled(n, double.infinity);
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
      return List<double>.filled(n, double.infinity);
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

  final covariance = [
    for (var row = 0; row < reduced; row++)
      augmented[row].sublist(reduced),
  ];
  return [
    for (var player = 0; player < n; player++)
      () {
        final coefficients = [
          for (var j = 0; j < reduced; j++)
            (player == j ? 1.0 : 0.0) - 1 / n,
        ];
        var variance = 0.0;
        for (var i = 0; i < reduced; i++) {
          for (var j = 0; j < reduced; j++) {
            variance += coefficients[i] * covariance[i][j] * coefficients[j];
          }
        }
        return variance > 0 ? _scale * math.sqrt(variance) : 0.0;
      }(),
  ];
}

/// Expected score of a player rated [a] against one rated [b].
double expectedScore(double a, double b) => 1 / (1 + math.pow(10, (b - a) / 400));
