/// Adaptive opponent selection and two-game experimental allocation.
///
/// The scheduler is deliberately not a general-purpose black-box optimizer.
/// It uses the Bradley–Terry Fisher geometry: for a candidate edge u and a
/// batch information weight w, the exact joint-covariance reduction of a
/// contrast c is w(cᵀCu)²/(1+w uᵀCu). Dividing the weighted, unmet-precision
/// reduction by measured cost gives a verifiable best-overall allocation rule.
/// A connected pilot and global opening-cluster bootstrap guard the geometry.
library;

import 'dart:math' as math;

import '../services/rating_fit.dart';
import 'benchmark_config.dart';
import 'benchmark_plan.dart';
import 'cluster_bootstrap.dart';
import 'elo.dart';
import 'engine_identity.dart';
import 'game_record.dart';
import 'opening_suite.dart';
import 'precision.dart';

class SchedulerCandidate {
  final EngineIdentity identity;
  final bool available;
  final String? unavailableReason;

  /// Catalog estimate or compatible historical measurement. Scheduling prior
  /// only — never inserted into the rating fit as evidence.
  final double? estimatedRating;
  final String estimateSource;
  final double estimateStdErr;
  final double expectedMoveMillis;
  final double startupMillis;
  final int memoryMb;
  final bool usesGpu;
  final double failureProbability;
  final bool supportsNodeLimit;
  final bool calibrationUseful;
  final String? historicalRunId;

  const SchedulerCandidate({
    required this.identity,
    this.available = true,
    this.unavailableReason,
    this.estimatedRating,
    this.estimateSource = 'catalog estimate (not evidence)',
    this.estimateStdErr = 200,
    this.expectedMoveMillis = 100,
    this.startupMillis = 1500,
    this.memoryMb = 256,
    this.usesGpu = false,
    this.failureProbability = 0,
    this.supportsNodeLimit = true,
    this.calibrationUseful = false,
    this.historicalRunId,
  });

  String get id => identity.engineId;
  String get label => identity.label;
  double get ratingPrior => estimatedRating ?? 1500;

  Map<String, dynamic> toJson() => {
    'engineId': id,
    'label': label,
    'available': available,
    if (unavailableReason != null) 'unavailableReason': unavailableReason,
    if (estimatedRating != null) 'estimatedRating': estimatedRating,
    'estimateSource': estimateSource,
    'estimateStdErr': estimateStdErr,
    'expectedMoveMillis': expectedMoveMillis,
    'startupMillis': startupMillis,
    'memoryMb': memoryMb,
    'usesGpu': usesGpu,
    'failureProbability': failureProbability,
    'supportsNodeLimit': supportsNodeLimit,
    'calibrationUseful': calibrationUseful,
    if (historicalRunId != null) 'historicalRunId': historicalRunId,
    'cohort': identity.cohortKey,
  };
}

class SchedulerState {
  final int gamesPlayed;
  final int engineMillis;
  final int bootstrapMillis;
  final Duration elapsed;
  final Map<String, int> failures;
  final Map<String, double> measuredMoveMillis;
  final Map<String, double> measuredStartupMillis;
  const SchedulerState({
    this.gamesPlayed = 0,
    this.engineMillis = 0,
    this.bootstrapMillis = 0,
    this.elapsed = Duration.zero,
    this.failures = const {},
    this.measuredMoveMillis = const {},
    this.measuredStartupMillis = const {},
  });
}

class SchedulerDecision {
  final bool stop;
  final String reason;
  final List<PlannedGame> games;
  final String? matchupReason;
  final double expectedCostMillis;
  final double utility;
  final bool needsBootstrap;
  const SchedulerDecision({
    required this.stop,
    required this.reason,
    this.games = const [],
    this.matchupReason,
    this.expectedCostMillis = 0,
    this.utility = 0,
    this.needsBootstrap = false,
  });
  Map<String, dynamic> toJson() => {
    'stop': stop, 'reason': reason,
    'games': [for (final g in games) g.index],
    if (matchupReason != null) 'matchupReason': matchupReason,
    'expectedCostMillis': expectedCostMillis,
    'utility': utility,
    'needsBootstrap': needsBootstrap,
  };
}

class PrecisionEvaluation {
  final bool achieved;
  final Map<String, double> individualHalfWidths;
  final Map<String, double> pairwiseHalfWidths;
  final List<String> unmet;
  final int? additionalGamesEstimate;
  final String explanation;
  const PrecisionEvaluation({
    required this.achieved,
    required this.individualHalfWidths,
    required this.pairwiseHalfWidths,
    required this.unmet,
    required this.explanation,
    this.additionalGamesEstimate,
  });
  Map<String, dynamic> toJson() => {
    'achieved': achieved,
    'individualHalfWidths': individualHalfWidths,
    'pairwiseHalfWidths': pairwiseHalfWidths,
    'unmet': unmet,
    if (additionalGamesEstimate != null) 'additionalGamesEstimate': additionalGamesEstimate,
    'explanation': explanation,
  };
}

PrecisionEvaluation evaluatePrecision({
  required EloFit fit,
  required PrecisionSettings precision,
  required List<String> participantIds,
  required List<String> targetIds,
  required int ratedGames,
}) {
  final report = fit.bootstrap;
  final individual = <String, double>{};
  final pairwise = <String, double>{};
  final unmet = <String>[];
  if (report == null || !report.reliable || !report.completed) {
    return PrecisionEvaluation(
      achieved: false, individualHalfWidths: individual,
      pairwiseHalfWidths: pairwise,
      unmet: ['A reliable completed opening-cluster bootstrap is required.'],
      explanation: report == null
          ? 'No cluster-bootstrap estimate is available.'
          : report.warnings.join(' '),
    );
  }
  final toleranceForMc = precision.wantsIndividual
      ? precision.individualToleranceElo
      : precision.pairwiseToleranceElo;
  if (!report.monteCarloAdequate(toleranceForMc)) {
    unmet.add('Bootstrap Monte Carlo endpoint uncertainty is too large; more replicates are needed.');
  }
  if (precision.wantsIndividual) {
    for (final id in participantIds) {
      final interval = report.individual[id];
      final half = interval?.halfWidth ?? double.infinity;
      individual[id] = half;
      if (!half.isFinite || half > precision.individualToleranceElo) {
        unmet.add('$id individual interval ${half.isFinite ? '±${half.toStringAsFixed(1)}' : 'unavailable'}');
      }
    }
  }
  if (precision.wantsPairwise) {
    final ids = participantIds.toList()..sort();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = ids[i], b = ids[j];
        if (precision.comparisonSet == PairwiseComparisonSet.targetPairs &&
            !(targetIds.contains(a) && targetIds.contains(b))) {
          continue;
        }
        final interval = report.pairwise[pairwiseKey(a, b)];
        final half = interval?.interval(precision.pairwiseScope).halfWidth ?? double.infinity;
        pairwise[pairwiseKey(a, b)] = half;
        if (!fit.inSameComponent(a, b) || !half.isFinite || half > precision.pairwiseToleranceElo) {
          unmet.add('$a vs $b ${precision.pairwiseScope.id} interval ${half.isFinite ? '±${half.toStringAsFixed(1)}' : 'unavailable/disconnected'}');
        }
      }
    }
  }
  int? estimate;
  if (unmet.isNotEmpty && ratedGames > 0) {
    var factor = 1.0;
    for (final half in [...individual.values, ...pairwise.values]) {
      final target = precision.wantsPairwise && pairwise.isNotEmpty
          ? precision.pairwiseToleranceElo
          : precision.individualToleranceElo;
      if (half.isFinite && half > target) {
        factor = math.max(factor, (half / target) * (half / target));
      } else if (!half.isFinite) {
        factor = double.infinity;
      }
    }
    if (factor.isFinite && factor > 1) {
      estimate = ((ratedGames * (factor - 1)) / 2).ceil() * 2;
    }
  }
  return PrecisionEvaluation(
    achieved: unmet.isEmpty,
    individualHalfWidths: individual, pairwiseHalfWidths: pairwise,
    unmet: unmet, additionalGamesEstimate: estimate,
    explanation: unmet.isEmpty
        ? 'All requested ${precision.summary} conditions are supported by the collected opening clusters.'
        : 'Objective not achieved: ${unmet.length} condition(s) remain uncertain.',
  );
}

class IntelligentScheduler {
  final List<String> targetIds;
  final List<SchedulerCandidate> candidates;
  final BenchmarkConfig config;
  final OpeningSuite suite;
  final Set<String> excludedIds;
  final BootstrapSettings bootstrapSettings;
  final Map<String, List<String>> _pairOpenings = {};
  final Map<String, int> _pairUnits = {};
  final Set<String> _usedClusters = {};
  bool _connectivitySeen = false;
  final List<Map<String, dynamic>> decisions = [];
  int _nextIndex = 1;
  int _nextPairing = 0;
  late final List<String> participantIds;
  late final List<String> selectedOpponents;
  late final Map<String, SchedulerCandidate> _byId;
  late final List<String> _warnings;

  IntelligentScheduler({
    required this.targetIds,
    required this.candidates,
    required this.config,
    required this.suite,
    this.excludedIds = const {},
    this.bootstrapSettings = const BootstrapSettings(),
  }) {
    if (targetIds.isEmpty) throw ArgumentError('Select at least one target engine.');
    _byId = {for (final c in candidates) c.id: c};
    for (final id in targetIds) {
      if (!_byId.containsKey(id)) throw ArgumentError('Target $id is not in the candidate pool.');
    }
    selectedOpponents = _selectOpponents();
    participantIds = [...targetIds, ...selectedOpponents];
    _warnings = [
      if (suite.length < bootstrapSettings.minClusters)
        'The opening suite has only ${suite.length} positions; at least '
            '${bootstrapSettings.minClusters} independent clusters are needed '
            'for the primary bootstrap precision claim.',
      if (participantIds.map((id) => _byId[id]!.identity.cohortKey).toSet().length > 1)
        'Participants span multiple execution cohorts. Comparisons are '
            'reported with cohort qualifications and cannot share a calibrated anchor.',
    ];
  }

  List<String> get warnings => List.unmodifiable(_warnings);
  List<SchedulerCandidate> get participants =>
      [for (final id in participantIds) _byId[id]!];

  bool _compatible(SchedulerCandidate c) {
    if (!c.available || excludedIds.contains(c.id)) return false;
    if (config.nodeLimit != null && !c.supportsNodeLimit) return false;
    final memory = config.resourceBudget.maxMemoryMb;
    if (memory != null && c.memoryMb > memory) return false;
    return true;
  }

  double _pairCost(String a, String b) {
    final ca = _byId[a]!, cb = _byId[b]!;
    final moveMs = math.max(ca.expectedMoveMillis, cb.expectedMoveMillis);
    final expectedPlies = math.min(config.plyCap, 90);
    final gameMs = expectedPlies * (moveMs + 8);
    final stability = 1 + 4 * math.max(ca.failureProbability, cb.failureProbability);
    final cohortPenalty = ca.identity.cohortKey == cb.identity.cohortKey ? 1.0 : 1.35;
    final gpuPenalty = (ca.usesGpu || cb.usesGpu) && config.resourceBudget.maxGpuMillis != null ? 1.15 : 1.0;
    return 2 * gameMs * stability * cohortPenalty * gpuPenalty;
  }

  double _information(String a, String b) {
    final p = expectedScore(_byId[a]!.ratingPrior, _byId[b]!.ratingPrior);
    // Two games, one colour-reversed opening unit.
    return 2 * p * (1 - p) / (ratingEloScale * ratingEloScale);
  }

  double _opponentUtility(SchedulerCandidate c) {
    if (!_compatible(c)) return -1;
    var best = 0.0;
    for (final target in targetIds) {
      final info = _information(target, c.id);
      final uncertaintyBonus = 1 + math.min(2, c.estimateStdErr / 200);
      final calibrationBonus = c.calibrationUseful ? 1.25 : 1.0;
      final stability = 1 - c.failureProbability.clamp(0.0, 0.95);
      best = math.max(best, info * uncertaintyBonus * calibrationBonus * stability / math.max(1, _pairCost(target, c.id)));
    }
    return best;
  }

  List<String> _selectOpponents() {
    final pool = [
      for (final c in candidates)
        if (!targetIds.contains(c.id) && _compatible(c)) c,
    ]..sort((a, b) {
      final byUtility = _opponentUtility(b).compareTo(_opponentUtility(a));
      return byUtility != 0 ? byUtility : a.id.compareTo(b.id);
    });
    if (pool.isEmpty) return const [];
    final selected = <String>[];
    final desiredReferences = math.max(2, 4 - targetIds.length);
    final bestUtility = _opponentUtility(pool.first);
    for (final candidate in pool) {
      final utility = _opponentUtility(candidate);
      if (utility <= 0) continue;
      final needed = selected.length < desiredReferences;
      final stillUseful = utility >= bestUtility * 0.2;
      if (!needed && !stillUseful) break;
      // Budget affordability is checked against a connected pilot, not by
      // downloading every catalog candidate.
      final trial = [...targetIds, ...selected, candidate.id];
      if (!_pilotAffordable(trial)) {
        if (needed) continue;
        break;
      }
      selected.add(candidate.id);
      if (!needed && selected.length >= desiredReferences && utility < bestUtility * 0.35) break;
    }
    return selected;
  }

  /// Distinct openings the suite can offer before a pairing's cycle repeats.
  /// One cycle is all the independence the pilot can buy from that edge.
  int get _openingsPerPairing => math.max(1, suite.openings.length);

  /// Opening units the pilot can give each tree edge without repeating an
  /// opening. The clamp is the point: `minClusters / edges` alone promises more
  /// independent openings than the suite contains, and a repeat is not a new
  /// cluster.
  int _pilotUnitsPerEdge(int edgeCount) => math.max(
      1,
      math.min(
        (bootstrapSettings.minClusters / math.max(1, edgeCount)).ceil(),
        _openingsPerPairing,
      ));

  double _pilotCost(List<String> ids) {
    if (ids.length < 2) return double.infinity;
    final edges = _spanningEdges(ids);
    final unitsPerEdge = _pilotUnitsPerEdge(edges.length);
    return edges.fold(0.0, (sum, e) => sum + unitsPerEdge * _pairCost(e.$1, e.$2)) +
        ids.fold(0.0, (sum, id) => sum + _byId[id]!.startupMillis);
  }

  bool _pilotAffordable(List<String> ids) {
    final cost = _pilotCost(ids);
    final maxGames = config.maxGames;
    final edges = math.max(1, ids.length - 1);
    final unitsPerEdge = _pilotUnitsPerEdge(edges);
    final games = 2 * edges * unitsPerEdge;
    if (maxGames != null && games + config.warmUpGames > maxGames) return false;
    final maxDuration = config.maxDuration;
    if (maxDuration != null && cost > maxDuration.inMilliseconds * 0.8) return false;
    final maxEngine = config.resourceBudget.maxEngineMillis;
    if (maxEngine != null && cost > maxEngine * 0.8) return false;
    return cost.isFinite;
  }

  /// Maximum-information/cost spanning tree, deterministic from a target root.
  List<(String, String)> _spanningEdges(List<String> ids) {
    if (ids.length < 2) return const [];
    final connected = <String>{ids.first};
    final edges = <(String, String)>[];
    while (connected.length < ids.length) {
      (String, String)? best;
      var bestWeight = -1.0;
      for (final a in connected) {
        for (final b in ids) {
          if (connected.contains(b)) continue;
          final weight = _information(a, b) / math.max(1, _pairCost(a, b));
          if (weight > bestWeight || (weight == bestWeight && (best == null || '$a|$b'.compareTo('${best.$1}|${best.$2}') < 0))) {
            bestWeight = weight;
            best = (a, b);
          }
        }
      }
      if (best == null) break;
      edges.add(best);
      connected.add(best.$2);
    }
    return edges;
  }

  /// Whether at least one colour-reversed opening pair fits the recorded-game
  /// cap. A cap of one game cannot hold a pair, and no schedule can.
  bool get hasRoomForAnOpeningUnit {
    final cap = effectiveRecordedGameCap(config);
    return cap == null || cap >= 2;
  }

  BenchmarkPlan buildPilotPlan() {
    if (participantIds.length < 2) {
      throw StateError('The scheduler needs at least one compatible opponent '
          'to build a connected pilot.');
    }
    final recordedCap = effectiveRecordedGameCap(config);
    if (recordedCap != null && recordedCap < 2) {
      throw ArgumentError(
          'A budget of ${config.maxGames} game(s) cannot hold one '
          'colour-reversed opening pair; the pilot needs at least 2. Nothing '
          'was scheduled.');
    }
    final identities = [for (final id in participantIds) _byId[id]!.identity];
    final edges = _spanningEdges(participantIds);
    final unitsPerEdge = _pilotUnitsPerEdge(edges.length);
    final games = <PlannedGame>[];
    final maxRecorded = effectiveRecordedGameCap(config) ?? 1 << 30;
    var pairingIndex = 0;
    for (final edge in edges) {
      final key = pairwiseKey(edge.$1, edge.$2);
      final order = suite.openingOrder(seed: config.seed, pairingIndex: pairingIndex);
      _pairOpenings[key] = [for (final i in order) suite.openings[i].id];
      for (var unit = 0; unit < unitsPerEdge && games.length + 1 < maxRecorded; unit++) {
        final openingId = _pairOpenings[key]!.removeAt(0);
        final opening = suite.openingById(openingId)!;
        final cluster = suite.clusterIdFor(opening);
        _usedClusters.add(cluster);
        _pairUnits[key] = (_pairUnits[key] ?? 0) + 1;
        final pairId = 'pilot/$pairingIndex/$unit';
        games.add(PlannedGame(index: games.length + 1, whiteId: edge.$1, blackId: edge.$2,
            pairingIndex: pairingIndex, gameInPairing: 0, openingId: openingId, clusterId: cluster, pairId: pairId));
        games.add(PlannedGame(index: games.length + 1, whiteId: edge.$2, blackId: edge.$1,
            pairingIndex: pairingIndex, gameInPairing: 1, openingId: openingId, clusterId: cluster, pairId: pairId));
      }
      pairingIndex++;
    }
    _nextIndex = games.length + 1;
    _nextPairing = pairingIndex;
    final plannedClusters = _usedClusters.length;
    decisions.add({
      'phase': 'pilot',
      'reason': 'Connected maximum-information/cost pilot; up to '
          '$unitsPerEdge opening unit(s) per tree edge to approach '
          '${bootstrapSettings.minClusters} independent clusters; '
          '$plannedClusters planned before any cluster repeated'
          '${plannedClusters < bootstrapSettings.minClusters ? ' (below the minimum, so a precision claim will need the adaptive phase)' : ''}.',
      'participants': participantIds,
      'opponents': selectedOpponents,
      'games': games.length,
      'clusters': plannedClusters,
      'unitsPerEdge': unitsPerEdge,
    });
    return BenchmarkPlan(
      config: config, format: TournamentFormat.intelligent,
      engines: identities, suite: suite, games: games,
      targetEngineIds: targetIds,
      warnings: _warnings,
      schedulerMetadata: {
        'algorithm': 'connected pilot + weighted Fisher variance reduction per measured cost',
        'targets': targetIds,
        'opponents': selectedOpponents,
        'participants': participantIds,
        // The full pool is assessable; only [participants] enter the model.
        // Unselected candidates are recorded separately so a report can show
        // what was considered and rejected without implying it played.
        'candidatePool': [for (final c in candidates) c.toJson()],
        'unselected': [
          for (final c in candidates)
            if (!participantIds.contains(c.id)) c.id,
        ],
        'excluded': excludedIds.toList(),
        'bootstrap': bootstrapSettings.toJson(),
        'decisions': decisions,
      },
    );
  }

  List<Map<String, dynamic>> get decisionLog => List.unmodifiable(decisions);

  /// Chooses the next two-game opening unit, or a truthful stop. [fit] is the
  /// current joint Fisher fit; [bootstrap] is the latest primary uncertainty.
  SchedulerDecision decideNext({
    required List<BenchGame> games,
    required EloFit fit,
    required ClusterBootstrapReport? bootstrap,
    required SchedulerState state,
    required int finalBootstrapReserveMillis,
  }) {
    final precision = config.precision;
    // The precision claim is made on the *primary* uncertainty estimate: the
    // latest cluster bootstrap when the caller has one, the fit's own stored
    // report otherwise. A Fisher-only fit can never declare the objective met.
    final evaluated = bootstrap == null ? fit : fit.withBootstrap(bootstrap);
    final evaluation = evaluatePrecision(
      fit: evaluated,
      precision: precision,
      participantIds: participantIds,
      targetIds: targetIds,
      ratedGames: fit.ratedGames,
    );
    if (evaluation.achieved) {
      return _stop('precision objective achieved', evaluation.explanation);
    }
    final maxGames = config.maxGames;
    if (maxGames != null && state.gamesPlayed + 2 + config.warmUpGames > maxGames) {
      return _stop('game budget exhausted', 'The next paired opening would exceed the user game cap.');
    }
    final maxDuration = config.maxDuration;
    if (maxDuration != null && state.elapsed.inMilliseconds + finalBootstrapReserveMillis >= maxDuration.inMilliseconds) {
      return _stop('time budget reserved for final analysis', 'Remaining wall-clock time is reserved for the final bootstrap and report.');
    }
    final maxEngine = config.resourceBudget.maxEngineMillis;
    if (maxEngine != null && state.engineMillis >= maxEngine) {
      return _stop('engine compute budget exhausted', 'Measured engine compute reached the user budget.');
    }
    final maxBootstrap = config.resourceBudget.maxBootstrapMillis;
    if (maxBootstrap != null && state.bootstrapMillis + finalBootstrapReserveMillis > maxBootstrap) {
      return _stop('bootstrap compute budget exhausted', 'Remaining compute is needed for the final uncertainty estimate.');
    }
    final model = fitRatingModel(
      [for (final g in games) if (!g.warmUp && g.outcome.isRatingEligible && g.whiteId != g.blackId)
        (white: g.whiteId, black: g.blackId, score: g.outcome.whiteScore!)],
      participants: participantIds,
    );
    final contrasts = _contrasts(model);
    _connectivitySeen = false;
    var bestUtility = 0.0;
    String? bestA, bestB, bestOpening, bestCluster, bestReason;
    var bestCost = 0.0;
    for (var i = 0; i < participantIds.length; i++) {
      for (var j = i + 1; j < participantIds.length; j++) {
        final a = participantIds[i], b = participantIds[j];
        if (!_availableParticipant(a) || !_availableParticipant(b)) continue;
        final key = pairwiseKey(a, b);
        final remaining = _remainingOpenings(key, i * participantIds.length + j);
        if (remaining.isEmpty) continue;
        final cost = _measuredPairCost(a, b, state);
        if (maxDuration != null && state.elapsed.inMilliseconds + cost + finalBootstrapReserveMillis > maxDuration.inMilliseconds) continue;
        if (maxEngine != null && state.engineMillis + cost > maxEngine) continue;
        final p = expectedScore(_rating(fit, a), _rating(fit, b));
        final w = 2 * p * (1 - p) / (ratingEloScale * ratingEloScale);
        final ia = model.players.indexOf(a), ib = model.players.indexOf(b);
        final u = List<double>.filled(model.players.length, 0);
        u[ia] = 1; u[ib] = -1;
        var uu = 0.0;
        for (var x = 0; x < u.length; x++) {
          for (var y = 0; y < u.length; y++) {
            uu += u[x] * model.covariance[x][y] * u[y];
          }
        }
        var gain = 0.0;
        for (final contrast in contrasts) {
          var cv = 0.0;
          for (var x = 0; x < u.length; x++) {
            cv += (contrast.coefficients[model.players[x]] ?? 0) * (model.covariance[ia][x] - model.covariance[ib][x]);
          }
          final current = model.contrastVariance(contrast.coefficients);
          final target = contrast.targetVariance;
          if (!current.isFinite) {
            // A cross-component contrast has no finite variance to reduce:
            // only connectivity creates it. That is a scheduling opportunity,
            // scored separately from variance gain so it cannot masquerade as
            // a precision improvement.
            if (model.componentOf[a] != model.componentOf[b] && !_connectivitySeen) {
              _connectivitySeen = true;
              gain += 1.0 / math.max(1, cost);
            }
            continue;
          }
          if (current <= target) continue;
          final reduction = w * cv * cv / math.max(1e-12, 1 + w * uu);
          final gap = (current - target) / math.max(current, target);
          gain += contrast.weight * gap * reduction / math.max(1, target);
        }
        // Prefer a globally new opening while independent clusters are scarce.
        final openingId = remaining.firstWhere((id) => !_usedClusters.contains(suite.clusterIdFor(suite.openingById(id)!)), orElse: () => remaining.first);
        final opening = suite.openingById(openingId)!;
        final cluster = suite.clusterIdFor(opening);
        final coverageBonus = _usedClusters.length < bootstrapSettings.minClusters && !_usedClusters.contains(cluster) ? 1.5 : 1.0;
        final stability = 1 - math.max(_byId[a]!.failureProbability, _byId[b]!.failureProbability).clamp(0.0, 0.95);
        final utility = gain * coverageBonus * stability / math.max(1, cost);
        if (utility > bestUtility) {
          bestUtility = utility;
          bestA = a; bestB = b; bestOpening = openingId; bestCluster = cluster; bestCost = cost;
          bestReason = 'Expected weighted joint-variance reduction per measured '
              'millisecond is ${utility.toStringAsExponential(3)}; '
              'p=${p.toStringAsFixed(3)}, batch cost≈${cost.round()} ms.';
        }
      }
    }
    if (bestA == null || bestB == null || bestUtility <= 0) {
      final needsMoreClusters = _usedClusters.length < bootstrapSettings.minClusters;
      return _stop(needsMoreClusters ? 'insufficient independent openings' : 'no affordable informative matchup',
          needsMoreClusters
              ? 'No remaining matchup can add the independent opening clusters required for a reliable bootstrap.'
              : 'Every affordable matchup has exhausted its opening cycle or offers no remaining precision gain.');
    }
    // Promotion from the guard above: these are non-null from here on.
    final engineA = bestA, engineB = bestB, cluster = bestCluster!;
    final key = pairwiseKey(engineA, engineB);
    _pairOpenings[key]!.remove(bestOpening);
    _usedClusters.add(cluster);
    final unit = _pairUnits[key] ?? 0;
    _pairUnits[key] = unit + 1;
    final pairingIndex = _nextPairing++;
    final pairId = 'adaptive/$pairingIndex/$unit';
    final batch = [
      PlannedGame(index: _nextIndex++, whiteId: engineA, blackId: engineB, pairingIndex: pairingIndex,
          gameInPairing: 0, openingId: bestOpening, clusterId: cluster, pairId: pairId),
      PlannedGame(index: _nextIndex++, whiteId: engineB, blackId: engineA, pairingIndex: pairingIndex,
          gameInPairing: 1, openingId: bestOpening, clusterId: cluster, pairId: pairId),
    ];
    decisions.add({'phase': 'adaptive', 'a': engineA, 'b': engineB, 'reason': bestReason, 'utility': bestUtility, 'expectedCostMillis': bestCost});
    return SchedulerDecision(stop: false, reason: 'next most informative affordable opening unit',
        games: batch, matchupReason: bestReason, expectedCostMillis: bestCost, utility: bestUtility);
  }

  bool _availableParticipant(String id) {
    final c = _byId[id]!;
    return c.available && !excludedIds.contains(id);
  }

  double _rating(EloFit fit, String id) => fit.ratingFor(id)?.rating ?? _byId[id]!.ratingPrior;

  double _measuredPairCost(String a, String b, SchedulerState state) {
    final estimated = _pairCost(a, b);
    final ma = state.measuredMoveMillis[a], mb = state.measuredMoveMillis[b];
    if (ma == null && mb == null) return estimated;
    final moveMs = math.max(ma ?? _byId[a]!.expectedMoveMillis, mb ?? _byId[b]!.expectedMoveMillis);
    return 2 * math.min(config.plyCap, 90) * (moveMs + 8);
  }

  List<String> _remainingOpenings(String key, int pairingSeed) {
    return _pairOpenings.putIfAbsent(key, () {
      final order = suite.openingOrder(seed: config.seed, pairingIndex: pairingSeed);
      return [for (final i in order) suite.openings[i].id];
    });
  }

  List<_Contrast> _contrasts(RatingModelFit model) {
    final result = <_Contrast>[];
    final precision = config.precision;
    final z = _zForConfidence(precision.confidenceLevel);
    if (precision.wantsIndividual) {
      for (final id in participantIds) {
        final component = model.components[model.componentOf[id] ?? 0];
        final coefficients = {for (final p in component) p: (p == id ? 1.0 : 0.0) - 1 / component.length};
        result.add(_Contrast(coefficients,
            math.pow(precision.individualToleranceElo / z, 2).toDouble(),
            targetIds.contains(id) ? 2.0 : 1.0));
      }
    }
    if (precision.wantsPairwise) {
      for (var i = 0; i < participantIds.length; i++) {
        for (var j = i + 1; j < participantIds.length; j++) {
          final a = participantIds[i], b = participantIds[j];
          if (precision.comparisonSet == PairwiseComparisonSet.targetPairs &&
              !(targetIds.contains(a) && targetIds.contains(b))) {
            continue;
          }
          final weight = targetIds.contains(a) && targetIds.contains(b) ? 3.0
              : targetIds.contains(a) || targetIds.contains(b) ? 1.5 : 1.0;
          result.add(_Contrast({a: 1.0, b: -1.0},
              math.pow(precision.pairwiseToleranceElo / z, 2).toDouble(), weight));
        }
      }
    }
    return result;
  }

  SchedulerDecision _stop(String reason, String explanation) {
    decisions.add({'phase': 'stop', 'reason': reason, 'explanation': explanation});
    return SchedulerDecision(stop: true, reason: reason, matchupReason: explanation);
  }
}

/// One precision requirement expressed as a linear contrast of the ratings.
class _Contrast {
  final Map<String, double> coefficients;

  /// Variance the contrast must reach: (tolerance / z)² in Elo².
  final double targetVariance;

  /// Priority, not a statistical quantity: target-to-target comparisons are by
  /// definition more interesting than filler ones.
  final double weight;

  const _Contrast(this.coefficients, this.targetVariance, this.weight);
}

/// Acklam's inverse-normal approximation; adequate for interval planning.
double _zForConfidence(double confidence) {
  final p = (1 + confidence) / 2;
  if (p <= 0 || p >= 1) return 1.96;
  const a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00];
  const b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01];
  const c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00];
  const d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00];
  const plow = 0.02425;
  double q, r;
  if (p < plow) {
    q = math.sqrt(-2 * math.log(p));
    return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1);
  }
  if (p > 1 - plow) {
    q = math.sqrt(-2 * math.log(1 - p));
    return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) / ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1);
  }
  q = p - 0.5; r = q * q;
  return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q / (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1);
}
