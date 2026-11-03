/// Opening-cluster bootstrap for the joint Bradley–Terry model.
///
/// The resampling unit is the opening position, not the game. All games that
/// share an opening — across matchups, repetitions and colour reversals — are
/// drawn together. Every valid replicate refits the same joint model used for
/// the point estimate. Failed/singular/disconnected replicates are counted and
/// can make the whole interval estimate unreliable; they are not hidden.
library;

import 'dart:math' as math;

import '../services/rating_fit.dart';
import 'precision.dart';
import 'bootstrap_worker.dart' as worker;

class ClusteredRatedGame {
  final String clusterId;
  final String white;
  final String black;
  final double score;
  final String? pairId;

  const ClusteredRatedGame({
    required this.clusterId,
    required this.white,
    required this.black,
    required this.score,
    this.pairId,
  });
}

class BootstrapSettings {
  final int replicates;
  final int maxReplicates;
  final int minValidReplicates;
  final int minClusters;
  final int seed;

  const BootstrapSettings({
    this.replicates = 1000,
    this.maxReplicates = 4000,
    this.minValidReplicates = 399,
    this.minClusters = 20,
    this.seed = 20261103,
  });

  BootstrapSettings copyWith({int? replicates, int? maxReplicates, int? seed}) =>
      BootstrapSettings(
        replicates: replicates ?? this.replicates,
        maxReplicates: maxReplicates ?? this.maxReplicates,
        minValidReplicates: minValidReplicates,
        minClusters: minClusters,
        seed: seed ?? this.seed,
      );

  Map<String, dynamic> toJson() => {
    'replicates': replicates,
    'maxReplicates': maxReplicates,
    'minValidReplicates': minValidReplicates,
    'minClusters': minClusters,
    'seed': seed,
  };
}

class BootstrapInterval {
  final double low;
  final double high;
  final double? standardError;
  const BootstrapInterval(this.low, this.high, {this.standardError});
  double get halfWidth => (high - low) / 2;
  bool get isFinite => low.isFinite && high.isFinite;
  Map<String, dynamic> toJson() => {
    'low': low.isFinite ? low : null,
    'high': high.isFinite ? high : null,
    if (standardError != null && standardError!.isFinite) 'stdErr': standardError,
  };
  factory BootstrapInterval.fromJson(Map<String, dynamic> json) => BootstrapInterval(
    (json['low'] as num?)?.toDouble() ?? double.negativeInfinity,
    (json['high'] as num?)?.toDouble() ?? double.infinity,
    standardError: (json['stdErr'] as num?)?.toDouble(),
  );
}

class PairwiseBootstrapInterval {
  final String a;
  final String b;
  final double difference;
  final BootstrapInterval pointwise;
  final BootstrapInterval simultaneous;
  const PairwiseBootstrapInterval({
    required this.a, required this.b, required this.difference,
    required this.pointwise, required this.simultaneous,
  });
  BootstrapInterval interval(PairwiseIntervalScope scope) =>
      scope == PairwiseIntervalScope.simultaneous ? simultaneous : pointwise;
  Map<String, dynamic> toJson() => {
    'a': a, 'b': b, 'difference': difference,
    'pointwise': pointwise.toJson(), 'simultaneous': simultaneous.toJson(),
  };
  factory PairwiseBootstrapInterval.fromJson(Map<String, dynamic> json) =>
      PairwiseBootstrapInterval(
        a: json['a'] as String? ?? '', b: json['b'] as String? ?? '',
        difference: (json['difference'] as num?)?.toDouble() ?? 0,
        pointwise: BootstrapInterval.fromJson(Map<String, dynamic>.from(json['pointwise'] as Map? ?? {})),
        simultaneous: BootstrapInterval.fromJson(Map<String, dynamic>.from(json['simultaneous'] as Map? ?? {})),
      );
}

String pairwiseKey(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a\u0000$b' : '$b\u0000$a';

class ClusterBootstrapReport {
  final bool reliable;
  final String method;
  final double confidenceLevel;
  final int clusters;
  final int attemptedReplicates;
  final int validReplicates;
  final int failedReplicates;
  final Map<String, int> failureReasons;
  final Map<String, BootstrapInterval> individual;
  final Map<String, PairwiseBootstrapInterval> pairwise;
  final List<String> warnings;
  final int computeMillis;
  final int seed;
  final double maxEndpointMonteCarloRange;
  final bool completed;
  final PrecisionSettings precision;

  const ClusterBootstrapReport({
    required this.reliable,
    required this.method,
    required this.confidenceLevel,
    required this.clusters,
    required this.attemptedReplicates,
    required this.validReplicates,
    required this.failedReplicates,
    required this.failureReasons,
    required this.individual,
    required this.pairwise,
    required this.warnings,
    required this.computeMillis,
    required this.seed,
    required this.maxEndpointMonteCarloRange,
    required this.completed,
    required this.precision,
  });

  factory ClusterBootstrapReport.unavailable({
    required String reason,
    required PrecisionSettings precision,
    int clusters = 0,
    int computeMillis = 0,
    int seed = 0,
  }) => ClusterBootstrapReport(
    reliable: false, method: 'opening-cluster-bootstrap',
    confidenceLevel: precision.confidenceLevel,
    clusters: clusters, attemptedReplicates: 0, validReplicates: 0,
    failedReplicates: 0, failureReasons: {'unavailable': 1},
    individual: const {}, pairwise: const {}, warnings: [reason],
    computeMillis: computeMillis, seed: seed,
    maxEndpointMonteCarloRange: double.infinity, completed: false,
    precision: precision,
  );

  double get validFraction => attemptedReplicates == 0 ? 0 : validReplicates / attemptedReplicates;

  double maxIndividualHalfWidth() {
    var worst = 0.0;
    for (final interval in individual.values) {
      if (!interval.isFinite) return double.infinity;
      worst = math.max(worst, interval.halfWidth);
    }
    return individual.isEmpty ? double.infinity : worst;
  }

  double maxPairwiseHalfWidth(PairwiseIntervalScope scope) {
    var worst = 0.0;
    for (final interval in pairwise.values) {
      final selected = interval.interval(scope);
      if (!selected.isFinite) return double.infinity;
      worst = math.max(worst, selected.halfWidth);
    }
    return pairwise.isEmpty ? double.infinity : worst;
  }

  bool monteCarloAdequate(double toleranceElo) =>
      maxEndpointMonteCarloRange.isFinite &&
      maxEndpointMonteCarloRange <= math.max(1.0, toleranceElo * 0.2);

  Map<String, dynamic> toJson() => {
    'reliable': reliable,
    'method': method,
    'confidenceLevel': confidenceLevel,
    'clusters': clusters,
    'attemptedReplicates': attemptedReplicates,
    'validReplicates': validReplicates,
    'failedReplicates': failedReplicates,
    'failureReasons': failureReasons,
    'individual': {for (final e in individual.entries) e.key: e.value.toJson()},
    'pairwise': {for (final e in pairwise.entries) e.key: e.value.toJson()},
    'warnings': warnings,
    'computeMillis': computeMillis,
    'seed': seed,
    'maxEndpointMonteCarloRange': maxEndpointMonteCarloRange.isFinite ? maxEndpointMonteCarloRange : null,
    'completed': completed,
    'precision': precision.toJson(),
  };

  factory ClusterBootstrapReport.fromJson(Map<String, dynamic> json) => ClusterBootstrapReport(
    reliable: json['reliable'] == true,
    method: json['method'] as String? ?? 'opening-cluster-bootstrap',
    confidenceLevel: (json['confidenceLevel'] as num?)?.toDouble() ?? 0.95,
    clusters: (json['clusters'] as num?)?.toInt() ?? 0,
    attemptedReplicates: (json['attemptedReplicates'] as num?)?.toInt() ?? 0,
    validReplicates: (json['validReplicates'] as num?)?.toInt() ?? 0,
    failedReplicates: (json['failedReplicates'] as num?)?.toInt() ?? 0,
    failureReasons: {for (final e in (json['failureReasons'] as Map? ?? {}).entries) '${e.key}': (e.value as num).toInt()},
    individual: {for (final e in (json['individual'] as Map? ?? {}).entries) '${e.key}': BootstrapInterval.fromJson(Map<String, dynamic>.from(e.value as Map))},
    pairwise: {for (final e in (json['pairwise'] as Map? ?? {}).entries) '${e.key}': PairwiseBootstrapInterval.fromJson(Map<String, dynamic>.from(e.value as Map))},
    warnings: [for (final w in (json['warnings'] as List? ?? [])) '$w'],
    computeMillis: (json['computeMillis'] as num?)?.toInt() ?? 0,
    seed: (json['seed'] as num?)?.toInt() ?? 0,
    maxEndpointMonteCarloRange: (json['maxEndpointMonteCarloRange'] as num?)?.toDouble() ?? double.infinity,
    completed: json['completed'] == true,
    precision: PrecisionSettings.fromJson(Map<String, dynamic>.from(json['precision'] as Map? ?? {})),
  );
}

/// Request for one isolate batch. All fields are plain sendable Dart data.
class BootstrapBatchRequest {
  final List<String> participants;
  final List<RatingTally> clusterTallies;
  final List<List<String>> originalComponents;
  final int start;
  final int count;
  final int seed;
  const BootstrapBatchRequest({
    required this.participants, required this.clusterTallies,
    required this.originalComponents, required this.start,
    required this.count, required this.seed,
  });
}

class BootstrapBatchResult {
  final List<List<double>> samples;
  final Map<String, int> failures;
  const BootstrapBatchResult(this.samples, this.failures);
}

/// Pure batch computation, also used directly by deterministic tests.
BootstrapBatchResult computeBootstrapBatch(BootstrapBatchRequest request) {
  final samples = <List<double>>[];
  final failures = <String, int>{};
  final random = math.Random(request.seed);
  // Advance the PRNG to the batch's first replicate without storing a huge
  // state; batches remain reproducible when run in order.
  for (var i = 0; i < request.start; i++) {
    for (var c = 0; c < request.clusterTallies.length; c++) {
      random.nextInt(request.clusterTallies.length);
    }
  }
  for (var rep = 0; rep < request.count; rep++) {
    final tally = RatingTally(request.participants);
    for (var c = 0; c < request.clusterTallies.length; c++) {
      final draw = random.nextInt(request.clusterTallies.length);
      tally.addFrom(request.clusterTallies[draw]);
    }
    final fit = fitRatingModelFromTally(tally, prior: 0.3, maxIterations: 2000);
    String? failure;
    if (!fit.converged) failure = 'nonconverged';
    if (fit.separated) failure = 'separated';
    if (fit.components.length != request.originalComponents.length) {
      failure = 'disconnected';
    } else {
      for (final component in request.originalComponents) {
        final first = component.first;
        if (component.any((id) => !fit.connected(first, id))) {
          failure = 'disconnected';
          break;
        }
      }
    }
    if (failure == null && fit.ratings.any((r) => !r.stdErr.isFinite)) {
      failure = 'singular';
    }
    if (failure != null) {
      failures[failure] = (failures[failure] ?? 0) + 1;
      continue;
    }
    final byId = {for (final r in fit.ratings) r.name: r.rating};
    samples.add([for (final id in request.participants) byId[id]!]);
  }
  return BootstrapBatchResult(samples, failures);
}

/// Runs the bootstrap in cancellable batches. Native platforms use a worker
/// isolate per batch; web uses small asynchronous batches because dart:isolate
/// is unavailable there. The caller checks wall/compute budgets between batches.
Future<ClusterBootstrapReport> runClusterBootstrap({
  required List<ClusteredRatedGame> games,
  required Iterable<String> participants,
  required PrecisionSettings precision,
  BootstrapSettings settings = const BootstrapSettings(),
  List<String> targetIds = const [],
  Duration? maxDuration,
  bool Function()? cancelled,
}) async {
  final clock = Stopwatch()..start();
  final ids = <String>{...participants, for (final g in games) ...[g.white, g.black]}.toList()..sort();
  final original = fitRatingModel(
    [for (final g in games) (white: g.white, black: g.black, score: g.score)],
    participants: ids,
  );
  final clusterMap = <String, RatingTally>{};
  for (final game in games) {
    final tally = clusterMap.putIfAbsent(game.clusterId, () => RatingTally(ids));
    tally.add(game.white, game.black, game.score);
  }
  final clusters = clusterMap.values.toList();
  if (ids.length < 2 || games.isEmpty) {
    return ClusterBootstrapReport.unavailable(reason: 'No rated comparison is available.', precision: precision, clusters: clusters.length, computeMillis: clock.elapsedMilliseconds, seed: settings.seed);
  }
  if (clusters.length < settings.minClusters) {
    return ClusterBootstrapReport.unavailable(reason: 'Only ${clusters.length} independent opening clusters; at least ${settings.minClusters} are required.', precision: precision, clusters: clusters.length, computeMillis: clock.elapsedMilliseconds, seed: settings.seed);
  }
  if (!original.converged || original.separated) {
    return ClusterBootstrapReport.unavailable(reason: 'The observed fit is separated or did not converge; bootstrap intervals are not trustworthy.', precision: precision, clusters: clusters.length, computeMillis: clock.elapsedMilliseconds, seed: settings.seed);
  }
  final samples = <List<double>>[];
  final failures = <String, int>{};
  var attempted = 0;
  final target = math.max(settings.minValidReplicates, settings.replicates);
  final batchSize = worker.bootstrapBatchSize;
  var completed = true;
  while (attempted < target) {
    if (cancelled?.call() ?? false) { completed = false; break; }
    if (maxDuration != null && clock.elapsed >= maxDuration) { completed = false; break; }
    final count = math.min(batchSize, target - attempted);
    final result = await worker.runBootstrapBatch(BootstrapBatchRequest(
      participants: ids, clusterTallies: clusters,
      originalComponents: original.components,
      start: attempted, count: count, seed: settings.seed,
    ));
    samples.addAll(result.samples);
    for (final e in result.failures.entries) {
      failures[e.key] = (failures[e.key] ?? 0) + e.value;
    }
    attempted += count;
    await Future<void>.delayed(Duration.zero);
  }
  final valid = samples.length;
  final failed = attempted - valid;
  final warnings = <String>[];
  var reliable = completed && valid >= settings.minValidReplicates && attempted > 0 && valid / attempted >= 0.95;
  if (!completed) warnings.add('Bootstrap stopped before its replicate target; intervals are not a completed precision estimate.');
  if (valid < settings.minValidReplicates) warnings.add('Only $valid valid replicates; at least ${settings.minValidReplicates} are required.');
  if (attempted > 0 && valid / attempted < 0.95) warnings.add('${(100 * failed / attempted).toStringAsFixed(1)}% of replicates failed; surviving replicates are not treated as a clean sample.');
  if (failed > 0) warnings.add('$failed replicate(s) failed validity checks and were not used.');

  final individual = <String, BootstrapInterval>{};
  final pairwise = <String, PairwiseBootstrapInterval>{};
  var mcRange = double.infinity;
  if (valid > 0) {
    final alpha = 1 - precision.confidenceLevel;
    for (var i = 0; i < ids.length; i++) {
      final values = [for (final sample in samples) sample[i]]..sort();
      individual[ids[i]] = _percentile(values, alpha, _mean(samples.map((s) => s[i])));
    }
    final point = {for (final r in original.ratings) r.name: r.rating};
    final pairs = <(String, String)>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        if (!original.connected(a, b)) continue;
        if (precision.comparisonSet == PairwiseComparisonSet.targetPairs &&
            !(targetIds.contains(a) && targetIds.contains(b))) continue;
        pairs.add((a, b));
      }
    }
    final maxErrors = List<double>.filled(valid, 0);
    final diffSamples = <String, List<double>>{};
    for (final pair in pairs) {
      final ia = ids.indexOf(pair.$1), ib = ids.indexOf(pair.$2);
      final diff = point[pair.$1]! - point[pair.$2]!;
      final values = [for (final sample in samples) sample[ia] - sample[ib]];
      diffSamples[pairwiseKey(pair.$1, pair.$2)] = values;
      for (var r = 0; r < valid; r++) {
        maxErrors[r] = math.max(maxErrors[r], (values[r] - diff).abs());
      }
    }
    final sortedMax = List<double>.of(maxErrors)..sort();
    final simultaneousHalf = valid == 0 ? double.infinity : _quantile(sortedMax, precision.confidenceLevel);
    mcRange = _endpointMonteCarloRange(sortedMax, precision.confidenceLevel);
    for (final pair in pairs) {
      final key = pairwiseKey(pair.$1, pair.$2);
      final values = List<double>.of(diffSamples[key]!)..sort();
      final diff = point[pair.$1]! - point[pair.$2]!;
      final pointwise = _percentile(values, alpha, _mean(values));
      final endpointRange = math.max(
        _endpointMonteCarloRange(values, alpha / 2),
        _endpointMonteCarloRange(values, 1 - alpha / 2),
      );
      mcRange = math.max(mcRange, endpointRange);
      final low = math.min(pointwise.low, diff - simultaneousHalf);
      final high = math.max(pointwise.high, diff + simultaneousHalf);
      pairwise[key] = PairwiseBootstrapInterval(
        a: pair.$1, b: pair.$2, difference: diff, pointwise: pointwise,
        simultaneous: BootstrapInterval(low, high, standardError: pointwise.standardError),
      );
    }
    if (precision.comparisonSet == PairwiseComparisonSet.allParticipants &&
        original.components.length > 1) {
      warnings.add('Cross-component differences have no bootstrap interval and cannot meet a pairwise objective.');
      reliable = false;
    }
  } else {
    reliable = false;
  }
  if (reliable && mcRange.isFinite) {
    warnings.add('Bootstrap endpoint Monte Carlo range is at most ${mcRange.toStringAsFixed(2)} Elo; increase replicates if this is large relative to the tolerance.');
  }
  return ClusterBootstrapReport(
    reliable: reliable,
    method: 'opening-cluster percentile bootstrap; simultaneous pairwise intervals use the maximum absolute contrast error',
    confidenceLevel: precision.confidenceLevel,
    clusters: clusters.length, attemptedReplicates: attempted,
    validReplicates: valid, failedReplicates: failed,
    failureReasons: failures, individual: individual, pairwise: pairwise,
    warnings: warnings, computeMillis: clock.elapsedMilliseconds,
    seed: settings.seed, maxEndpointMonteCarloRange: mcRange,
    completed: completed, precision: precision,
  );
}

double _mean(Iterable<double> values) {
  var sum = 0.0, n = 0;
  for (final value in values) { sum += value; n++; }
  return n == 0 ? double.nan : sum / n;
}

double _quantile(List<double> sorted, double q) {
  if (sorted.isEmpty) return double.nan;
  final position = (sorted.length - 1) * q.clamp(0.0, 1.0);
  final low = position.floor(), high = position.ceil();
  if (low == high) return sorted[low];
  return sorted[low] + (sorted[high] - sorted[low]) * (position - low);
}

BootstrapInterval _percentile(List<double> sorted, double alpha, double mean) {
  final low = _quantile(sorted, alpha / 2);
  final high = _quantile(sorted, 1 - alpha / 2);
  var variance = 0.0;
  for (final value in sorted) {
    variance += (value - mean) * (value - mean);
  }
  return BootstrapInterval(low, high,
      standardError: sorted.length > 1 ? math.sqrt(variance / (sorted.length - 1)) : null);
}

/// Approximate Monte Carlo uncertainty of a percentile endpoint, expressed as
/// the width between neighbouring order-statistic indices. This is a diagnostic
/// for replicate count, not a confidence interval on the rating itself.
double _endpointMonteCarloRange(List<double> sorted, double q) {
  if (sorted.length < 8) return double.infinity;
  final n = sorted.length;
  final se = math.sqrt(math.max(1e-12, q * (1 - q) / (n + 2)));
  final lo = ((n + 1) * (q - 1.96 * se)).floor().clamp(0, n - 1);
  final hi = ((n + 1) * (q + 1.96 * se)).ceil().clamp(0, n - 1);
  return (sorted[hi] - sorted[lo]).abs();
}
