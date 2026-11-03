/// User-selectable statistical objectives and non-wall-clock resource limits.
///
/// These values are stored with every intelligent run. They are objectives,
/// not promises: a run may stop at a budget boundary with the objective marked
/// unmet. No confidence interval is narrowed to make an objective look met.
library;

enum PrecisionObjective {
  individual,
  pairwise,
  both;

  String get id => name;
  static PrecisionObjective fromId(String? id) => values.firstWhere(
      (value) => value.id == id, orElse: () => PrecisionObjective.both);
}

enum PairwiseIntervalScope {
  pointwise,
  simultaneous;

  String get id => name;
  static PairwiseIntervalScope fromId(String? id) => values.firstWhere(
      (value) => value.id == id,
      orElse: () => PairwiseIntervalScope.pointwise);
}

enum PairwiseComparisonSet {
  allParticipants,
  targetPairs;

  String get id => name;
  static PairwiseComparisonSet fromId(String? id) => values.firstWhere(
      (value) => value.id == id,
      orElse: () => PairwiseComparisonSet.allParticipants);
}

class PrecisionSettings {
  final PrecisionObjective objective;
  final double confidenceLevel;
  final double individualToleranceElo;
  final double pairwiseToleranceElo;
  final PairwiseIntervalScope pairwiseScope;
  final PairwiseComparisonSet comparisonSet;

  const PrecisionSettings({
    this.objective = PrecisionObjective.both,
    this.confidenceLevel = 0.95,
    this.individualToleranceElo = 20,
    this.pairwiseToleranceElo = 20,
    this.pairwiseScope = PairwiseIntervalScope.pointwise,
    this.comparisonSet = PairwiseComparisonSet.allParticipants,
  });

  bool get wantsIndividual => objective != PrecisionObjective.pairwise;
  bool get wantsPairwise => objective != PrecisionObjective.individual;

  PrecisionSettings copyWith({
    PrecisionObjective? objective,
    double? confidenceLevel,
    double? individualToleranceElo,
    double? pairwiseToleranceElo,
    PairwiseIntervalScope? pairwiseScope,
    PairwiseComparisonSet? comparisonSet,
  }) => PrecisionSettings(
    objective: objective ?? this.objective,
    confidenceLevel: confidenceLevel ?? this.confidenceLevel,
    individualToleranceElo: individualToleranceElo ?? this.individualToleranceElo,
    pairwiseToleranceElo: pairwiseToleranceElo ?? this.pairwiseToleranceElo,
    pairwiseScope: pairwiseScope ?? this.pairwiseScope,
    comparisonSet: comparisonSet ?? this.comparisonSet,
  );

  List<String> validationErrors() => [
    if (!confidenceLevel.isFinite || confidenceLevel < 0.5 || confidenceLevel > 0.999)
      'Confidence level must be between 50% and 99.9%.',
    if (wantsIndividual && (!individualToleranceElo.isFinite ||
        individualToleranceElo < 1 || individualToleranceElo > 1000))
      'Individual Elo tolerance must be between 1 and 1000.',
    if (wantsPairwise && (!pairwiseToleranceElo.isFinite ||
        pairwiseToleranceElo < 1 || pairwiseToleranceElo > 1000))
      'Pairwise Elo tolerance must be between 1 and 1000.',
  ];

  String get summary {
    // 90% stays 90%, but 92.5% keeps its half point: a whole percentage is
    // written without a trailing '.0', not rounded to the nearest percent.
    final percent = confidenceLevel * 100;
    final confidence = '${percent == percent.roundToDouble() ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1)}%';
    final parts = <String>[
      if (wantsIndividual) 'individual ±${individualToleranceElo.toStringAsFixed(0)} Elo',
      if (wantsPairwise)
        'pairwise ±${pairwiseToleranceElo.toStringAsFixed(0)} Elo '
            '(${pairwiseScope.id}, ${comparisonSet.id})',
    ];
    return '$confidence ${parts.join(' and ')}';
  }

  Map<String, dynamic> toJson() => {
    'objective': objective.id,
    'confidenceLevel': confidenceLevel,
    'individualToleranceElo': individualToleranceElo,
    'pairwiseToleranceElo': pairwiseToleranceElo,
    'pairwiseScope': pairwiseScope.id,
    'comparisonSet': comparisonSet.id,
  };

  factory PrecisionSettings.fromJson(Map<String, dynamic> json) {
    double number(String key, double fallback) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }
    return PrecisionSettings(
      objective: PrecisionObjective.fromId(json['objective'] as String?),
      confidenceLevel: number('confidenceLevel', 0.95),
      individualToleranceElo: number('individualToleranceElo', 20),
      pairwiseToleranceElo: number('pairwiseToleranceElo', 20),
      pairwiseScope: PairwiseIntervalScope.fromId(json['pairwiseScope'] as String?),
      comparisonSet: PairwiseComparisonSet.fromId(json['comparisonSet'] as String?),
    );
  }
}

/// Additional resource boundaries. Game and wall-clock caps remain the
/// existing [BenchmarkConfig.maxGames]/[BenchmarkConfig.maxDuration] fields.
/// Null means the user did not impose that particular boundary.
class ResourceBudget {
  final int? maxEngineMillis;
  final int? maxBootstrapMillis;
  final int? maxMemoryMb;
  final int? maxGpuMillis;

  const ResourceBudget({
    this.maxEngineMillis,
    this.maxBootstrapMillis,
    this.maxMemoryMb,
    this.maxGpuMillis,
  });

  ResourceBudget copyWith({
    int? Function()? maxEngineMillis,
    int? Function()? maxBootstrapMillis,
    int? Function()? maxMemoryMb,
    int? Function()? maxGpuMillis,
  }) => ResourceBudget(
    maxEngineMillis: maxEngineMillis == null ? this.maxEngineMillis : maxEngineMillis(),
    maxBootstrapMillis: maxBootstrapMillis == null ? this.maxBootstrapMillis : maxBootstrapMillis(),
    maxMemoryMb: maxMemoryMb == null ? this.maxMemoryMb : maxMemoryMb(),
    maxGpuMillis: maxGpuMillis == null ? this.maxGpuMillis : maxGpuMillis(),
  );

  List<String> validationErrors() => [
    for (final entry in {
      'Engine compute budget': maxEngineMillis,
      'Bootstrap compute budget': maxBootstrapMillis,
      'Memory limit': maxMemoryMb,
      'GPU budget': maxGpuMillis,
    }.entries)
      if (entry.value != null && entry.value! <= 0)
        '${entry.key} must be positive when set.',
  ];

  Map<String, dynamic> toJson() => {
    if (maxEngineMillis != null) 'maxEngineMillis': maxEngineMillis,
    if (maxBootstrapMillis != null) 'maxBootstrapMillis': maxBootstrapMillis,
    if (maxMemoryMb != null) 'maxMemoryMb': maxMemoryMb,
    if (maxGpuMillis != null) 'maxGpuMillis': maxGpuMillis,
  };

  factory ResourceBudget.fromJson(Map<String, dynamic> json) {
    int? value(String key) {
      final raw = json[key];
      return raw is num ? raw.toInt() : null;
    }
    return ResourceBudget(
      maxEngineMillis: value('maxEngineMillis'),
      maxBootstrapMillis: value('maxBootstrapMillis'),
      maxMemoryMb: value('maxMemoryMb'),
      maxGpuMillis: value('maxGpuMillis'),
    );
  }
}
