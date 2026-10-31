/// A stored benchmark run: what was measured, under which conditions, and what
/// it produced.
///
/// A run is the unit of persistence and of export. It contains its own
/// configuration, environment, per-engine identities and every game, so a
/// report can be re-read, re-analysed and compared with another run months
/// later without consulting any global state.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../services/rating_fit.dart' show RatedGame;
import 'benchmark_config.dart';
import 'benchmark_environment.dart';
import 'benchmark_plan.dart';
import 'calibration.dart';
import 'elo.dart';
import 'engine_identity.dart';
import 'game_record.dart';

/// What happened to one engine in the run.
class EngineRunStatus {
  /// `completed`, `failed`, `skipped`, `unsupported` or `partial`.
  final String status;

  /// Why, when it is not `completed`.
  final String? reason;

  /// Games this engine actually finished.
  final int gamesCompleted;

  const EngineRunStatus({
    required this.status,
    this.reason,
    this.gamesCompleted = 0,
  });

  bool get isFailure =>
      status == 'failed' || status == 'skipped' || status == 'unsupported';

  Map<String, dynamic> toJson() => {
        'status': status,
        if (reason != null) 'reason': reason,
        'gamesCompleted': gamesCompleted,
      };

  factory EngineRunStatus.fromJson(Map<String, dynamic> json) => EngineRunStatus(
        status: (json['status'] as String?) ?? 'completed',
        reason: json['reason'] as String?,
        gamesCompleted: json['gamesCompleted'] is num
            ? (json['gamesCompleted'] as num).toInt()
            : 0,
      );
}

/// A completed (or stopped) benchmark.
class BenchmarkRun {
  /// Stable id, also the storage key.
  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final BenchmarkConfig config;
  final TournamentFormat format;
  final List<EngineIdentity> engines;
  final Map<String, EngineRunStatus> engineStatus;
  final List<BenchGame> games;
  final EloFit ratings;
  final CalibrationOutcome calibration;
  final BenchmarkEnvironment environment;

  /// Why the run stopped: `completed`, `game cap`, `time cap`,
  /// `uncertainty target`, `cancelled`, `engine failure`.
  final String stopReason;

  final List<String> warnings;
  final List<String> validationWarnings;

  /// When set, this run was produced by one of the automatic triggers.
  final String? trigger;

  const BenchmarkRun({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.config,
    required this.format,
    required this.engines,
    required this.engineStatus,
    required this.games,
    required this.ratings,
    required this.calibration,
    required this.environment,
    this.stopReason = 'completed',
    this.warnings = const [],
    this.validationWarnings = const [],
    this.trigger,
  });

  /// Games that produced a rating-eligible result.
  List<BenchGame> get ratedGames =>
      [for (final game in games) if (!game.warmUp && game.outcome.isRatingEligible) game];

  int get gamesCompleted => ratedGames.length;

  int get gamesPlayed => games.where((g) => !g.warmUp).length;

  int get forfeits => games
      .where((g) => !g.warmUp && g.outcome == GameOutcome.forfeit)
      .length;

  int get aborted => games
      .where((g) =>
          !g.warmUp &&
          (g.outcome == GameOutcome.aborted || g.outcome == GameOutcome.cancelled))
      .length;

  int get adjudicated => games
      .where((g) => !g.warmUp && g.outcome == GameOutcome.adjudicated)
      .length;

  Duration get duration => finishedAt.difference(startedAt);

  EngineIdentity? identityFor(String engineId) {
    for (final engine in engines) {
      if (engine.engineId == engineId) return engine;
    }
    return null;
  }

  /// Per-engine aggregates, keyed by engine id.
  Map<String, EngineAggregate> aggregates() {
    final result = <String, EngineAggregate>{
      for (final engine in engines)
        engine.engineId:
            EngineAggregate(engineId: engine.engineId, label: engine.label),
    };
    for (final game in games) {
      if (game.warmUp) continue;
      result[game.whiteId]?.addGame(game);
      result[game.blackId]?.addGame(game);
    }
    return result;
  }

  /// Standings: rated engines first by rating, then unrated ones by score.
  List<EngineAggregate> standings() {
    final aggregates = aggregates();
    final list = aggregates.values.toList();
    list.sort((a, b) {
      final ratingA = ratings.ratingFor(a.engineId);
      final ratingB = ratings.ratingFor(b.engineId);
      if (ratingA != null && ratingB != null) {
        return ratingB.rating.compareTo(ratingA.rating);
      }
      if (ratingA != null) return -1;
      if (ratingB != null) return 1;
      return b.score.compareTo(a.score);
    });
    return list;
  }

  /// A replayable PGN of every recorded game.
  String pgn({String event = 'CrispChess Engine Lab benchmark'}) => games
      .where((game) => !game.warmUp)
      .map((game) => game.pgnDocument(event: event))
      .join('\n');

  /// One row per game.
  String gamesCsv() {
    final header = [
      'game',
      'white_id',
      'white',
      'black_id',
      'black',
      'opening',
      'outcome',
      'forfeit_reason',
      'forfeited_by',
      'plies',
      'white_moves',
      'white_p50_ms',
      'white_p95_ms',
      'black_moves',
      'black_p50_ms',
      'black_p95_ms',
      'duration_ms',
      'detail',
    ];
    final rows = <String>[header.join(',')];
    for (final game in games) {
      if (game.warmUp) continue;
      rows.add([
        '${game.index}',
        game.whiteId,
        game.whiteLabel,
        game.blackId,
        game.blackLabel,
        game.openingName,
        game.outcome.id,
        game.forfeitReason.id,
        game.forfeitedBy ?? '',
        '${game.plies}',
        '${game.white.moves}',
        '${game.white.percentile(0.5)}',
        '${game.white.percentile(0.95)}',
        '${game.black.moves}',
        '${game.black.percentile(0.5)}',
        '${game.black.percentile(0.95)}',
        '${game.durationMillis}',
        _csvEscape(game.detail ?? ''),
      ].join(','));
    }
    return rows.join('\n');
  }

  /// One row per engine.
  String enginesCsv() {
    final header = [
      'engine_id',
      'engine',
      'version',
      'fingerprint_kind',
      'fingerprint',
      'platform',
      'backend',
      'games',
      'wins',
      'draws',
      'losses',
      'score_percent',
      'relative_elo',
      'std_err',
      'ci_low',
      'ci_high',
      'quality',
      'calibrated_elo',
      'p50_ms',
      'p95_ms',
      'p99_ms',
      'max_ms',
      'nodes',
      'nps',
      'depth',
      'forfeit_losses',
      'aborted',
      'status',
      'status_reason',
    ];
    final rows = <String>[header.join(',')];
    for (final aggregate in standings()) {
      final identity = identityFor(aggregate.engineId);
      final rating = ratings.ratingFor(aggregate.engineId);
      final status = engineStatus[aggregate.engineId];
      rows.add([
        aggregate.engineId,
        _csvEscape(aggregate.label),
        _csvEscape(identity?.engineVersion ?? ''),
        identity?.fingerprintKind ?? '',
        identity?.shortFingerprint ?? '',
        identity?.platform ?? '',
        identity?.backend ?? '',
        '${aggregate.ratedGames}',
        '${aggregate.wins}',
        '${aggregate.draws}',
        '${aggregate.losses}',
        aggregate.scorePercent.toStringAsFixed(1),
        rating == null ? '' : rating.rating.toStringAsFixed(1),
        rating == null ? '' : rating.stdErr.toStringAsFixed(1),
        rating == null ? '' : rating.ciLow.toStringAsFixed(1),
        rating == null ? '' : rating.ciHigh.toStringAsFixed(1),
        rating?.quality.id ?? '',
        calibration.ratingFor(aggregate.engineId)?.toStringAsFixed(1) ?? '',
        '${aggregate.percentile(0.5)}',
        '${aggregate.percentile(0.95)}',
        '${aggregate.percentile(0.99)}',
        '${aggregate.maxMillis}',
        aggregate.totalNodes?.toString() ?? '',
        aggregate.nps?.toString() ?? '',
        aggregate.maxDepth?.toString() ?? '',
        '${aggregate.forfeitLosses}',
        '${aggregate.aborted + aggregate.cancelled}',
        status?.status ?? '',
        _csvEscape(status?.reason ?? ''),
      ].join(','));
    }
    return rows.join('\n');
  }

  /// The human-readable report, as Markdown.
  String reportMarkdown() {
    final out = StringBuffer();
    out.writeln('# Engine benchmark report');
    out.writeln();
    out.writeln('- Run: `${id}`');
    out.writeln('- Started: ${startedAt.toIso8601String()}');
    out.writeln('- Finished: ${finishedAt.toIso8601String()} '
        '(${_formatDuration(duration)})');
    out.writeln('- Trigger: ${trigger ?? 'manual'}');
    out.writeln('- Stopped because: $stopReason');
    out.writeln('- Format: ${format.id}');
    out.writeln('- Configuration: ${config.summary}');
    out.writeln('- Platform: ${environment.platform} · ${environment.host}');
    out.writeln('- App: ${environment.appVersion} '
        '(benchmark format ${environment.benchmarkVersion})');
    out.writeln();
    out.writeln('## Standings');
    out.writeln();
    out.writeln('| # | Engine | Rating | 95% CI | Quality | Games | W/D/L '
        '| Score | Notes |');
    out.writeln('|---|---|---|---|---|---|---|---|---|');
    var place = 0;
    for (final aggregate in standings()) {
      place++;
      final rating = ratings.ratingFor(aggregate.engineId);
      final status = engineStatus[aggregate.engineId];
      final notes = <String>[
        if (status != null && status.status != 'completed')
          '${status.status}: ${status.reason ?? ''}',
      ].join('; ');
      out.writeln('| $place | ${_md(aggregate.label)} '
          '| ${rating == null ? '—' : rating.rating.toStringAsFixed(0)} '
          '| ${rating == null ? '—' : '±${(kZ95 * rating.stdErr).toStringAsFixed(0)}'} '
          '| ${rating?.quality.id ?? '—'} '
          '| ${aggregate.ratedGames} '
          '| ${aggregate.wins}/${aggregate.draws}/${aggregate.losses} '
          '| ${aggregate.scorePercent.toStringAsFixed(1)}% '
          '| $notes |');
    }
    out.writeln();
    if (calibration.available) {
      out.writeln('## Calibrated Elo');
      out.writeln();
      out.writeln(calibration.reason);
      out.writeln();
      out.writeln('| Engine | Relative | Calibrated |');
      out.writeln('|---|---|---|');
      for (final aggregate in standings()) {
        final calibrated = calibration.ratingFor(aggregate.engineId);
        final relative = ratings.ratingFor(aggregate.engineId);
        out.writeln('| ${_md(aggregate.label)} '
            '| ${relative == null ? '—' : relative.rating.toStringAsFixed(0)} '
            '| ${calibrated == null ? '—' : calibrated.toStringAsFixed(0)} |');
      }
      out.writeln();
      for (final warning in calibration.warnings) {
        out.writeln('> $warning');
      }
      out.writeln();
    } else {
      out.writeln('## Calibrated Elo');
      out.writeln();
      out.writeln('**Unavailable.** ${calibration.reason}');
      out.writeln();
    }

    out.writeln('## Rating methodology');
    out.writeln();
    out.writeln('Bradley–Terry maximum likelihood over every rated game, '
        'centred on ${ratings.anchor.toStringAsFixed(0)} on average (relative '
        'scale). The 95% interval is `rating ± 1.96 × standard error`, where the '
        'standard error comes from the Fisher information of the fit. Games '
        'that were adjudicated, aborted, cancelled or lost by forfeit are '
        'excluded: ${_excludedSummary()}');
    out.writeln();
    if (ratings.warnings.isNotEmpty) {
      out.writeln('### Rating warnings');
      out.writeln();
      for (final warning in ratings.warnings) {
        out.writeln('- $warning');
      }
      out.writeln();
    }

    out.writeln('## Performance');
    out.writeln();
    out.writeln('| Engine | Moves | p50 | p95 | p99 | max | Nodes | NPS | Depth '
        '| Time-budget compliance |');
    out.writeln('|---|---|---|---|---|---|---|---|---|---|');
    final budgetMs = config.isTimeBased ? config.timePerMove.inMilliseconds : null;
    for (final aggregate in standings()) {
      final compliance = budgetMs == null || aggregate.moveMillis.isEmpty
          ? 'n/a (depth-based)'
          : '${(aggregate.moveMillis.where((ms) => ms <= budgetMs * 1.5).length * 100 / aggregate.moveMillis.length).toStringAsFixed(1)}%';
      out.writeln('| ${_md(aggregate.label)} '
          '| ${aggregate.moveMillis.length} '
          '| ${aggregate.percentile(0.5)} ms '
          '| ${aggregate.percentile(0.95)} ms '
          '| ${aggregate.percentile(0.99)} ms '
          '| ${aggregate.maxMillis} ms '
          '| ${aggregate.totalNodes?.toString() ?? 'unavailable'} '
          '| ${aggregate.nps?.toString() ?? 'unavailable'} '
          '| ${aggregate.maxDepth?.toString() ?? 'unavailable'} '
          '| $compliance |');
    }
    out.writeln();
    out.writeln('CPU time and memory usage are not exposed by the engine '
        'protocol and are reported as unavailable rather than estimated.');
    out.writeln();

    if (forfeits > 0 || aborted > 0 || adjudicated > 0) {
      out.writeln('## Games without a result');
      out.writeln();
      out.writeln('- Forfeits: $forfeits');
      out.writeln('- Aborted or cancelled: $aborted');
      out.writeln('- Adjudicated at the ply cap: $adjudicated');
      out.writeln();
      for (final game in games) {
        if (game.warmUp) continue;
        if (game.outcome.isTerminal) continue;
        out.writeln('- #${game.index} ${_md(game.whiteLabel)} vs '
            '${_md(game.blackLabel)} — ${game.outcome.id}'
            '${game.detail == null ? '' : ': ${game.detail}'}');
      }
      out.writeln();
    }

    if (validationWarnings.isNotEmpty || warnings.isNotEmpty) {
      out.writeln('## Configuration notes');
      out.writeln();
      for (final warning in [...validationWarnings, ...warnings]) {
        out.writeln('- $warning');
      }
      out.writeln();
    }

    out.writeln('## Environment');
    out.writeln();
    for (final engine in engines) {
      final status = engineStatus[engine.engineId];
      final options = engine.configuration.isEmpty
          ? ''
          : ', options ${engine.configuration.entries.map((e) => '${e.key}=${e.value}').join(', ')}';
      final statusText = status == null
          ? ''
          : ', status ${status.status}'
              '${status.reason == null ? '' : ' (' + status.reason! + ')'}';
      out.writeln('- **${_md(engine.label)}** — id `${engine.engineId}`, '
          'backend ${engine.backend}, platform ${engine.platform}, '
          'fingerprint ${engine.fingerprintKind} ${engine.shortFingerprint}'
          '$options$statusText');
    }
    out.writeln();
    out.writeln('## Reproducing');
    out.writeln();
    out.writeln('```json');
    out.writeln(const JsonEncoder.withIndent('  ').convert({
      'config': config.toJson(),
      'format': format.id,
      'seed': config.seed,
      'openings': config.openingSuiteId,
      'engines': [
        for (final engine in engines)
          {
            'id': engine.engineId,
            'fingerprint': engine.fingerprint,
            'backend': engine.backend,
            'platform': engine.platform,
          }
      ],
    }));
    out.writeln('```');
    return out.toString();
  }

  String _excludedSummary() {
    final counts = <String, int>{};
    for (final game in games) {
      if (game.warmUp || game.outcome.isRatingEligible) continue;
      counts[game.outcome.id] = (counts[game.outcome.id] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'none were excluded.';
    return counts.entries.map((e) => '${e.value} ${e.key}').join(', ') + '.';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'config': config.toJson(),
        'format': format.id,
        'engines': [for (final engine in engines) engine.toJson()],
        'engineStatus': {
          for (final entry in engineStatus.entries) entry.key: entry.value.toJson(),
        },
        'games': [for (final game in games) game.toJson()],
        'ratings': ratings.toJson(),
        'calibration': calibration.toJson(),
        'environment': environment.toJson(),
        'stopReason': stopReason,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (validationWarnings.isNotEmpty)
          'validationWarnings': validationWarnings,
        if (trigger != null) 'trigger': trigger,
      };

  factory BenchmarkRun.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> mapsOf(String key) {
      final raw = json[key];
      final result = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is Map) result.add(Map<String, dynamic>.from(entry));
        }
      }
      return result;
    }

    List<String> stringsOf(String key) {
      final raw = json[key];
      final result = <String>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is String) result.add(entry);
        }
      }
      return result;
    }

    final status = <String, EngineRunStatus>{};
    final rawStatus = json['engineStatus'];
    if (rawStatus is Map) {
      rawStatus.forEach((key, value) {
        if (value is Map) {
          status['$key'] = EngineRunStatus.fromJson(
              Map<String, dynamic>.from(value));
        }
      });
    }

    final configJson = json['config'];
    final ratingsJson = json['ratings'];
    final calibrationJson = json['calibration'];
    final environmentJson = json['environment'];
    return BenchmarkRun(
      id: (json['id'] as String?) ?? 'unknown',
      startedAt: DateTime.tryParse((json['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: DateTime.tryParse((json['finishedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      config: configJson is Map
          ? BenchmarkConfig.fromJson(Map<String, dynamic>.from(configJson))
          : BenchmarkConfig.standard,
      format: (json['format'] as String?) == 'gauntlet'
          ? TournamentFormat.gauntlet
          : TournamentFormat.roundRobin,
      engines: [
        for (final engine in mapsOf('engines')) EngineIdentity.fromJson(engine),
      ],
      engineStatus: status,
      games: [for (final game in mapsOf('games')) BenchGame.fromJson(game)],
      ratings: ratingsJson is Map
          ? EloFit.fromJson(Map<String, dynamic>.from(ratingsJson))
          : EloFit.empty,
      calibration: calibrationJson is Map
          ? CalibrationOutcome.fromJson(
              Map<String, dynamic>.from(calibrationJson))
          : CalibrationOutcome.unavailable('Not recorded for this run.'),
      environment: environmentJson is Map
          ? BenchmarkEnvironment.fromJson(
              Map<String, dynamic>.from(environmentJson))
          : BenchmarkEnvironment.unknown,
      stopReason: (json['stopReason'] as String?) ?? 'completed',
      warnings: stringsOf('warnings'),
      validationWarnings: stringsOf('validationWarnings'),
      trigger: json['trigger'] as String?,
    );
  }

  /// Lightweight projection for the history list, so a leaderboard does not
  /// have to load every game of every run.
  BenchmarkRunSummary summary() => BenchmarkRunSummary(
        id: id,
        startedAt: startedAt,
        finishedAt: finishedAt,
        engineLabels: [for (final engine in engines) engine.label],
        engineIds: [for (final engine in engines) engine.engineId],
        preset: config.preset.id,
        gamesPlayed: gamesPlayed,
        ratedGames: gamesCompleted,
        forfeits: forfeits,
        aborted: aborted,
        stopReason: stopReason,
        trigger: trigger,
        ratings: {
          for (final rating in ratings.ratings)
            rating.engineId: rating.rating,
        },
        calibrated: calibration.calibrated,
        cohortKeys: {for (final engine in engines) engine.cohortKey}.toList(),
      );
}

/// Enough of a run to list, sort and filter it.
class BenchmarkRunSummary {
  final String id;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<String> engineLabels;
  final List<String> engineIds;
  final String preset;
  final int gamesPlayed;
  final int ratedGames;
  final int forfeits;
  final int aborted;
  final String stopReason;
  final String? trigger;
  final Map<String, double> ratings;
  final Map<String, double> calibrated;
  final List<String> cohortKeys;

  const BenchmarkRunSummary({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.engineLabels,
    required this.engineIds,
    required this.preset,
    required this.gamesPlayed,
    required this.ratedGames,
    required this.forfeits,
    required this.aborted,
    required this.stopReason,
    this.trigger,
    this.ratings = const {},
    this.calibrated = const {},
    this.cohortKeys = const [],
  });

  bool get isComparableAcrossCohorts => cohortKeys.length <= 1;

  Map<String, dynamic> toJson() => {
        'id': id,
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'engineLabels': engineLabels,
        'engineIds': engineIds,
        'preset': preset,
        'gamesPlayed': gamesPlayed,
        'ratedGames': ratedGames,
        'forfeits': forfeits,
        'aborted': aborted,
        'stopReason': stopReason,
        if (trigger != null) 'trigger': trigger,
        'ratings': ratings,
        'calibrated': calibrated,
        'cohortKeys': cohortKeys,
      };

  factory BenchmarkRunSummary.fromJson(Map<String, dynamic> json) {
    Map<String, double> doublesOf(String key) {
      final raw = json[key];
      final result = <String, double>{};
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is num) result['$k'] = v.toDouble();
        });
      }
      return result;
    }

    List<String> stringsOf(String key) {
      final raw = json[key];
      final result = <String>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is String) result.add(entry);
        }
      }
      return result;
    }

    int intOf(String key) {
      final value = json[key];
      return value is num ? value.toInt() : 0;
    }

    return BenchmarkRunSummary(
      id: (json['id'] as String?) ?? 'unknown',
      startedAt: DateTime.tryParse((json['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: DateTime.tryParse((json['finishedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      engineLabels: stringsOf('engineLabels'),
      engineIds: stringsOf('engineIds'),
      preset: (json['preset'] as String?) ?? '',
      gamesPlayed: intOf('gamesPlayed'),
      ratedGames: intOf('ratedGames'),
      forfeits: intOf('forfeits'),
      aborted: intOf('aborted'),
      stopReason: (json['stopReason'] as String?) ?? '',
      trigger: json['trigger'] as String?,
      ratings: doublesOf('ratings'),
      calibrated: doublesOf('calibrated'),
      cohortKeys: stringsOf('cohortKeys'),
    );
  }
}

/// Fits ratings for a set of games, with excluded outcomes counted.
EloFit fitRunRatings({
  required List<BenchGame> games,
  required Map<String, String> labels,
  required BenchmarkConfig config,
  double anchor = 1500,
  String? anchorEngineId,
}) {
  final rated = <RatedGame>[];
  final excluded = <String, int>{};
  for (final game in games) {
    if (game.warmUp) continue;
    final whiteScore = game.outcome.whiteScore;
    final eligible = game.outcome.isRatingEligible ||
        (game.outcome == GameOutcome.adjudicated &&
            config.countAdjudicatedAsDraws);
    if (!eligible || whiteScore == null) {
      excluded[game.outcome.id] = (excluded[game.outcome.id] ?? 0) + 1;
      continue;
    }
    rated.add(
        (white: game.whiteId, black: game.blackId, score: whiteScore));
  }
  return fitElo(
    games: rated,
    labels: labels,
    anchor: anchor,
    anchorPlayer: anchorEngineId,
    excludedByOutcome: excluded,
  );
}

String _csvEscape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _md(String value) => value.replaceAll('|', '\\|');

String _formatDuration(Duration duration) {
  if (duration.inMinutes < 1) return '${duration.inSeconds}s';
  if (duration.inHours < 1) return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
  return '${duration.inHours}h ${duration.inMinutes % 60}m';
}

/// Median of a list, used by the UI for quick latency readouts.
double median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle].toDouble();
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

/// clamp helper used by report rendering.
int clampedInt(int value, int low, int high) => math.min(math.max(value, low), high);
