/// Setup and live state for an intelligent benchmark.
///
/// The user chooses targets, conditions, a precision objective and a budget.
/// Everything else — which opponents, which openings, how many games — is the
/// scheduler's decision, and this panel shows that decision and its reasons
/// instead of asking the user to assemble a bracket.
library;

import 'package:flutter/material.dart';

import '../bench/benchmark_config.dart';
import '../bench/benchmark_plan.dart';
import '../bench/cluster_bootstrap.dart';
import '../bench/elo.dart';
import '../bench/intelligent_scheduler.dart';
import '../bench/precision.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/engine_lab/lab_widgets.dart';

class PrecisionObjectiveSelector extends StatelessWidget {
  final PrecisionSettings settings;
  final bool enabled;
  final ValueChanged<PrecisionSettings> onChanged;
  const PrecisionObjectiveSelector({
    super.key,
    required this.settings,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<PrecisionObjective>(
          segments: [
            ButtonSegment(
              value: PrecisionObjective.individual,
              label: Text(l?.precisionIndividual ?? 'Individual'),
            ),
            ButtonSegment(
              value: PrecisionObjective.pairwise,
              label: Text(l?.precisionPairwise ?? 'Pairwise'),
            ),
            ButtonSegment(
              value: PrecisionObjective.both,
              label: Text(l?.precisionBoth ?? 'Both'),
            ),
          ],
          selected: {settings.objective},
          onSelectionChanged: enabled
              ? (selection) => onChanged(settings.copyWith(objective: selection.first))
              : null,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: LabNumberField(
                key: ValueKey('confidence-${(settings.confidenceLevel * 100).round()}'),
                label: l?.precisionConfidence ?? 'Confidence %',
                value: (settings.confidenceLevel * 100).round(),
                enabled: enabled,
                onChanged: (value) => onChanged(settings.copyWith(
                    // PrecisionSettings.validationErrors accepts up to 99.9%, so the
                    // field must not be able to produce 100% or more: a
                    // clamped value that still fails validation turns a typing
                    // slip into an unstartable run.
                    confidenceLevel: (value ?? 95).clamp(50, 99.9) / 100)),
              ),
            ),
            const SizedBox(width: 12),
            if (settings.wantsIndividual)
              Expanded(
                child: LabNumberField(
                  key: ValueKey('individual-${settings.individualToleranceElo.round()}'),
                  label: l?.precisionIndividualElo ?? 'Individual ±Elo',
                  value: settings.individualToleranceElo.round(),
                  enabled: enabled,
                  onChanged: (value) => onChanged(settings.copyWith(
                      individualToleranceElo: (value ?? 20).clamp(1, 1000).toDouble())),
                ),
              ),
            if (settings.wantsPairwise) ...[
              if (settings.wantsIndividual) const SizedBox(width: 12),
              Expanded(
                child: LabNumberField(
                  key: ValueKey('pairwise-${settings.pairwiseToleranceElo.round()}'),
                  label: l?.precisionPairwiseElo ?? 'Pairwise ±Elo',
                  value: settings.pairwiseToleranceElo.round(),
                  enabled: enabled,
                  onChanged: (value) => onChanged(settings.copyWith(
                      pairwiseToleranceElo: (value ?? 20).clamp(1, 1000).toDouble())),
                ),
              ),
            ],
          ],
        ),
        if (settings.wantsPairwise) ...[
          const SizedBox(height: 8),
          SegmentedButton<PairwiseIntervalScope>(
            segments: [
              ButtonSegment(
                value: PairwiseIntervalScope.pointwise,
                label: Text(l?.precisionPointwise ?? 'Pointwise'),
              ),
              ButtonSegment(
                value: PairwiseIntervalScope.simultaneous,
                label: Text(l?.precisionSimultaneous ?? 'Simultaneous'),
              ),
            ],
            selected: {settings.pairwiseScope},
            onSelectionChanged: enabled
                ? (selection) => onChanged(settings.copyWith(pairwiseScope: selection.first))
                : null,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              settings.pairwiseScope == PairwiseIntervalScope.simultaneous
                  ? (l?.precisionSimultaneousHint ??
                      'Simultaneous intervals cover every requested comparison '
                          'at once (maximum-statistic bootstrap); they are wider '
                          'than pointwise intervals.')
                  : (l?.precisionPointwiseHint ??
                      'Pointwise intervals apply to one comparison at a time and '
                          'do not claim joint coverage.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SegmentedButton<PairwiseComparisonSet>(
            segments: [
              ButtonSegment(
                value: PairwiseComparisonSet.allParticipants,
                label: Text(l?.precisionAllPairs ?? 'All participants'),
              ),
              ButtonSegment(
                value: PairwiseComparisonSet.targetPairs,
                label: Text(l?.precisionTargetPairs ?? 'Targets only'),
              ),
            ],
            selected: {settings.comparisonSet},
            onSelectionChanged: enabled
                ? (selection) => onChanged(settings.copyWith(comparisonSet: selection.first))
                : null,
          ),
        ],
        const SizedBox(height: 6),
        Text(settings.summary, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class ResourceBudgetFields extends StatelessWidget {
  final BenchmarkConfig config;
  final bool enabled;
  final ValueChanged<BenchmarkConfig> onChanged;
  const ResourceBudgetFields({
    super.key,
    required this.config,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l?.budgetHint ??
              'At least one budget must be set. The scheduler never invents a '
                  'global time limit; it stops at your boundaries and reports '
                  'the objective as unmet when they run out.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: LabNumberField(
              key: ValueKey('maxGames-${config.maxGames}'),
              label: l?.engineLabMaxGames ?? 'Max games',
              value: config.maxGames ?? 0,
              helper: l?.engineLabZeroIsUnlimited ?? '0 = no limit',
              enabled: enabled,
              onChanged: (value) => onChanged(config.copyWith(
                  maxGames: () => (value ?? 0) <= 0 ? null : value)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabNumberField(
              key: ValueKey('maxMinutes-${config.maxDuration?.inMinutes}'),
              label: l?.engineLabMaxMinutes ?? 'Max minutes',
              value: config.maxDuration?.inMinutes ?? 0,
              enabled: enabled,
              onChanged: (value) => onChanged(config.copyWith(
                  maxDuration: () => (value ?? 0) <= 0
                      ? null
                      : Duration(minutes: value!))),
            ),
          ),
        ]),
        Row(children: [
          Expanded(
            child: LabNumberField(
              key: ValueKey('engineMinutes-${config.resourceBudget.maxEngineMillis}'),
              label: l?.budgetEngineMinutes ?? 'Engine compute (min)',
              value: (config.resourceBudget.maxEngineMillis ?? 0) ~/ 60000,
              enabled: enabled,
              onChanged: (value) => onChanged(config.copyWith(
                  resourceBudget: config.resourceBudget.copyWith(
                      maxEngineMillis: () => (value ?? 0) <= 0
                          ? null
                          : value! * 60000))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LabNumberField(
              key: ValueKey('memory-${config.resourceBudget.maxMemoryMb}'),
              label: l?.budgetMemory ?? 'Memory limit (MB)',
              value: config.resourceBudget.maxMemoryMb ?? 0,
              enabled: enabled,
              onChanged: (value) => onChanged(config.copyWith(
                  resourceBudget: config.resourceBudget.copyWith(
                      maxMemoryMb: () => (value ?? 0) <= 0 ? null : value))),
            ),
          ),
        ]),
      ],
    );
  }
}

/// Preview of the exact schedule the scheduler proposes, before anything runs.
class SchedulerPreviewCard extends StatelessWidget {
  final BenchmarkPlan plan;
  final List<String> warnings;
  const SchedulerPreviewCard({super.key, required this.plan, this.warnings = const []});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final targets = plan.targetEngineIds.toSet();
    final participants = plan.engines;
    final opponents = participants.where((e) => !targets.contains(e.engineId)).toList();
    final pairs = <String>{};
    for (final game in plan.recordedGames) {
      final ids = [game.whiteId, game.blackId]..sort();
      pairs.add(ids.join(' vs '));
    }
    final decisions = plan.schedulerMetadata['decisions'];
    final pilotReason = decisions is List && decisions.isNotEmpty && decisions.first is Map
        ? (decisions.first as Map)['reason'] as String?
        : null;
    return LabSection(
      title: l?.schedulerPreview ?? 'Scheduler proposal',
      subtitle: l?.schedulerPreviewHint ??
          'Review the plan before it runs. Adaptive batches are chosen from '
              'measured uncertainty, so the final game count may be larger.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabInfoRow(
            label: l?.schedulerTargets ?? 'Targets',
            value: participants
                .where((e) => targets.contains(e.engineId))
                .map((e) => e.label)
                .join(', '),
          ),
          LabInfoRow(
            label: l?.schedulerOpponents ?? 'Selected opponents',
            value: opponents.isEmpty ? '—' : opponents.map((e) => e.label).join(', '),
          ),
          LabInfoRow(
            label: l?.schedulerParticipants ?? 'Participants in the joint model',
            value: '${participants.length}',
          ),
          LabInfoRow(
            label: l?.schedulerPilotGames ?? 'Pilot games',
            value: '${plan.recordedGames.length}',
          ),
          LabInfoRow(
            label: l?.schedulerPilotPairs ?? 'Initial matchups',
            value: pairs.length.toString(),
          ),
          if (pilotReason != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${l?.schedulerWhy ?? 'Why'}: $pilotReason',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final warning in [...plan.warnings, ...warnings])
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(warning, style: Theme.of(context).textTheme.bodySmall)),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Live precision vs budget for an intelligent run.
class LiveUncertaintyCard extends StatelessWidget {
  final EloFit fit;
  final PrecisionEvaluation precision;
  final String schedulerReason;
  final int gamesPlayed;
  final int? maxGames;
  final Duration elapsed;
  final Duration? maxDuration;
  const LiveUncertaintyCard({
    super.key,
    required this.fit,
    required this.precision,
    required this.schedulerReason,
    required this.gamesPlayed,
    required this.maxGames,
    required this.elapsed,
    required this.maxDuration,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bootstrap = fit.bootstrap;
    return LabSection(
      title: l?.livePrecision ?? 'Live precision',
      subtitle: precision.achieved
          ? (l?.precisionAchieved ?? 'Objective achieved by the collected evidence.')
          : (l?.precisionNotAchieved ?? 'Objective not achieved yet.'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LabInfoRow(label: l?.engineLabGames ?? 'Games', value: maxGames == null
            ? '$gamesPlayed'
            : '$gamesPlayed / $maxGames'),
        LabInfoRow(
          label: l?.liveElapsed ?? 'Elapsed',
          value: maxDuration == null
              ? _duration(elapsed)
              : '${_duration(elapsed)} / ${_duration(maxDuration!)}',
        ),
        if (bootstrap != null) ...[
          LabInfoRow(
            label: l?.liveClusters ?? 'Independent opening clusters',
            value: '${bootstrap.clusters}',
          ),
          LabInfoRow(
            label: l?.liveBootstrap ?? 'Bootstrap replicates',
            value: '${bootstrap.validReplicates} valid / '
                '${bootstrap.attemptedReplicates} attempted'
                '${bootstrap.reliable ? '' : ' (unreliable)'}',
          ),
          if (bootstrap.maxIndividualHalfWidth().isFinite)
            LabInfoRow(
              label: l?.liveWorstIndividual ?? 'Worst individual interval',
              value: '±${bootstrap.maxIndividualHalfWidth().toStringAsFixed(1)} Elo '
                  '(${(bootstrap.confidenceLevel * 100).toStringAsFixed(0)}%)',
            ),
          if (bootstrap.pairwise.isNotEmpty)
            LabInfoRow(
              label: l?.liveWorstPairwise ?? 'Worst pairwise interval',
              value: '±${bootstrap.maxPairwiseHalfWidth(fit.pairwiseScope).toStringAsFixed(1)} Elo '
                  '(${fit.pairwiseScope.id})',
            ),
        ],
        for (final unmet in precision.unmet.take(6))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('· $unmet', style: Theme.of(context).textTheme.bodySmall),
          ),
        if (precision.unmet.length > 6)
          Text('+${precision.unmet.length - 6} more',
              style: Theme.of(context).textTheme.bodySmall),
        if (precision.additionalGamesEstimate != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${l?.precisionAdditionalGames ?? 'Defensible additional estimate'}: '
              '~${precision.additionalGamesEstimate} games under the current design.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const Divider(height: 20),
        Text('${l?.schedulerNext ?? 'Scheduler'}: $schedulerReason',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  static String _duration(Duration d) {
    final h = d.inHours, m = d.inMinutes.remainder(60), s = d.inSeconds.remainder(60);
    return h > 0 ? '${h}h ${m}m' : m > 0 ? '${m}m ${s}s' : '${s}s';
  }
}

/// Explanation of the statistical method, in plain language, with the exact
/// diagnostics one level below.
class MethodologyCard extends StatelessWidget {
  final ClusterBootstrapReport? bootstrap;
  final PrecisionEvaluation? precision;
  const MethodologyCard({super.key, this.bootstrap, this.precision});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final report = bootstrap;
    return LabSection(
      title: l?.ratingMethodology ?? 'Rating methodology',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          l?.ratingMethodologyPlain ??
              'Games are paired: the same opening is played with both colours. '
                  'The uncertainty comes from resampling entire openings, not '
                  'single games, because games from one opening are related. '
                  'Intervals therefore reflect how much independent evidence the '
                  'run actually collected.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (report == null)
          Text(l?.bootstrapMissing ?? 'No opening-cluster bootstrap is stored for this run.',
              style: Theme.of(context).textTheme.bodySmall)
        else ...[
          LabInfoRow(label: l?.liveClusters ?? 'Clusters', value: '${report.clusters}'),
          LabInfoRow(
            label: l?.liveBootstrap ?? 'Replicates',
            value: '${report.validReplicates}/${report.attemptedReplicates} valid · '
                '${report.failedReplicates} failed',
          ),
          LabInfoRow(label: l?.methodologySeed ?? 'Seed', value: '${report.seed}'),
          LabInfoRow(
            label: l?.methodologyCompute ?? 'Bootstrap compute',
            value: '${report.computeMillis} ms',
          ),
          if (report.failureReasons.isNotEmpty)
            LabInfoRow(
              label: l?.methodologyFailures ?? 'Failure reasons',
              value: report.failureReasons.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join(', '),
            ),
          if (report.maxEndpointMonteCarloRange.isFinite)
            LabInfoRow(
              label: l?.methodologyMonteCarlo ?? 'Monte Carlo endpoint range',
              value: '±${report.maxEndpointMonteCarloRange.toStringAsFixed(2)} Elo',
            ),
          for (final warning in report.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('· $warning', style: Theme.of(context).textTheme.bodySmall),
            ),
        ],
        if (precision != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(precision!.explanation,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ]),
    );
  }
}
