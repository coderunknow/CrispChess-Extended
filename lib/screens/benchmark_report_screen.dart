import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bench/benchmark_run.dart';
import '../bench/benchmark_service.dart';
import '../bench/benchmark_store.dart';
import '../bench/game_record.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/engine_lab/lab_widgets.dart';

/// The detailed report of one benchmark run.
///
/// Everything here comes from the stored run: no live engine, no recomputation
/// that could disagree with what was saved. Exports render from the same
/// object, so a PGN, the CSV and the tables cannot drift apart.
class BenchmarkReportScreen extends StatefulWidget {
  final String runId;

  const BenchmarkReportScreen({super.key, required this.runId});

  @override
  State<BenchmarkReportScreen> createState() => _BenchmarkReportScreenState();
}

class _BenchmarkReportScreenState extends State<BenchmarkReportScreen> {
  final BenchmarkService _service = BenchmarkService.shared;
  BenchmarkRun? _run;
  String? _error;
  bool _loading = true;
  bool _showAllGames = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final run = await _service.loadRun(widget.runId);
      if (!mounted) return;
      setState(() {
        _run = run;
        _loading = false;
        _error = run == null
            ? 'That run is no longer stored. It may have been deleted, or the '
                'document could not be read.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$what ✓')));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final run = _run;
    return Scaffold(
      appBar: AppBar(
        title: Text(l?.engineLabReport ?? 'Benchmark report'),
        actions: [
          if (run != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'json':
                    _copy(BenchmarkStore.encodeRunDocument(run), 'JSON');
                  case 'csv':
                    _copy('${run.enginesCsv()}\n\n${run.gamesCsv()}', 'CSV');
                  case 'pgn':
                    _copy(run.pgn(), 'PGN');
                  case 'report':
                    _copy(run.reportMarkdown(), 'Markdown');
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                    value: 'json', child: Text(l?.exportJson ?? 'Export JSON')),
                PopupMenuItem(
                    value: 'csv', child: Text(l?.exportCsv ?? 'Export CSV')),
                PopupMenuItem(
                    value: 'pgn', child: Text(l?.exportPgn ?? 'Export PGN')),
                PopupMenuItem(
                    value: 'report',
                    child: Text(l?.engineLabExportReport ?? 'Copy report')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: LabEmptyState(
                    icon: Icons.error_outline,
                    title: l?.engineLabReportMissing ?? 'Report unavailable',
                    message: _error!,
                  ),
                )
              : _body(run!, l),
    );
  }

  Widget _body(BenchmarkRun run, AppLocalizations? l) {
    final standings = run.standings();
    final ratings = run.ratings.ratings;
    final low = ratings.isEmpty
        ? 0.0
        : ratings.map((r) => r.ciLow).reduce((a, b) => a < b ? a : b);
    final high = ratings.isEmpty
        ? 0.0
        : ratings.map((r) => r.ciHigh).reduce((a, b) => a > b ? a : b);
    final games = [
      for (final game in run.games)
        if (!game.warmUp) game
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(
          title: l?.engineLabSummary ?? 'Summary',
          subtitle: run.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabInfoRow(
                  label: l?.engineLabStarted ?? 'Started',
                  value: _formatDate(run.startedAt)),
              LabInfoRow(
                  label: l?.engineLabDuration ?? 'Duration',
                  value: _formatDuration(run.duration)),
              LabInfoRow(
                  label: l?.engineLabTrigger ?? 'Trigger',
                  value: run.trigger ?? 'manual'),
              LabInfoRow(
                  label: l?.engineLabStopped ?? 'Stopped because',
                  value: run.stopReason),
              LabInfoRow(
                  label: l?.engineLabFormat ?? 'Format',
                  value: run.format.id),
              LabInfoRow(
                  label: l?.engineLabConfiguration ?? 'Configuration',
                  value: run.config.summary),
              LabInfoRow(
                  label: l?.engineLabGames ?? 'Games',
                  value: '${run.gamesPlayed} '
                      '(${run.gamesCompleted} ${l?.engineLabRatedGames ?? 'rated'}, '
                      '${run.forfeits} ${l?.engineLabForfeits ?? 'forfeits'}, '
                      '${run.aborted} ${l?.engineLabAborted ?? 'aborted'}, '
                      '${run.adjudicated} ${l?.engineLabAdjudicated ?? 'adjudicated'})'),
              LabInfoRow(
                  label: l?.engineLabEnvironment ?? 'Environment',
                  value: '${run.environment.platform} · ${run.environment.host}'),
              LabInfoRow(
                  label: l?.engineLabVersion ?? 'Version',
                  value: run.environment.appVersion),
            ],
          ),
        ),
        if (run.engineStatus.values.any((status) => status.isFailure))
          LabSection(
            title: l?.engineLabFailures ?? 'Engine problems',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in run.engineStatus.entries)
                  if (entry.value.isFailure)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '${run.identityFor(entry.key)?.label ?? entry.key}: '
                        '${entry.value.status}'
                        '${entry.value.reason == null ? '' : ' — ${entry.value.reason}'}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ),
              ],
            ),
          ),
        LabSection(
          title: l?.relativeElo ?? 'Relative Elo',
          subtitle: l?.engineLabRelativeScaleHint ??
              'Centred on ${run.ratings.anchor.toStringAsFixed(0)} across these '
                  'engines — a relative scale, not an absolute strength',
          child: Column(
            children: [
              for (final rating in ratings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: RatingBar(
                    rating: rating.rating,
                    ciLow: rating.ciLow,
                    ciHigh: rating.ciHigh,
                    minRating: low,
                    maxRating: high,
                    label: rating.label,
                    color: qualityColor(context, rating.quality),
                  ),
                ),
              if (ratings.isEmpty)
                Text(l?.engineLabNoRatings ?? 'No rated games yet.',
                    style: Theme.of(context).textTheme.bodySmall),
              for (final warning in run.ratings.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('· $warning',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabStandings ?? 'Standings',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              columns: [
                DataColumn(label: Text('#')),
                DataColumn(label: Text(l?.engineLabEngine ?? 'Engine')),
                DataColumn(label: Text(l?.relativeElo ?? 'Relative')),
                DataColumn(label: Text(l?.uncertainty ?? '±')),
                DataColumn(label: Text(l?.calibratedElo ?? 'Calibrated')),
                DataColumn(label: Text(l?.ratingQuality ?? 'Quality')),
                DataColumn(label: Text(l?.engineLabGames ?? 'Games')),
                DataColumn(label: Text(l?.engineLabScore ?? 'Score')),
              ],
              rows: [
                for (var index = 0; index < standings.length; index++)
                  DataRow(cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(standings[index].label)),
                    DataCell(Text(run.ratings
                            .ratingFor(standings[index].engineId)
                            ?.rating
                            .toStringAsFixed(0) ??
                        '—')),
                    DataCell(Text(run.ratings
                            .ratingFor(standings[index].engineId)
                            ?.stdErr
                            .toStringAsFixed(0) ??
                        '—')),
                    DataCell(Text(run.calibration
                            .ratingFor(standings[index].engineId)
                            ?.toStringAsFixed(0) ??
                        '—')),
                    DataCell(Text(run.ratings
                            .ratingFor(standings[index].engineId)
                            ?.quality
                            .id ??
                        '—')),
                    DataCell(Text('${standings[index].ratedGames}')),
                    DataCell(Text(
                        '${standings[index].wins}/${standings[index].draws}/'
                        '${standings[index].losses}')),
                  ]),
              ],
            ),
          ),
        ),
        LabSection(
          title: l?.calibratedElo ?? 'Calibrated Elo',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(run.calibration.reason,
                  style: Theme.of(context).textTheme.bodyMedium),
              for (final warning in run.calibration.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('· $warning',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
          ),
        ),
        LabSection(
          title: l?.performanceMetrics ?? 'Performance',
          subtitle: l?.engineLabPerformanceHint ??
              'Measured around every move; counters the engine does not report '
                  'stay unavailable',
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 14,
              columns: [
                DataColumn(label: Text(l?.engineLabEngine ?? 'Engine')),
                DataColumn(label: Text(l?.latencyP50 ?? 'p50')),
                DataColumn(label: Text(l?.latencyP95 ?? 'p95')),
                DataColumn(label: Text(l?.latencyP99 ?? 'p99')),
                DataColumn(label: Text(l?.engineLabMax ?? 'max')),
                DataColumn(label: Text(l?.nodesPerSecond ?? 'NPS')),
                DataColumn(label: Text(l?.engineLabDepth ?? 'Depth')),
                DataColumn(label: Text(l?.engineLabInitMs ?? 'Init')),
              ],
              rows: [
                for (final aggregate in standings)
                  DataRow(cells: [
                    DataCell(Text(aggregate.label)),
                    DataCell(Text('${aggregate.percentile(0.5)} ms')),
                    DataCell(Text('${aggregate.percentile(0.95)} ms')),
                    DataCell(Text('${aggregate.percentile(0.99)} ms')),
                    DataCell(Text('${aggregate.maxMillis} ms')),
                    DataCell(Text(aggregate.nps?.toString() ??
                        (l?.unavailableLabel ?? 'unavailable'))),
                    DataCell(Text(aggregate.maxDepth?.toString() ??
                        (l?.unavailableLabel ?? 'unavailable'))),
                    DataCell(Text('—')),
                  ]),
              ],
            ),
          ),
        ),
        LabSection(
          title: l?.engineLabEngines ?? 'Engines',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final identity in run.engines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(identity.label,
                          style: Theme.of(context).textTheme.bodyMedium),
                      Text(
                        '${identity.engineId} · ${identity.backend} · '
                        '${identity.platform} · ${identity.fingerprintKind} '
                        '${identity.shortFingerprint}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (identity.configuration.isNotEmpty)
                        Text(
                          identity.configuration.entries
                              .map((e) => '${e.key}=${e.value}')
                              .join(', '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabGamesList ?? 'Games',
          subtitle: '${games.length}',
          actions: [
            TextButton(
              onPressed: () =>
                  setState(() => _showAllGames = !_showAllGames),
              child: Text(_showAllGames
                  ? (l?.engineLabShowLess ?? 'Show fewer')
                  : (l?.engineLabShowAll ?? 'Show all')),
            ),
          ],
          child: Column(
            children: [
              for (final game in (_showAllGames ? games : games.take(20)))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${game.whiteLabel} vs ${game.blackLabel}'),
                  subtitle: Text(
                      '${game.openingName} · ${game.moves.length} plies · '
                      '${game.outcome.id}'
                      '${game.detail == null ? '' : ' — ${game.detail}'}'),
                  trailing: Text(game.outcome.pgnResult),
                  onTap: () => _showPgn(game),
                ),
              if (games.isEmpty)
                Text(l?.engineLabNoGames ?? 'No games recorded yet.',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (run.validationWarnings.isNotEmpty || run.warnings.isNotEmpty)
          LabSection(
            title: l?.engineLabConfiguration ?? 'Configuration notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final warning in [
                  ...run.validationWarnings,
                  ...run.warnings
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('· $warning',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        LabSection(
          title: l?.engineLabMethod ?? 'Method',
          child: Text(
            l?.engineLabMethodBody ??
                'Bradley–Terry maximum likelihood over every rated game, '
                    'centred on ${run.ratings.anchor.toStringAsFixed(0)}. The '
                    '95% interval is rating ± 1.96 × standard error, from the '
                    'Fisher information of the fit. Adjudicated, aborted, '
                    'cancelled and forfeited games are counted but not rated: a '
                    'game that did not finish is not a draw.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _copy(BenchmarkStore.encodeRunDocument(run), 'JSON'),
                icon: const Icon(Icons.data_object, size: 18),
                label: Text(l?.exportJson ?? 'Export JSON'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _copy('${run.enginesCsv()}\n\n${run.gamesCsv()}', 'CSV'),
                icon: const Icon(Icons.table_chart_outlined, size: 18),
                label: Text(l?.exportCsv ?? 'Export CSV'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _copy(run.pgn(), 'PGN'),
                icon: const Icon(Icons.article_outlined, size: 18),
                label: Text(l?.exportPgn ?? 'Export PGN'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  void _showPgn(BenchGame game) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${game.whiteLabel} vs ${game.blackLabel}'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              game.pgnDocument(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _copy(game.pgnDocument(), 'PGN'),
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';

  String _formatDuration(Duration duration) {
    if (duration.inMinutes < 1) return '${duration.inSeconds}s';
    if (duration.inHours < 1) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    }
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }
}
