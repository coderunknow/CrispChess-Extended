/// Relative Elo with the uncertainty attached to it.
///
/// The fitting itself is [fitRatings] in `lib/services/rating_fit.dart` — one
/// implementation, used by the match screen and by the Engine Lab. This file
/// adds what a benchmark report needs on top of a point estimate:
///
///  * a 95% confidence interval, from the standard error the fit already
///    computes;
///  * a quality grade, so a rating from eight games is not shown as if it were
///    a rating from a thousand;
///  * connectivity: which engines' ratings rest on games against each other.
///    Two disconnected groups are only tied together by the prior, and a
///    comparison across that join is not a measurement;
///  * a comparison between two engines that carries its own uncertainty and a
///    probability, instead of declaring the higher number the winner.
library;

import 'dart:math' as math;

import '../services/rating_fit.dart';

/// How much a rating can be trusted.
enum RatingQuality {
  /// Too few games, or an interval so wide the ordering is a coin toss.
  insufficient,

  /// Indicative only.
  low,

  /// Usable for a rough ordering.
  moderate,

  /// Tight enough to be worth quoting.
  high;

  String get id => name;
}

/// z for a two-sided 95% interval.
const double kZ95 = 1.959963984540054;

/// One engine's rating in a fitted pool.
class EloRating {
  final String engineId;

  /// Display label at the time of the run.
  final String label;
  final double rating;
  final double stdErr;
  final double ciLow;
  final double ciHigh;
  final int wins;
  final int draws;
  final int losses;
  final RatingQuality quality;

  /// Number of distinct opponents this rating rests on.
  final int opponents;

  const EloRating({
    required this.engineId,
    required this.label,
    required this.rating,
    required this.stdErr,
    required this.ciLow,
    required this.ciHigh,
    required this.wins,
    required this.draws,
    required this.losses,
    required this.quality,
    required this.opponents,
  });

  int get games => wins + draws + losses;

  /// Points scored per game, 0..1.
  double get score => games == 0 ? 0 : (wins + draws / 2) / games;

  double get scorePercent => score * 100;

  /// Whether the interval is narrow enough to rank this engine against another
  /// one whose interval does not overlap.
  bool get isUsableForOrdering => quality != RatingQuality.insufficient;

  Map<String, dynamic> toJson() => {
        'engineId': engineId,
        'label': label,
        'rating': rating,
        'stdErr': stdErr.isFinite ? stdErr : null,
        'ciLow': ciLow.isFinite ? ciLow : null,
        'ciHigh': ciHigh.isFinite ? ciHigh : null,
        'wins': wins,
        'draws': draws,
        'losses': losses,
        'games': games,
        'scorePercent': scorePercent,
        'quality': quality.id,
        'opponents': opponents,
      };

  factory EloRating.fromJson(Map<String, dynamic> json) {
    double doubleOf(String key, [double fallback = 0]) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    int intOf(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return 0;
    }

    final quality = json['quality'];
    return EloRating(
      engineId: (json['engineId'] as String?) ?? 'unknown',
      label: (json['label'] as String?) ?? 'Engine',
      rating: doubleOf('rating'),
      stdErr: doubleOf('stdErr', double.infinity),
      ciLow: doubleOf('ciLow', double.negativeInfinity),
      ciHigh: doubleOf('ciHigh', double.infinity),
      wins: intOf('wins'),
      draws: intOf('draws'),
      losses: intOf('losses'),
      quality: RatingQuality.values.firstWhere(
        (q) => q.id == quality,
        orElse: () => RatingQuality.insufficient,
      ),
      opponents: intOf('opponents'),
    );
  }

  @override
  String toString() => 'EloRating($label, ${rating.toStringAsFixed(1)} '
      '±${(kZ95 * stdErr).toStringAsFixed(1)}, ${quality.id})';
}

/// A comparison of two ratings, with its own uncertainty.
class EloComparison {
  final String aId;
  final String bId;
  final double difference;
  final double stdErr;
  final double ciLow;
  final double ciHigh;

  /// Probability that A is genuinely the stronger engine, under a normal
  /// approximation on the rating difference.
  final double probabilityAGreater;
  final String verdict;
  final List<String> warnings;

  const EloComparison({
    required this.aId,
    required this.bId,
    required this.difference,
    required this.stdErr,
    required this.ciLow,
    required this.ciHigh,
    required this.probabilityAGreater,
    required this.verdict,
    this.warnings = const [],
  });

  bool get isSignificant => ciLow > 0 || ciHigh < 0;

  Map<String, dynamic> toJson() => {
        'a': aId,
        'b': bId,
        'difference': difference,
        'stdErr': stdErr.isFinite ? stdErr : null,
        'ciLow': ciLow.isFinite ? ciLow : null,
        'ciHigh': ciHigh.isFinite ? ciHigh : null,
        'probabilityAGreater': probabilityAGreater,
        'verdict': verdict,
      };
}

/// A change in one engine's rating between two runs.
///
/// This is the regression detector: the point is never "the number went down",
/// it is whether the interval on the *change* excludes zero. Two runs of 40
/// games each routinely differ by 40 Elo for no reason at all.
class EloDelta {
  final String engineId;
  final String label;
  final double before;
  final double after;
  final double difference;
  final double stdErr;
  final double ciLow;
  final double ciHigh;

  const EloDelta({
    required this.engineId,
    required this.label,
    required this.before,
    required this.after,
    required this.difference,
    required this.stdErr,
    required this.ciLow,
    required this.ciHigh,
  });

  double get effectSize => stdErr.isFinite && stdErr > 0 ? difference / stdErr : 0;

  bool get isReliable =>
      stdErr.isFinite && (ciLow > 0 || ciHigh < 0);

  bool get isRegression => isReliable && difference < 0;

  bool get isImprovement => isReliable && difference > 0;

  /// What to show instead of a verdict when the change is not established.
  String get verdict {
    if (!stdErr.isFinite) {
      return 'not comparable (a rating has no interval)';
    }
    if (!isReliable) {
      return 'no reliable change (±${(kZ95 * stdErr).toStringAsFixed(0)} Elo)';
    }
    final sign = difference < 0 ? 'regression' : 'improvement';
    return '$sign of ${difference.abs().toStringAsFixed(0)} Elo '
        '(95% interval excludes zero)';
  }

  /// Extra games a shaky comparison would need, so the UI can suggest a next
  /// step instead of a re-run by guesswork.
  int get suggestedAdditionalGames {
    if (!stdErr.isFinite || stdErr <= 0) return 0;
    // Aim at ±20 Elo on the difference.
    final target = 20.0;
    if (stdErr <= target) return 0;
    final factor = (stdErr / target) * (stdErr / target);
    return (factor - 1).ceil() * 20;
  }

  Map<String, dynamic> toJson() => {
        'engineId': engineId,
        'label': label,
        'before': before,
        'after': after,
        'difference': difference,
        'stdErr': stdErr.isFinite ? stdErr : null,
        'ciLow': ciLow.isFinite ? ciLow : null,
        'ciHigh': ciHigh.isFinite ? ciHigh : null,
        'verdict': verdict,
      };
}

/// The rating change of one engine between two fits, or null when either run
/// did not rate it.
EloDelta? ratingDelta(EloRating before, EloRating after) {
  final difference = after.rating - before.rating;
  final se = (before.stdErr.isFinite && after.stdErr.isFinite)
      ? math.sqrt(before.stdErr * before.stdErr + after.stdErr * after.stdErr)
      : double.infinity;
  return EloDelta(
    engineId: after.engineId,
    label: after.label,
    before: before.rating,
    after: after.rating,
    difference: difference,
    stdErr: se,
    ciLow: difference - kZ95 * se,
    ciHigh: difference + kZ95 * se,
  );
}

/// The result of fitting one pool of games.
class EloFit {
  final List<EloRating> ratings;

  /// Games actually used in the fit.
  final int ratedGames;

  /// Games that were not used, and why they were not.
  final Map<String, int> excludedByOutcome;

  /// The relative scale centre (1500 unless the caller said otherwise).
  final double anchor;

  /// Engine the fit is anchored on, when it is not the geometric centre.
  final String? anchorEngineId;

  /// Connected groups of engines, each list sorted by rating. More than one
  /// group means some comparisons cross a join that only the prior holds
  /// together.
  final List<List<String>> components;

  final List<String> warnings;

  const EloFit({
    required this.ratings,
    required this.ratedGames,
    required this.excludedByOutcome,
    required this.anchor,
    this.anchorEngineId,
    this.components = const [],
    this.warnings = const [],
  });

  static const EloFit empty = EloFit(
    ratings: [],
    ratedGames: 0,
    excludedByOutcome: {},
    anchor: 1500,
  );

  bool get isEmpty => ratings.isEmpty;

  EloRating? ratingFor(String engineId) {
    for (final rating in ratings) {
      if (rating.engineId == engineId) return rating;
    }
    return null;
  }

  /// Whether two engines' ratings rest on at least one game against each other
  /// (directly or through the fitted pool).
  bool inSameComponent(String a, String b) {
    for (final component in components) {
      if (component.contains(a) && component.contains(b)) return true;
    }
    return false;
  }

  /// Compares two engines, refusing to pretend a cross-component difference is
  /// measured.
  EloComparison? compare(String aId, String bId) {
    final a = ratingFor(aId);
    final b = ratingFor(bId);
    if (a == null || b == null) return null;
    final difference = a.rating - b.rating;
    // Joint-fit ratings are correlated (anti-correlated for two players).
    // Independence would UNDERSTATE uncertainty. Without stored covariance,
    // use the Cauchy-Schwarz upper bound; exact for a centered two-player fit.
    final connected = inSameComponent(aId, bId);
    final se = connected ? a.stdErr + b.stdErr : double.infinity;
    final warnings = <String>[];
    if (!inSameComponent(aId, bId)) {
      warnings.add('These engines are not connected by games in this run; the '
          'difference rests on the fit prior, not on a match.');
    }
    if (a.quality == RatingQuality.insufficient ||
        b.quality == RatingQuality.insufficient) {
      warnings.add('At least one of these ratings is too uncertain to rank.');
    }
    final probability = se <= 0
        ? (difference > 0 ? 1.0 : 0.0)
        : normalCdf(difference / se);
    final low = difference - kZ95 * se;
    final high = difference + kZ95 * se;
    final String verdict;
    if (!connected) {
      verdict = 'not comparable (disconnected pools)';
    } else if (se <= 0) {
      verdict = 'identical';
    } else if (low > 0) {
      verdict = 'A is stronger (95% interval excludes zero)';
    } else if (high < 0) {
      verdict = 'B is stronger (95% interval excludes zero)';
    } else {
      verdict = 'no reliable difference';
    }
    return EloComparison(
      aId: aId,
      bId: bId,
      difference: difference,
      stdErr: se,
      ciLow: low,
      ciHigh: high,
      probabilityAGreater: probability,
      verdict: verdict,
      warnings: warnings,
    );
  }

  Map<String, dynamic> toJson() => {
        'anchor': anchor,
        if (anchorEngineId != null) 'anchorEngineId': anchorEngineId,
        'ratedGames': ratedGames,
        'excludedByOutcome': excludedByOutcome,
        'ratings': [for (final rating in ratings) rating.toJson()],
        'components': components,
        'warnings': warnings,
      };

  factory EloFit.fromJson(Map<String, dynamic> json) {
    final ratings = <EloRating>[];
    final raw = json['ratings'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          ratings.add(EloRating.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    final excluded = <String, int>{};
    final rawExcluded = json['excludedByOutcome'];
    if (rawExcluded is Map) {
      rawExcluded.forEach((key, value) {
        if (value is num) excluded['$key'] = value.toInt();
      });
    }
    final components = <List<String>>[];
    final rawComponents = json['components'];
    if (rawComponents is List) {
      for (final entry in rawComponents) {
        if (entry is List) {
          components.add([for (final id in entry) '$id']);
        }
      }
    }
    final warnings = <String>[];
    final rawWarnings = json['warnings'];
    if (rawWarnings is List) {
      for (final warning in rawWarnings) {
        warnings.add('$warning');
      }
    }
    final anchor = json['anchor'];
    return EloFit(
      ratings: ratings,
      ratedGames: json['ratedGames'] is num
          ? (json['ratedGames'] as num).toInt()
          : 0,
      excludedByOutcome: excluded,
      anchor: anchor is num ? anchor.toDouble() : 1500,
      anchorEngineId: json['anchorEngineId'] as String?,
      components: components,
      warnings: warnings,
    );
  }
}

/// Fits ratings to [games].
///
/// [labels] maps engine id to display name; ids without a label are shown as
/// they are. [anchorPlayer] pins one engine at [anchor] instead of centring the
/// pool on it, which is what makes a rating comparable with an earlier run that
/// used the same anchor.
EloFit fitElo({
  required List<RatedGame> games,
  Map<String, String> labels = const {},
  double anchor = 1500,
  String? anchorPlayer,
  double prior = 0.3,
  Map<String, int> excludedByOutcome = const {},
}) {
  final excluded = Map<String, int>.from(excludedByOutcome);
  final eligible = List<RatedGame>.of(games);
  if (eligible.isEmpty) {
    return EloFit(
      ratings: const [],
      ratedGames: 0,
      excludedByOutcome: excluded,
      anchor: anchor,
      anchorEngineId: anchorPlayer,
      warnings: const ['No rated games in this run.'],
    );
  }

  final fitted = fitRatings(
    eligible,
    anchor: anchor,
    anchorPlayer: anchorPlayer,
    prior: prior,
  );

  final opponents = <String, Set<String>>{};
  final playedPairs = <String, int>{};
  for (final game in eligible) {
    (opponents[game.white] ??= <String>{}).add(game.black);
    (opponents[game.black] ??= <String>{}).add(game.white);
    final key = game.white.compareTo(game.black) < 0
        ? '${game.white}\u0000${game.black}'
        : '${game.black}\u0000${game.white}';
    playedPairs[key] = (playedPairs[key] ?? 0) + 1;
  }

  final ratings = <EloRating>[
    for (final player in fitted)
      EloRating(
        engineId: player.name,
        label: labels[player.name] ?? player.name,
        rating: player.rating,
        stdErr: player.stdErr,
        ciLow: player.rating - kZ95 * player.stdErr,
        ciHigh: player.rating + kZ95 * player.stdErr,
        wins: player.wins,
        draws: player.draws,
        losses: player.losses,
        quality: gradeRating(player.games, player.stdErr),
        opponents: (opponents[player.name] ?? const <String>{}).length,
      ),
  ];

  final components = _components(
    ratings.map((r) => r.engineId).toList(),
    playedPairs,
  );

  final warnings = <String>[];
  if (components.length > 1) {
    warnings.add('The run has ${components.length} groups of engines that never '
        'played each other; ratings across those groups are tied only by the '
        'fit prior and should not be compared.');
  }
  for (final rating in ratings) {
    if (rating.games < 10) {
      warnings.add('${rating.label} played only ${rating.games} rated '
          'game(s); its rating is indicative at best.');
    }
  }
  if (ratings.any((r) => r.stdErr.isInfinite || r.stdErr.isNaN)) {
    warnings.add('At least one rating has no information behind it (no '
        'finished games); it is shown as an estimate only.');
  }

  return EloFit(
    ratings: ratings..sort((a, b) => b.rating.compareTo(a.rating)),
    ratedGames: eligible.length,
    excludedByOutcome: excluded,
    anchor: anchor,
    anchorEngineId: anchorPlayer,
    components: components,
    warnings: warnings,
  );
}

/// Grade for a rating, from the games behind it *and* the interval it ends up
/// with. Games alone are not enough: 200 draws against one opponent still says
/// little.
RatingQuality gradeRating(int games, double stdErr) {
  if (games < 20 || stdErr.isInfinite || stdErr.isNaN || stdErr > 250) {
    return RatingQuality.insufficient;
  }
  if (stdErr <= 50 && games >= 100) return RatingQuality.high;
  if (stdErr <= 80 && games >= 60) return RatingQuality.moderate;
  return RatingQuality.low;
}

List<List<String>> _components(List<String> players, Map<String, int> pairs) {
  final parent = <String, String>{for (final player in players) player: player};

  String find(String value) {
    var current = value;
    while (parent[current] != current) {
      final next = parent[current]!;
      parent[current] = parent[next] ?? next;
      current = next;
    }
    return current;
  }

  void union(String a, String b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootB] = rootA;
  }

  for (final entry in pairs.entries) {
    if (entry.value <= 0) continue;
    final parts = entry.key.split('\u0000');
    if (parts.length != 2) continue;
    if (!parent.containsKey(parts[0]) || !parent.containsKey(parts[1])) {
      continue;
    }
    union(parts[0], parts[1]);
  }

  final groups = <String, List<String>>{};
  for (final player in players) {
    (groups[find(player)] ??= <String>[]).add(player);
  }
  final result = groups.values.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  return result;
}

/// Standard normal CDF, via the Abramowitz–Stegun 7.1.26 error function.
///
/// Accurate to ~1.5e-7, which is far beyond what a rating difference needs.
double normalCdf(double z) => 0.5 * (1 + _erf(z / math.sqrt2));

double _erf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  final ax = x.abs();
  const a1 = 0.254829592;
  const a2 = -0.284496736;
  const a3 = 1.421413741;
  const a4 = -1.453152027;
  const a5 = 1.061405429;
  const p = 0.3275911;
  final t = 1.0 / (1.0 + p * ax);
  final y = 1.0 -
      (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax);
  return sign * y;
}

/// Games needed to shrink a standard error of [currentStdErr] to [targetStdErr],
/// assuming more games scale the information linearly (SE ∝ 1/√n).
int gamesNeededForStdErr({
  required int gamesSoFar,
  required double currentStdErr,
  required double targetStdErr,
}) {
  if (gamesSoFar <= 0 || currentStdErr <= 0 || targetStdErr <= 0) return 0;
  if (currentStdErr <= targetStdErr) return 0;
  final factor = (currentStdErr / targetStdErr) * (currentStdErr / targetStdErr);
  return math.max(0, (gamesSoFar * factor).ceil() - gamesSoFar);
}
