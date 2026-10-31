/// What a benchmark is allowed to do, and what that costs.
///
/// Everything a run does is decided here and stored with the run, so a report
/// can be reproduced: same engines, same budgets, same openings, same seed.
library;

import 'dart:math' as math;

/// Benchmark presets. The times are defaults, not limits — a custom
/// configuration can use anything the validation below accepts.
enum BenchmarkPreset {
  quick,
  standard,
  accurate,
  custom;

  String get id => name;

  /// Per-move budget the preset uses.
  Duration get timePerMove => switch (this) {
        BenchmarkPreset.quick => const Duration(milliseconds: 100),
        BenchmarkPreset.standard => const Duration(milliseconds: 300),
        BenchmarkPreset.accurate => const Duration(milliseconds: 1000),
        BenchmarkPreset.custom => const Duration(milliseconds: 300),
      };

  /// One-line purpose, used by the UI.
  String get purpose => switch (this) {
        BenchmarkPreset.quick => 'Fast estimation',
        BenchmarkPreset.standard => 'General comparison',
        BenchmarkPreset.accurate => 'More extensive testing',
        BenchmarkPreset.custom => 'Flexible configuration',
      };

  /// Games per pairing (each pairing plays both colours).
  int get gamesPerPairing => switch (this) {
        BenchmarkPreset.quick => 2,
        BenchmarkPreset.standard => 4,
        BenchmarkPreset.accurate => 6,
        BenchmarkPreset.custom => 2,
      };

  /// Total games the preset will not exceed, whatever the pairings.
  int? get maxGames => switch (this) {
        BenchmarkPreset.quick => 60,
        BenchmarkPreset.standard => 240,
        BenchmarkPreset.accurate => 600,
        BenchmarkPreset.custom => null,
      };

  /// Target standard error for adaptive stopping, or null to play everything.
  double? get targetStdErr => switch (this) {
        BenchmarkPreset.quick => 100,
        BenchmarkPreset.standard => 60,
        BenchmarkPreset.accurate => 40,
        BenchmarkPreset.custom => null,
      };

  int get minGamesBeforeStopping => switch (this) {
        BenchmarkPreset.quick => 12,
        BenchmarkPreset.standard => 24,
        BenchmarkPreset.accurate => 60,
        BenchmarkPreset.custom => 0,
      };

  static BenchmarkPreset fromId(String? id) {
    for (final preset in BenchmarkPreset.values) {
      if (preset.id == id) return preset;
    }
    return BenchmarkPreset.standard;
  }
}

/// The full configuration of one benchmark.
class BenchmarkConfig {
  final BenchmarkPreset preset;

  /// Per-move time budget. Ignored when [searchDepth] is set.
  final Duration timePerMove;

  /// Fixed search depth instead of a time budget. Null means time-based, which
  /// is what makes two engines comparable on one machine: depth costs wildly
  /// different amounts of time for different engines.
  final int? searchDepth;

  /// `go nodes N`, when the engine honours it. Recorded as unsupported for
  /// engines that do not, rather than silently ignored.
  final int? nodeLimit;

  /// Games per pairing, both colours. Rounded up to an even number by
  /// validation when [balanceColors] is on.
  final int gamesPerPairing;

  /// Hard cap on games played, *including* warm-up games.
  ///
  /// The cap is the one number a user sets to bound a run, so it bounds the
  /// whole run: a configuration with `warmUpGames: 20` and `maxGames: 2` plays
  /// two games, not twenty-two. [effectiveWarmUpGames] is what resolves the
  /// two, and the planner, the estimate and the UI all use it, so they cannot
  /// disagree about what "max games" means.
  final int? maxGames;

  /// Hard cap on wall-clock duration.
  final Duration? maxDuration;

  /// Plies before a game is adjudicated. An adjudicated game is *not* a draw:
  /// it is excluded from the rating fit and reported separately.
  final int plyCap;

  /// Opening suite id (see `opening_suite.dart`).
  final String openingSuiteId;

  /// Seed for opening selection, so a run can be reproduced.
  final int seed;

  /// Games played before recording starts, to warm caches and JIT.
  final int warmUpGames;

  /// Both colours for every opening. Off only for a deliberately one-sided
  /// test; validation warns when it is off.
  final bool balanceColors;

  /// Requested threads; 0 keeps the engine's own value.
  final int threads;

  /// Requested hash size in MB; 0 keeps the engine's own value.
  final int hashMb;

  /// Extra `setoption` values applied to every engine that advertises them.
  final Map<String, String> optionOverrides;

  /// Whole-benchmark repetitions. The schedule is played [repetitions] times,
  /// each repetition with its own seed so the openings differ; the games of
  /// every repetition are fitted together.
  final int repetitions;

  /// Stop early once every rating's standard error is at or below this.
  final bool adaptiveStopping;

  /// The standard error an adaptive run aims for.
  final double? targetStdErr;

  /// Never stop before this many games, however confident the numbers look.
  final int minGamesBeforeStopping;

  /// Whether ply-cap adjudications count as draws in the fit. Off by default:
  /// an adjudicated game is an unfinished game, and counting it as a draw
  /// biases every rating toward the middle.
  final bool countAdjudicatedAsDraws;

  const BenchmarkConfig({
    required this.preset,
    required this.timePerMove,
    this.searchDepth,
    this.nodeLimit,
    required this.gamesPerPairing,
    this.maxGames,
    this.maxDuration,
    required this.plyCap,
    required this.openingSuiteId,
    required this.seed,
    this.warmUpGames = 1,
    this.balanceColors = true,
    this.threads = 0,
    this.hashMb = 0,
    this.optionOverrides = const {},
    this.repetitions = 1,
    required this.adaptiveStopping,
    this.targetStdErr,
    this.minGamesBeforeStopping = 0,
    this.countAdjudicatedAsDraws = false,
  });

  /// Fast estimation: short games, few of them, adaptive stop.
  static const BenchmarkConfig quick = BenchmarkConfig(
    preset: BenchmarkPreset.quick,
    timePerMove: Duration(milliseconds: 100),
    gamesPerPairing: 2,
    maxGames: 60,
    plyCap: 160,
    openingSuiteId: 'balanced-8',
    seed: 20261031,
    warmUpGames: 1,
    adaptiveStopping: true,
    targetStdErr: 100,
    minGamesBeforeStopping: 12,
  );

  /// General comparison.
  static const BenchmarkConfig standard = BenchmarkConfig(
    preset: BenchmarkPreset.standard,
    timePerMove: Duration(milliseconds: 300),
    gamesPerPairing: 4,
    maxGames: 240,
    plyCap: 200,
    openingSuiteId: 'balanced-8',
    seed: 20261031,
    warmUpGames: 1,
    adaptiveStopping: true,
    targetStdErr: 60,
    minGamesBeforeStopping: 24,
  );

  /// More extensive testing.
  static const BenchmarkConfig accurate = BenchmarkConfig(
    preset: BenchmarkPreset.accurate,
    timePerMove: Duration(milliseconds: 1000),
    gamesPerPairing: 6,
    maxGames: 600,
    plyCap: 240,
    openingSuiteId: 'balanced-8',
    seed: 20261031,
    warmUpGames: 2,
    adaptiveStopping: true,
    targetStdErr: 40,
    minGamesBeforeStopping: 60,
  );

  /// The configuration a preset stands for.
  static BenchmarkConfig forPreset(BenchmarkPreset preset) => switch (preset) {
        BenchmarkPreset.quick => quick,
        BenchmarkPreset.standard => standard,
        BenchmarkPreset.accurate => accurate,
        BenchmarkPreset.custom => customDefault(),
      };

  /// A custom configuration that already passes validation.
  static BenchmarkConfig customDefault() => BenchmarkConfig(
        preset: BenchmarkPreset.custom,
        timePerMove: const Duration(milliseconds: 300),
        gamesPerPairing: 4,
        plyCap: 200,
        openingSuiteId: 'balanced-8',
        seed: 20261031,
        warmUpGames: 1,
        adaptiveStopping: false,
      );

  /// Presets offered in the UI, in order.
  static const List<BenchmarkPreset> selectablePresets = [
    BenchmarkPreset.quick,
    BenchmarkPreset.standard,
    BenchmarkPreset.accurate,
    BenchmarkPreset.custom,
  ];

  /// Whether the search is bounded by time rather than a fixed depth.
  bool get isTimeBased => searchDepth == null && nodeLimit == null;

  /// The seed one repetition uses.
  ///
  /// Every repetition is a different sample: the same schedule with the same
  /// seed would replay the same openings and add no information. The stride is
  /// prime so consecutive seeds do not land on neighbouring openings in the
  /// suite's mixing function.
  int seedForRepetition(int repetition) =>
      seed + (repetition < 1 ? 0 : repetition * 7919);

  /// The single-line description of the strength test, for a report header.
  String get budgetLabel => nodeLimit != null
      ? 'nodes $nodeLimit'
      : searchDepth != null
      ? 'depth $searchDepth'
      : '${timePerMove.inMilliseconds} ms/move';

  BenchmarkConfig copyWith({
    BenchmarkPreset? preset,
    Duration? timePerMove,
    int? Function()? searchDepth,
    int? Function()? nodeLimit,
    int? gamesPerPairing,
    int? Function()? maxGames,
    Duration? Function()? maxDuration,
    int? plyCap,
    String? openingSuiteId,
    int? seed,
    int? warmUpGames,
    bool? balanceColors,
    int? threads,
    int? hashMb,
    Map<String, String>? optionOverrides,
    int? repetitions,
    bool? adaptiveStopping,
    double? Function()? targetStdErr,
    int? minGamesBeforeStopping,
    bool? countAdjudicatedAsDraws,
  }) =>
      BenchmarkConfig(
        preset: preset ?? this.preset,
        timePerMove: timePerMove ?? this.timePerMove,
        searchDepth: searchDepth == null ? this.searchDepth : searchDepth(),
        nodeLimit: nodeLimit == null ? this.nodeLimit : nodeLimit(),
        gamesPerPairing: gamesPerPairing ?? this.gamesPerPairing,
        maxGames: maxGames == null ? this.maxGames : maxGames(),
        maxDuration: maxDuration == null ? this.maxDuration : maxDuration(),
        plyCap: plyCap ?? this.plyCap,
        openingSuiteId: openingSuiteId ?? this.openingSuiteId,
        seed: seed ?? this.seed,
        warmUpGames: warmUpGames ?? this.warmUpGames,
        balanceColors: balanceColors ?? this.balanceColors,
        threads: threads ?? this.threads,
        hashMb: hashMb ?? this.hashMb,
        optionOverrides: optionOverrides ?? this.optionOverrides,
        repetitions: repetitions ?? this.repetitions,
        adaptiveStopping: adaptiveStopping ?? this.adaptiveStopping,
        targetStdErr: targetStdErr == null ? this.targetStdErr : targetStdErr(),
        minGamesBeforeStopping:
            minGamesBeforeStopping ?? this.minGamesBeforeStopping,
        countAdjudicatedAsDraws:
            countAdjudicatedAsDraws ?? this.countAdjudicatedAsDraws,
      );

  /// The `setoption` map this configuration asks for, before an engine's own
  /// advertised options are taken into account.
  Map<String, String> requestedOptions() {
    final options = <String, String>{};
    if (threads > 0) options['Threads'] = '$threads';
    if (hashMb > 0) options['Hash'] = '$hashMb';
    options.addAll(optionOverrides);
    return options;
  }

  Map<String, dynamic> toJson() => {
        'preset': preset.id,
        'timePerMoveMs': timePerMove.inMilliseconds,
        if (searchDepth != null) 'searchDepth': searchDepth,
        if (nodeLimit != null) 'nodeLimit': nodeLimit,
        'gamesPerPairing': gamesPerPairing,
        if (maxGames != null) 'maxGames': maxGames,
        if (maxDuration != null) 'maxDurationMs': maxDuration!.inMilliseconds,
        'plyCap': plyCap,
        'openingSuiteId': openingSuiteId,
        'seed': seed,
        'warmUpGames': warmUpGames,
        'balanceColors': balanceColors,
        'threads': threads,
        'hashMb': hashMb,
        if (optionOverrides.isNotEmpty) 'optionOverrides': optionOverrides,
        'repetitions': repetitions,
        'adaptiveStopping': adaptiveStopping,
        if (targetStdErr != null) 'targetStdErr': targetStdErr,
        'minGamesBeforeStopping': minGamesBeforeStopping,
        'countAdjudicatedAsDraws': countAdjudicatedAsDraws,
      };

  /// Reads a saved configuration, tolerating a document from an older version.
  factory BenchmarkConfig.fromJson(Map<String, dynamic> json) {
    int? intOf(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    double? doubleOf(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    final overrides = <String, String>{};
    final raw = json['optionOverrides'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value != null) overrides['$key'] = '$value';
      });
    }

    final fallback = standard;
    final maxDurationMs = intOf('maxDurationMs');
    return BenchmarkConfig(
      preset: BenchmarkPreset.fromId(json['preset'] as String?),
      timePerMove: Duration(
          milliseconds: intOf('timePerMoveMs') ?? fallback.timePerMove.inMilliseconds),
      searchDepth: intOf('searchDepth'),
      nodeLimit: intOf('nodeLimit'),
      gamesPerPairing: intOf('gamesPerPairing') ?? fallback.gamesPerPairing,
      maxGames: intOf('maxGames'),
      maxDuration:
          maxDurationMs == null ? null : Duration(milliseconds: maxDurationMs),
      plyCap: intOf('plyCap') ?? fallback.plyCap,
      openingSuiteId:
          (json['openingSuiteId'] as String?) ?? fallback.openingSuiteId,
      seed: intOf('seed') ?? fallback.seed,
      warmUpGames: intOf('warmUpGames') ?? fallback.warmUpGames,
      balanceColors: json['balanceColors'] is bool
          ? json['balanceColors'] as bool
          : fallback.balanceColors,
      threads: intOf('threads') ?? 0,
      hashMb: intOf('hashMb') ?? 0,
      optionOverrides: overrides,
      repetitions: math.max(1, intOf('repetitions') ?? 1),
      adaptiveStopping: json['adaptiveStopping'] is bool
          ? json['adaptiveStopping'] as bool
          : fallback.adaptiveStopping,
      targetStdErr: doubleOf('targetStdErr'),
      minGamesBeforeStopping: intOf('minGamesBeforeStopping') ?? 0,
      countAdjudicatedAsDraws: json['countAdjudicatedAsDraws'] == true,
    );
  }

  /// Short human summary, used in lists and reports.
  String get summary {
    final parts = <String>[
      budgetLabel,
      '$gamesPerPairing game(s) per pairing',
      'ply cap $plyCap',
      'openings: $openingSuiteId',
      if (threads > 0) 'threads $threads',
      if (hashMb > 0) 'hash $hashMb MB',
      if (maxGames != null) 'max $maxGames games (warm-ups included)',
      if (repetitions > 1) '$repetitions repetitions',
      if (adaptiveStopping && targetStdErr != null)
        'adaptive to SE ${targetStdErr!.toStringAsFixed(0)}',
    ];
    return parts.join(' · ');
  }
}

/// Outcome of validating a configuration against the engines it will be run on.
class BenchmarkValidation {
  final List<String> errors;
  final List<String> warnings;

  const BenchmarkValidation({this.errors = const [], this.warnings = const []});

  bool get isValid => errors.isEmpty;

  bool get hasWarnings => warnings.isNotEmpty;

  BenchmarkValidation merge(BenchmarkValidation other) => BenchmarkValidation(
        errors: [...errors, ...other.errors],
        warnings: [...warnings, ...other.warnings],
      );

  @override
  String toString() =>
      'BenchmarkValidation(errors: $errors, warnings: $warnings)';
}

/// What an engine advertises, for deciding whether a requested option can be
/// applied at all.
class EngineCapabilities {
  /// Option names the engine advertised, in its own casing.
  final List<String> optionNames;

  /// Whether the engine reports node counters (`nodes`/`nps`) in its output.
  final bool reportsNodeCounts;

  const EngineCapabilities({
    this.optionNames = const [],
    this.reportsNodeCounts = false,
  });

  static const EngineCapabilities unknown =
      EngineCapabilities(optionNames: [], reportsNodeCounts: false);

  bool advertises(String name) {
    final wanted = name.toLowerCase();
    return optionNames.any((o) => o.toLowerCase() == wanted);
  }
}

/// Validates a configuration on its own terms. Independent of any engine, so a
/// configuration can be checked before engines are even initialised.
BenchmarkValidation validateConfig(
  BenchmarkConfig config, {
  required int engineCount,
}) {
  final errors = <String>[];
  final warnings = <String>[];

  if (engineCount < 2) {
    errors.add('Select at least two engines.');
  }
  if (config.timePerMove.inMilliseconds < 10) {
    errors.add('Time per move must be at least 10 ms.');
  }
  if (config.timePerMove.inMilliseconds > 60000) {
    errors.add('Time per move cannot exceed 60 s.');
  }
  if (config.searchDepth != null) {
    if (config.searchDepth! < 1 || config.searchDepth! > 60) {
      errors.add('Search depth must be between 1 and 60.');
    }
    warnings.add(
        'A fixed depth is measured on this machine only: two engines at the '
        'same depth spend very different amounts of time. Time per move is '
        'the comparable budget for a rating.');
  }
  if (config.nodeLimit != null && config.searchDepth != null) {
    errors.add('Choose either a node limit or a depth limit, not both.');
  }
  if (config.nodeLimit != null && config.nodeLimit! < 1000) {
    errors.add('Node limit must be at least 1,000.');
  }
  if (config.gamesPerPairing < 1) {
    errors.add('At least one game per pairing is required.');
  }
  if (config.gamesPerPairing > 100) {
    errors.add('At most 100 games per pairing.');
  }
  if (config.balanceColors && config.gamesPerPairing.isOdd) {
    warnings.add(
        'An odd number of games per pairing cannot be colour-balanced; one '
        'more game is added so each engine plays White equally often.');
  }
  if (!config.balanceColors) {
    warnings.add(
        "Colour balance is off: a rating from unbalanced colours compares "
        "White's advantage as much as the engines.");
  }
  if (config.plyCap < 40 || config.plyCap > 600) {
    errors.add('Ply limit must be between 40 and 600.');
  }
  if (config.seed < 0) {
    errors.add('Seed must be zero or positive.');
  }
  if (config.warmUpGames < 0 || config.warmUpGames > 20) {
    errors.add('Warm-up games must be between 0 and 20.');
  }
  if (config.threads < 0 || config.threads > 256) {
    errors.add('Threads must be between 0 (engine default) and 256.');
  }
  if (config.hashMb < 0 || config.hashMb > 65536) {
    errors.add('Hash must be between 0 (engine default) and 65536 MB.');
  }
  if (config.maxGames != null && config.maxGames! < 2) {
    errors.add('A game cap below 2 cannot produce a comparison.');
  }
  if (config.maxDuration != null &&
      config.maxDuration!.inSeconds < 10) {
    errors.add('A time cap below 10 s cannot produce a comparison.');
  }
  if (config.repetitions < 1 || config.repetitions > 50) {
    errors.add('Repetitions must be between 1 and 50.');
  }
  if (config.adaptiveStopping) {
    final target = config.targetStdErr;
    if (target == null || target <= 0) {
      errors.add('Adaptive stopping needs a positive uncertainty target.');
    } else if (target < 10) {
      warnings.add(
          'A standard error below 10 Elo needs thousands of games; the run '
          'will almost certainly hit its game cap first.');
    } else if (target > 200) {
      warnings.add(
          'A standard error above 200 Elo stops almost immediately; the '
          'rating will be little better than a guess.');
    }
    if (config.minGamesBeforeStopping < 0) {
      errors.add('Minimum games before stopping cannot be negative.');
    }
  }
  if (config.maxGames != null && engineCount >= 2) {
    final mandatory = mandatoryGames(engineCount, config);
    final warmUps = effectiveWarmUpGames(config);
    if (warmUps < config.warmUpGames) {
      warnings.add(
          'The game cap of ${config.maxGames} covers warm-up games too, so '
          'only $warmUps of the ${config.warmUpGames} requested warm-ups are '
          'played and the rest of the cap funds games that count.');
    }
    if (mandatory > effectiveRecordedGameCap(config)!) {
      warnings.add(
          'The game cap ($mandatory needed for one full round, repetitions '
          'included) is smaller than one round of the selected format; the run '
          'stops after the cap and leaves pairings unplayed.');
    }
  }
  if (config.optionOverrides.isNotEmpty) {
    warnings.add(
        'Option overrides apply to every engine in the run; an engine that '
        'does not advertise one ignores it silently and the report records '
        'that.');
  }

  return BenchmarkValidation(errors: errors, warnings: warnings);
}

/// Games needed for each pairing to play its first game, over every
/// repetition.
int mandatoryGames(
  int engineCount,
  BenchmarkConfig config, {
  int? pairings,
}) =>
    (pairings ?? (engineCount * (engineCount - 1) ~/ 2)) *
    effectiveGamesPerPairing(config) *
    math.max(1, config.repetitions);

/// Games per pairing after colour balancing has been applied.
///
/// The planner and the estimate both need this: an odd number of games cannot
/// split evenly between the two colours, so the plan plays one more.
int effectiveGamesPerPairing(BenchmarkConfig config) {
  final requested = math.max(1, config.gamesPerPairing);
  return config.balanceColors && requested.isOdd ? requested + 1 : requested;
}

/// Warm-up games a run really plays.
///
/// [BenchmarkConfig.maxGames] bounds the whole run, warm-ups included, so the
/// warm-ups are trimmed when the cap leaves no room for them. Two games are
/// kept in reserve: a cap that spends every game on warm-ups would produce a
/// run with no evidence in it.
int effectiveWarmUpGames(BenchmarkConfig config) {
  final requested = math.max(0, config.warmUpGames);
  final cap = config.maxGames;
  if (cap == null) return requested;
  final available = cap - 2;
  if (available <= 0) return 0;
  return math.min(requested, available);
}

/// Recorded games a run may still play under the cap; null means no cap.
int? effectiveRecordedGameCap(BenchmarkConfig config) {
  final cap = config.maxGames;
  if (cap == null) return null;
  final warmUps = effectiveWarmUpGames(config);
  return math.max(0, cap - warmUps);
}

/// Per-engine warnings: settings this particular engine cannot honour.
List<String> configWarningsForEngine(
  BenchmarkConfig config,
  EngineCapabilities capabilities,
  String label,
) {
  final warnings = <String>[];
  for (final entry in config.requestedOptions().entries) {
    if (!capabilities.advertises(entry.key)) {
      warnings.add('$label does not advertise the "${entry.key}" option; '
          '"${entry.key} = ${entry.value}" is ignored for it.');
    }
  }
  if (config.nodeLimit != null && !capabilities.reportsNodeCounts) {
    warnings.add('$label does not report node counts; the node limit cannot '
        'be verified and is recorded as unsupported.');
  }
  return warnings;
}

/// How big a run is, before it starts.
class WorkloadEstimate {
  /// Games the configuration will attempt.
  final int plannedGames;

  /// Games that will actually be scored, allowing for the game cap.
  final int scoredGames;

  /// Warm-up games the run will play; they count against the cap but are not
  /// rated.
  final int warmUpGames;

  /// Expected wall-clock duration.
  final Duration estimated;

  /// Duration if every game runs to the ply cap.
  final Duration worstCase;

  final int estimatedPliesPerGame;
  final List<String> notes;

  const WorkloadEstimate({
    required this.plannedGames,
    required this.scoredGames,
    required this.estimated,
    required this.worstCase,
    required this.estimatedPliesPerGame,
    this.warmUpGames = 0,
    this.notes = const [],
  });

  /// Every game the run will start, warm-ups included.
  int get totalGames => scoredGames + warmUpGames;
}

/// Estimates the size of a run from [pairings] (each pairing plays
/// [BenchmarkConfig.gamesPerPairing] games) and [engineCount].
///
/// Every number here comes from the same helpers the planner uses
/// ([effectiveGamesPerPairing], [effectiveWarmUpGames],
/// [effectiveRecordedGameCap]) so the dialog that asks "start this run?" cannot
/// promise a different run from the one that then happens.
WorkloadEstimate estimateWorkload(
  BenchmarkConfig config, {
  required int engineCount,
  required int pairings,
}) {
  final perPairing = effectiveGamesPerPairing(config);
  final repetitions = math.max(1, config.repetitions);
  final planned = pairings * perPairing * repetitions;
  final warmUps = effectiveWarmUpGames(config);
  final recordedCap = effectiveRecordedGameCap(config);
  final scored = recordedCap == null ? planned : math.min(planned, recordedCap);

  // A game of engine chess at a fixed budget ends around 70-100 plies; the
  // cap is the upper bound, not the expectation.
  final expectedPlies = math.min(config.plyCap, 90);
  final moveMs = config.searchDepth != null
      // At a fixed depth, a rough expectation: depth d costs roughly
      // 2^(d/2) * 30 ms for a strong engine, clipped to something sane.
      ? math.min(60000, math.pow(2, config.searchDepth! / 2) * 30 ~/ 1).toInt()
      : config.timePerMove.inMilliseconds;
  const overheadPerMoveMs = 8;
  final perGameMs = expectedPlies * (moveMs + overheadPerMoveMs);
  final warmUpMs = warmUps * perGameMs;
  final initMs = engineCount * 1500;

  final notes = <String>[
    'assumes ${expectedPlies.clamp(0, config.plyCap)} plies per game',
    if (config.searchDepth != null)
      'depth-based budgets are an estimate, not a guarantee',
    if (config.nodeLimit != null)
      'node budgets have engine-dependent timing; the clock-based duration shown is only a planning approximation',
    if (warmUps < config.warmUpGames)
      'the game cap leaves room for $warmUps warm-up game(s), not '
          '${config.warmUpGames}',
  ];
  if (recordedCap != null && planned > recordedCap) {
    notes.add('the game cap stops the run after $scored scored game(s) '
        '(warm-ups included in the cap), so some pairings will not complete');
  }
  if (config.adaptiveStopping) {
    notes.add('adaptive stopping may end the run sooner');
  }
  if (config.maxDuration != null) {
    notes.add('the wall-clock cap ends the run after ${config.maxDuration!.inMinutes} '
        'minute(s), even mid-game');
  }

  return WorkloadEstimate(
    plannedGames: planned,
    scoredGames: scored,
    warmUpGames: warmUps,
    estimated: Duration(
        milliseconds: initMs + warmUpMs + (scored * perGameMs).round()),
    worstCase: Duration(
        milliseconds:
            initMs + warmUpMs + (scored * config.plyCap * (moveMs + overheadPerMoveMs))),
    estimatedPliesPerGame: expectedPlies,
    notes: notes,
  );
}
