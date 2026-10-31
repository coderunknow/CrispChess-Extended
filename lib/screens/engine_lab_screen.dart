/// The Engine Lab: run a benchmark, read the result, keep the history.
///
/// The screen is deliberately thin. Everything that decides what a run means
/// lives in `lib/bench/` — the plan, the runner, the rating fit, the store —
/// and this file only asks for choices and renders what came back. The one
/// rule it enforces by itself is that a rating is never shown without the
/// interval and the number of games behind it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bench/benchmark_config.dart';
import '../bench/benchmark_environment.dart';
import '../bench/benchmark_fingerprint.dart' show hostSummary;
import '../bench/benchmark_run.dart';
import '../bench/benchmark_plan.dart';
import '../bench/benchmark_runner.dart';
import '../bench/benchmark_service.dart';
import '../bench/benchmark_settings.dart';
import '../bench/benchmark_store.dart';
import '../bench/calibration.dart';
import '../bench/elo.dart';
import '../bench/engine_identity.dart';
import '../bench/game_record.dart';
import '../bench/opening_suite.dart';
import '../bench/stability_probe.dart';
import '../engines/engine_registry.dart';
// EngineProfile comes from the platform-independent stub, the same type the
// profile store persists: importing the io engine would drag dart:io into the
// web build.
import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../l10n/generated/app_localizations.dart';
import '../services/engine_profile_store.dart';
import '../widgets/engine_lab/lab_widgets.dart';
import 'benchmark_report_screen.dart';

class EngineLabScreen extends StatefulWidget {
  /// Tab to open on: 0 overview, 1 benchmark, 2 ratings, 3 history,
  /// 4 diagnostics. Used by a notification that points at a finished run.
  final int initialTab;

  const EngineLabScreen({super.key, this.initialTab = 0});

  @override
  State<EngineLabScreen> createState() => _EngineLabScreenState();
}

class _EngineLabScreenState extends State<EngineLabScreen>
    with SingleTickerProviderStateMixin {
  final BenchmarkService _service = BenchmarkService.shared;
  late final TabController _tabs = TabController(
    length: 5,
    initialIndex: widget.initialTab.clamp(0, 4).toInt(),
    vsync: this,
  );

  // Inventory
  List<EngineCandidate> _candidates = const [];
  List<EngineProfile> _profiles = const [];
  final Set<String> _selected = {};
  final Map<String, EngineIdentity> _identities = {};
  bool _loading = true;
  String? _loadError;

  // Configuration
  BenchmarkConfig _config = BenchmarkConfig.standard;
  TournamentFormat _format = TournamentFormat.roundRobin;
  String? _referenceId;
  String _customSuiteId = 'balanced-8';
  Map<String, OpeningSuite> _userSuites = const {};
  List<RatingAnchor> _anchors = const [];
  AutoBenchmarkSettings _auto = const AutoBenchmarkSettings();

  // Run state
  BenchmarkRunner? _runner;
  bool _running = false;
  bool _paused = false;
  String _status = '';
  double _progress = 0;
  int _gamesDone = 0;
  int _gamesTotal = 0;
  String _lastMove = '';
  final List<({String white, String black, int game, int total})> _liveGames = [];
  List<String> _liveNotices = const [];

  // History
  List<BenchmarkRunSummary> _history = const [];
  BenchmarkRun? _latestRun;

  // Diagnostics
  StabilityReport? _stability;
  String? _stabilityEngineId;
  bool _probing = false;

  StreamSubscription<BenchmarkEvent>? _subscription;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!mounted) return;
      setState(() {});
      // The diagnostics tab shows the identity of the selected engine, which
      // means starting it once. Loaded on arrival rather than on every build.
      if (_tabs.index == 4 && !_running) _loadIdentityForDiagnostics();
    });
    _load();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _service.init();
      final candidates = await _service.candidates();
      final profiles = await _service.profiles();
      final history = await _service.history();
      final lastIds = await _service.lastEngineIds();
      final config = await _service.lastConfig();
      final auto = await _service.autoSettings();
      final anchors = await _service.anchors();
      final suites = await _service.openingSuites();
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _profiles = profiles;
        _history = history;
        _config = config;
        _customSuiteId = config.openingSuiteId;
        _auto = auto;
        _anchors = anchors;
        _userSuites = suites;
        _selected
          ..clear()
          ..addAll(_defaultSelection(candidates, lastIds));
        if (_referenceId == null || !_selected.contains(_referenceId)) {
          _referenceId = _selected.isEmpty ? null : _selected.first;
        }
        _loading = false;
      });
      if (history.isNotEmpty) {
        final latest = await _service.loadRun(history.first.id);
        if (!mounted) return;
        setState(() => _latestRun = latest);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = '$error';
        _loading = false;
      });
    }
  }

  /// Which engines start selected: last time's choice, when it still exists,
  /// otherwise the first two that can run here.
  Set<String> _defaultSelection(
      List<EngineCandidate> candidates, List<String> lastIds) {
    final available = {
      for (final candidate in candidates)
        if (candidate.available) candidate.engineId
    };
    final remembered = [
      for (final id in lastIds)
        if (available.contains(id)) id
    ];
    if (remembered.length >= 2) return remembered.toSet();
    return available.take(2).toSet();
  }

  Future<void> _refreshHistory() async {
    final history = await _service.history();
    if (!mounted) return;
    setState(() => _history = history);
  }

  // ------------------------------------------------------------------- events

  void _attachRunner(BenchmarkRunner runner) {
    _subscription?.cancel();
    _runner = runner;
    _subscription = runner.events.listen(_onEvent);
  }

  void _onEvent(BenchmarkEvent event) {
    if (!mounted) return;
    switch (event) {
      case BenchmarkGameStartedEvent():
        setState(() {
          _gamesTotal = event.totalGames;
          _status = 'Game ${event.gameNumber}/${event.totalGames}: '
              '${event.whiteLabel} vs ${event.blackLabel}'
              '${event.openingName.isEmpty ? '' : ' · ${event.openingName}'}';
          _liveGames.insert(
            0,
            (
              white: event.whiteLabel,
              black: event.blackLabel,
              game: event.gameNumber,
              total: event.totalGames
            ),
          );
          if (_liveGames.length > 6) _liveGames.removeLast();
        });
      case BenchmarkMoveEvent():
        setState(() {
          _lastMove = event.san;
          _progress = _gamesTotal == 0
              ? 0
              : ((_gamesDone + (event.ply / 200).clamp(0.0, 0.9)) /
                      _gamesTotal)
                  .clamp(0.0, 1.0)
                  .toDouble();
        });
      case BenchmarkGameFinishedEvent():
        setState(() {
          _gamesDone = event.gamesCompleted;
          _progress = event.totalGames == 0
              ? 0
              : event.gamesCompleted / event.totalGames;
          _status = 'Game ${event.game.index} finished: '
              '${event.game.outcome.id}'
              '${event.game.detail == null ? '' : ' (${event.game.detail})'}';
        });
      case BenchmarkEngineFailedEvent():
        setState(() {
          _liveNotices = [
            ..._liveNotices,
            '${event.label}: ${event.reason}',
          ];
        });
      case BenchmarkNoticeEvent():
        setState(() {
          _liveNotices = [..._liveNotices, event.message];
        });
      case BenchmarkFinishedEvent():
        setState(() {
          _running = false;
          _paused = false;
          _runner = null;
          _latestRun = event.run;
          _status = 'Benchmark finished: ${event.run.gamesPlayed} game(s), '
              '${event.run.gamesCompleted} rated · ${event.run.stopReason}';
        });
    }
  }

  // ------------------------------------------------------------------ actions

  Future<void> _start() async {
    final l = AppLocalizations.of(context);
    if (_selected.length < 2) {
      _snack(l?.engineLabPickTwo ?? 'Select at least two engines.', error: true);
      return;
    }
    final validation = validateConfig(_config, engineCount: _selected.length);
    if (!validation.isValid) {
      _snack(validation.errors.join(' '), error: true);
      return;
    }
    // The estimate is computed from the configuration, not from a plan built
    // out of placeholder identities: the identities a run records come from
    // the engines themselves, inside the service, and inventing them here to
    // preview a number would be the kind of guess this feature exists to
    // avoid.
    final pairings = _format == TournamentFormat.gauntlet
        ? math.max(0, _selected.length - 1)
        : _selected.length * (_selected.length - 1) ~/ 2;
    final estimate = estimateWorkload(
      _config,
      engineCount: _selected.length,
      pairings: pairings,
    );
    final confirmed = await _confirmWorkload(
      l,
      engineCount: _selected.length,
      // The dialog quotes the estimate's own numbers, so it cannot promise a
      // different run from the one the planner will schedule.
      gamesPlanned: estimate.plannedGames,
      warmUpGames: estimate.warmUpGames,
      estimate: estimate,
      validation: validation,
    );
    if (confirmed != true) return;

    setState(() {
      _running = true;
      _paused = false;
      _gamesDone = 0;
      _progress = 0;
      _gamesTotal = estimate.scoredGames;
      _liveGames.clear();
      _liveNotices = const [];
      _lastMove = '';
      _status = l?.engineLabStarting ?? 'Starting engines…';
    });

    try {
      await _service.setLastConfig(_config);
      final runner = await _service.createRunner(
        engineIds: _selected.toList(),
        config: _config,
        format: _format,
        referenceEngineId:
            _format == TournamentFormat.gauntlet ? _referenceId : null,
        suites: _userSuites,
        anchor: _anchors.isEmpty ? null : _anchors.first,
        trigger: 'manual',
      );
      _attachRunner(runner);
      final run = await _service.runWithRunner(runner);
      if (!mounted) return;
      setState(() {
        _running = false;
        _runner = null;
        _latestRun = run;
      });
      await _refreshHistory();
      _snack(l?.engineLabFinished ?? 'Benchmark complete.');
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BenchmarkReportScreen(runId: run.id),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _runner = null;
      });
      _snack('${l?.engineLabFailed ?? 'The benchmark failed'}: $error',
          error: true);
    }
  }

  void _pause() {
    _runner?.pause();
    setState(() {
      _paused = true;
      _status = AppLocalizations.of(context)?.engineLabPaused ?? 'Paused.';
    });
  }

  void _resume() {
    _runner?.resume();
    setState(() {
      _paused = false;
      _status = AppLocalizations.of(context)?.engineLabRunning ?? 'Running…';
    });
  }

  void _cancel() {
    _runner?.cancel();
    setState(() {
      _status = AppLocalizations.of(context)?.engineLabCancelling ??
          'Cancelling after the current game…';
    });
  }

  Future<bool?> _confirmWorkload(
    AppLocalizations? l, {
    required int engineCount,
    required int gamesPlanned,
    required int warmUpGames,
    required WorkloadEstimate estimate,
    required BenchmarkValidation validation,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l?.engineLabConfirmTitle ?? 'Start this benchmark?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$engineCount ${l?.engineLabEngines ?? 'engines'} · '
                    '$gamesPlanned ${l?.engineLabGames ?? 'games'}'
                    '${warmUpGames > 0 ? ' (+$warmUpGames '
                        '${l?.engineLabWarmUp ?? 'warm-up'})' : ''}'),
                const SizedBox(height: 4),
                Text(l?.engineLabEstimate ?? 'Estimated time',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(_formatDuration(estimate.estimated)),
                Text('${l?.engineLabWorstCase ?? 'Worst case'}: '
                    '${_formatDuration(estimate.worstCase)}'),
                if (validation.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final warning in validation.warnings)
                    Text('• $warning', style: const TextStyle(fontSize: 12)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l?.cancel ?? 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l?.engineLabStart ?? 'Start'),
            ),
          ],
        ),
      );

  /// Loads the identity the diagnostics tab shows, once per engine.
  Future<void> _loadIdentityForDiagnostics([String? requested]) async {
    final candidates = [
      for (final candidate in _candidates)
        if (candidate.available) candidate
    ];
    final engineId = requested ??
        _stabilityEngineId ??
        (candidates.isEmpty ? null : candidates.first.engineId);
    if (engineId == null || _identities.containsKey(engineId)) return;
    try {
      final identity = await _service.identityFor(engineId);
      if (!mounted) return;
      setState(() => _identities[engineId] = identity);
    } catch (error) {
      // Reported in the tab's own words when it cannot be established; a
      // failure to identify an engine is not a reason to fail the screen.
      debugPrint('[EngineLab] could not identify $engineId: $error');
    }
  }

  Future<void> _runStability(String engineId) async {
    await _loadIdentityForDiagnostics(engineId);
    setState(() {
      _probing = true;
      _stabilityEngineId = engineId;
      _stability = null;
    });
    try {
      final report = await _service.probeStability(engineId);
      if (!mounted) return;
      setState(() => _stability = report);
    } catch (error) {
      if (!mounted) return;
      _snack('${AppLocalizations.of(context)?.engineLabFailed ?? 'Failed'}: '
          '$error', error: true);
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _deleteRun(String id) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l?.engineLabDeleteTitle ?? 'Delete this run?'),
        content: Text(l?.engineLabDeleteBody ??
            'The stored games, ratings and report for this run are removed '
                'from this device. Exported copies are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l?.delete ?? 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.deleteRun(id);
    if (!mounted) return;
    if (_latestRun?.id == id) setState(() => _latestRun = null);
    await _refreshHistory();
    if (_history.isNotEmpty && _latestRun == null) {
      final latest = await _service.loadRun(_history.first.id);
      if (!mounted) return;
      setState(() => _latestRun = latest);
    }
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack('$what ${AppLocalizations.of(context)?.copied ?? 'copied'}.');
  }

  Future<void> _import() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (text.trim().isEmpty) {
      _snack(AppLocalizations.of(context)?.engineLabImportEmpty ??
          'The clipboard is empty.', error: true);
      return;
    }
    try {
      final result = await _service.importRun(text);
      await _refreshHistory();
      if (!mounted) return;
      _snack([
        AppLocalizations.of(context)?.engineLabImported ?? 'Run imported.',
        if (result.idChanged)
          AppLocalizations.of(context)?.engineLabImportRenamed ??
              'It was stored under a new id so the existing run was kept.',
        ...result.warnings,
      ].join(' '));
    } catch (error) {
      if (!mounted) return;
      _snack('$error', error: true);
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      duration: Duration(seconds: error ? 6 : 3),
    ));
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l?.engineLab ?? 'Engine Lab'),
        actions: [
          IconButton(
            tooltip: l?.importBenchmark ?? 'Import a run from the clipboard',
            onPressed: _running ? null : _import,
            icon: const Icon(Icons.download_outlined),
          ),
          IconButton(
            tooltip: l?.refresh ?? 'Reload',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: [
            Tab(icon: const Icon(Icons.dashboard_outlined),
                text: l?.engineLabDashboard ?? 'Overview'),
            Tab(icon: const Icon(Icons.play_circle_outline),
                text: l?.engineLabBenchmark ?? 'Benchmark'),
            Tab(icon: const Icon(Icons.leaderboard_outlined),
                text: l?.engineLabLeaderboard ?? 'Ratings'),
            Tab(icon: const Icon(Icons.history), text: l?.engineLabHistory ?? 'History'),
            Tab(icon: const Icon(Icons.monitor_heart_outlined),
                text: l?.engineLabDiagnostics ?? 'Diagnostics'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? LabEmptyState(
                  icon: Icons.error_outline,
                  title: l?.engineLabFailed ?? 'The Lab could not load',
                  message: _loadError!,
                  action: FilledButton(
                    onPressed: _load,
                    child: Text(l?.retry ?? 'Try again'),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _overviewTab(l),
                    _benchmarkTab(l),
                    _ratingsTab(l),
                    _historyTab(l),
                    _diagnosticsTab(l),
                  ],
                ),
    );
  }

  // ------------------------------------------------------------------- tab 1

  Widget _overviewTab(AppLocalizations? l) {
    final available = _candidates.where((c) => c.available).toList();
    final latest = _latestRun;
    final progression = _progression(latest?.standings().firstOrNull?.engineId);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(
          title: l?.engineLab ?? 'Engine Lab',
          subtitle: l?.engineLabSubtitle ??
              'Measure the engines that are on this device, and keep the '
                  'measurements comparable.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _running ? null : () => _tabs.animateTo(1),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(l?.benchmarkNow ?? 'Benchmark now'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _running ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: Text(l?.refresh ?? 'Refresh'),
                  ),
                  if (_history.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _tabs.animateTo(3),
                      icon: const Icon(Icons.history),
                      label: Text('${_history.length} '
                          '${l?.engineLabRuns ?? 'runs'}'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('${available.length} ${l?.engineLabEngines ?? 'engines'} '
                  '· ${available.where((c) => c.isCustom).length} '
                  '${l?.engineLabCustom ?? 'custom'}'),
              if (!customEnginesSupported)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l?.engineLabWebNote ??
                        'In a browser only the engines that ship with the app '
                            'can run; a user-supplied executable cannot start.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (_running || _status.isNotEmpty)
          LabSection(
            title: l?.engineLabRunning ?? 'Benchmark in progress',
            actions: [
              if (_running && !_paused)
                IconButton(
                  tooltip: l?.pauseBenchmark ?? 'Pause',
                  onPressed: _pause,
                  icon: const Icon(Icons.pause),
                ),
              if (_running && _paused)
                IconButton(
                  tooltip: l?.resumeBenchmark ?? 'Resume',
                  onPressed: _resume,
                  icon: const Icon(Icons.play_arrow),
                ),
              if (_running)
                IconButton(
                  tooltip: l?.cancelBenchmark ?? 'Cancel',
                  onPressed: _cancel,
                  icon: const Icon(Icons.stop),
                ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progress.clamp(0.0, 1.0).toDouble()),
                const SizedBox(height: 8),
                Text(_status, style: const TextStyle(fontSize: 13)),
                if (_lastMove.isNotEmpty)
                  Text('${l?.engineLabLastMove ?? 'Last move'}: $_lastMove',
                      style: const TextStyle(fontSize: 12)),
                if (_liveNotices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final notice in _liveNotices.take(6))
                          Text('• $notice',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (latest != null)
          LabSection(
            title: l?.engineLabLatestResult ?? 'Latest result',
            subtitle: _formatDate(latest.finishedAt),
            actions: [
              TextButton(
                onPressed: () => _openRun(latest.id),
                child: Text(l?.engineLabOpenReport ?? 'Open report'),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final standing in latest.standings().take(5))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(standing.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                        ),
                        if (latest.ratings.ratingFor(standing.engineId)
                            case final rating?)
                          Text(
                            '${rating.rating.round()} '
                            '±${(kZ95 * rating.stdErr).round()}',
                            style: const TextStyle(
                                fontSize: 12, fontFeatures: []),
                          ),
                        const SizedBox(width: 8),
                        QualityBadge(
                          quality: latest.ratings
                                  .ratingFor(standing.engineId)
                                  ?.quality ??
                              RatingQuality.insufficient,
                          label: _qualityLabel(l,
                              latest.ratings
                                  .ratingFor(standing.engineId)
                                  ?.quality),
                        ),
                      ],
                    ),
                  ),
                if (latest.calibration.available)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(latest.calibration.reason,
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
        if (progression.length >= 2)
          LabSection(
            title: l?.engineLabProgression ?? 'Progression',
            subtitle: l?.engineLabProgressionHint ??
                'Relative rating of the leading engine across the stored runs, '
                    'on the same scale. Only comparable within one cohort.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProgressionBar(
                  values: [for (final point in progression) point.rating],
                  labels: [for (final point in progression) point.label],
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 6),
                Text(
                  '${progression.first.rating.round()} → '
                  '${progression.last.rating.round()}'
                  '${_deltaLabel(l, progression)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        LabSection(
          title: l?.engineLabAutomatic ?? 'Automatic benchmarks',
          subtitle: l?.engineLabAutomaticSubtitle ??
              'Run the Quick preset in the background after an engine is added '
                  'or changes. Never longer than the budget below.',
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _auto.afterAdd,
                onChanged: (value) => _setAuto(_auto.copyWith(afterAdd: value)),
                title: Text(l?.engineLabAutoAfterAdd ?? 'When an engine is added'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _auto.afterVersionChange,
                onChanged: (value) =>
                    _setAuto(_auto.copyWith(afterVersionChange: value)),
                title: Text(
                    l?.engineLabAutoAfterChange ?? 'When an engine changes'),
              ),
              LabInfoRow(
                label: l?.engineLabBudget ?? 'Budget',
                value: '${_auto.maxGames} ${l?.engineLabGames ?? 'games'} · '
                    '${_auto.maxDuration.inMinutes} min',
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Adds a calibration anchor.
  ///
  /// Every field the calibration needs is asked for by name, because a rating
  /// without a source, a date, hardware and a time control cannot be checked
  /// against this run — and the Lab refuses to calibrate from one.
  Future<void> _addAnchor() async {
    final l = AppLocalizations.of(context);
    final engineChoices = [
      for (final candidate in _candidates)
        if (candidate.available) candidate
    ];
    final controllers = {
      'rating': TextEditingController(),
      'scale': TextEditingController(text: 'CCRL 40/2'),
      'source': TextEditingController(),
      'date': TextEditingController(),
      'hardware': TextEditingController(),
      'timeControl': TextEditingController(),
      'budget': TextEditingController(),
      'version': TextEditingController(),
    };
    var engineId = _selected.isEmpty
        ? (engineChoices.isEmpty ? null : engineChoices.first.engineId)
        : _selected.first;
    var error = '';

    final created = await showDialog<RatingAnchor>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final budget = int.tryParse(controllers['budget']!.text.trim());
          RatingAnchor buildAnchor() => RatingAnchor(
                id: 'anchor-${DateTime.now().millisecondsSinceEpoch}',
                engineName: engineId == null
                    ? ''
                    : engineLabelForId(engineId!, _profiles),
                engineIdHint: engineId,
                engineVersion: controllers['version']!.text.trim(),
                rating: double.tryParse(controllers['rating']!.text.trim()) ?? 0,
                scale: controllers['scale']!.text.trim(),
                source: controllers['source']!.text.trim(),
                publishedDate: controllers['date']!.text.trim(),
                hardware: controllers['hardware']!.text.trim(),
                timeControl: controllers['timeControl']!.text.trim(),
                // Null rather than 0 when the budget is not stated: the
                // calibration then warns that it cannot check the budget,
                // instead of dividing by zero.
                timePerMoveMs: budget != null && budget > 0 ? budget : null,
              );

          return AlertDialog(
            title: Text(l?.engineLabAddAnchor ?? 'Add a calibration anchor'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.engineLabAnchorIntro ??
                          'A published rating is only usable if its source, '
                              'date, hardware and time control are recorded, '
                              'and the engine takes part in the run.',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: engineId,
                      items: [
                        for (final candidate in engineChoices)
                          DropdownMenuItem(
                            value: candidate.engineId,
                            child: Text(candidate.label,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() => engineId = value),
                    ),
                    _anchorField(controllers['version']!,
                        l?.engineLabVersion ?? 'Engine version', '17'),
                    _anchorField(controllers['rating']!,
                        l?.engineLabAnchorRating ?? 'Published rating', '3600',
                        number: true),
                    _anchorField(controllers['scale']!,
                        l?.engineLabAnchorScale ?? 'Rating list or scale',
                        'CCRL 40/2'),
                    _anchorField(controllers['source']!,
                        l?.engineLabAnchorSource ?? 'Source (URL or publication)',
                        'https://…'),
                    _anchorField(controllers['date']!,
                        l?.engineLabAnchorDate ?? 'Published (YYYY-MM-DD)',
                        '2026-01-31'),
                    _anchorField(controllers['hardware']!,
                        l?.engineLabAnchorHardware ?? 'Hardware',
                        'Ryzen 9 7950X'),
                    _anchorField(controllers['timeControl']!,
                        l?.engineLabAnchorTimeControl ?? 'Time control',
                        '40 moves / 2 min'),
                    _anchorField(controllers['budget']!,
                        l?.engineLabAnchorBudget ?? 'Move budget (ms)',
                        '3000',
                        number: true),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error,
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l?.cancel ?? 'Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final anchor = buildAnchor();
                  if (!anchor.isComplete) {
                    setDialogState(() {
                      error = '${l?.engineLabAnchorMissing ?? 'Missing'}: '
                          '${anchor.missingFields.join(', ')}';
                    });
                    return;
                  }
                  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$')
                      .hasMatch(anchor.publishedDate)) {
                    setDialogState(() {
                      error = l?.engineLabAnchorDateHint ??
                          'Write the publication date as YYYY-MM-DD.';
                    });
                    return;
                  }
                  Navigator.pop(context, anchor);
                },
                child: Text(l?.save ?? 'Save'),
              ),
            ],
          );
        },
      ),
    );

    // The controllers are left to the garbage collector rather than disposed
    // here: the dialog's exit animation can still be rebuilding its fields
    // when this future completes, and a disposed controller that a live
    // TextField touches throws.
    if (created == null) return;
    final anchors = [..._anchors, created];
    await _service.saveAnchors(anchors);
    if (!mounted) return;
    setState(() => _anchors = anchors);
  }

  Widget _anchorField(TextEditingController controller, String label,
          String hint,
          {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: controller,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  Future<void> _removeAnchor(RatingAnchor anchor) async {
    final anchors = [
      for (final entry in _anchors)
        if (entry.id != anchor.id) entry
    ];
    await _service.saveAnchors(anchors);
    if (!mounted) return;
    setState(() => _anchors = anchors);
  }

  Future<void> _setAuto(AutoBenchmarkSettings settings) async {
    setState(() => _auto = settings);
    await _service.setAutoSettings(settings);
  }

  List<({double rating, String label})> _progression(String? engineId) {
    if (engineId == null) return const [];
    final points = <({double rating, String label})>[];
    for (final summary in _history.reversed) {
      final rating = summary.ratings[engineId];
      if (rating == null) continue;
      points.add((rating: rating, label: _shortDate(summary.startedAt)));
    }
    return points;
  }

  String _deltaLabel(
      AppLocalizations? l, List<({double rating, String label})> points) {
    final delta = points.last.rating - points.first.rating;
    if (delta.abs() < 1) return ' (${l?.engineLabUnchanged ?? 'unchanged'})';
    final sign = delta > 0 ? '+' : '−';
    return ' ($sign${delta.abs().round()})';
  }

  // ------------------------------------------------------------------- tab 2

  Widget _benchmarkTab(AppLocalizations? l) {
    final available = [
      for (final candidate in _candidates)
        if (candidate.available) candidate
    ];
    final unavailable = [
      for (final candidate in _candidates)
        if (!candidate.available) candidate
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(
          title: l?.engineLabSelectEngines ?? 'Engines',
          subtitle: '${_selected.length} ${l?.engineLabSelected ?? 'selected'}',
          actions: [
            TextButton(
              onPressed: _running
                  ? null
                  : () => setState(() {
                        _selected
                          ..clear()
                          ..addAll(available.map((c) => c.engineId));
                        _referenceId = _selected.isEmpty ? null : _selected.first;
                      }),
              child: Text(l?.selectAll ?? 'Select all'),
            ),
            TextButton(
              onPressed: _running
                  ? null
                  : () => setState(() {
                        _selected.clear();
                        _referenceId = null;
                      }),
              child: Text(l?.clearSelection ?? 'Clear'),
            ),
          ],
          child: Column(
            children: [
              for (final candidate in available)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _selected.contains(candidate.engineId),
                  onChanged: _running
                      ? null
                      : (value) => setState(() {
                            if (value == true) {
                              _selected.add(candidate.engineId);
                              _referenceId ??= candidate.engineId;
                            } else {
                              _selected.remove(candidate.engineId);
                              if (_referenceId == candidate.engineId) {
                                _referenceId = _selected.isEmpty
                                    ? null
                                    : _selected.first;
                              }
                            }
                          }),
                  title: Text(candidate.label,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    candidate.isCustom
                        ? (l?.customConfiguration ?? 'User-added engine')
                        : (l?.engineLabBuiltIn ?? 'Ships with the app'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              if (unavailable.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('${unavailable.length} '
                      '${l?.engineLabUnavailable ?? 'unavailable here'}',
                      style: const TextStyle(fontSize: 13)),
                  children: [
                    for (final candidate in unavailable)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(candidate.label,
                            style: const TextStyle(fontSize: 12)),
                        subtitle: Text(candidate.unavailableReason ?? '—',
                            style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabFormat ?? 'Format',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<TournamentFormat>(
                segments: [
                  ButtonSegment(
                    value: TournamentFormat.roundRobin,
                    label: Text(l?.formatRoundRobin ?? 'Round robin'),
                  ),
                  ButtonSegment(
                    value: TournamentFormat.gauntlet,
                    label: Text(l?.formatGauntlet ?? 'Gauntlet'),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: _running
                    ? null
                    : (selection) => setState(() {
                          _format = selection.first;
                          _referenceId ??=
                              _selected.isEmpty ? null : _selected.first;
                        }),
              ),
              if (_format == TournamentFormat.gauntlet)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text('${l?.engineLabReference ?? 'Reference'}: ',
                          style: const TextStyle(fontSize: 12)),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selected.contains(_referenceId)
                              ? _referenceId
                              : null,
                          hint: Text(l?.engineLabReference ?? 'Reference'),
                          items: [
                            for (final id in _selected)
                              DropdownMenuItem(
                                value: id,
                                child: Text(engineLabelForId(id, _profiles)),
                              ),
                          ],
                          onChanged: _running
                              ? null
                              : (value) => setState(() => _referenceId = value),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_format == TournamentFormat.gauntlet)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l?.engineLabGauntletHint ??
                        'Each challenger plays the reference engine; the '
                            'reference is not rated against itself.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabPreset ?? 'Preset',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<BenchmarkPreset>(
                segments: [
                  for (final preset in BenchmarkPreset.values)
                    ButtonSegment(
                      value: preset,
                      label: Text(_presetLabel(l, preset)),
                    ),
                ],
                selected: {_config.preset},
                onSelectionChanged: _running
                    ? null
                    : (selection) => setState(() =>
                        _config = _applyPreset(selection.first, _config)),
              ),
              const SizedBox(height: 8),
              LabInfoRow(
                label: l?.engineLabConfiguration ?? 'Configuration',
                value: _config.summary,
              ),
              LabInfoRow(
                label: l?.engineLabOpeningSuite ?? 'Opening suite',
                value: openingSuiteById(_customSuiteId, extra: _userSuites).name,
              ),
              if (_config.preset == BenchmarkPreset.custom)
                _customConfiguration(l),
            ],
          ),
        ),
        LabSection(
          title: l?.calibrationAnchors ?? 'Calibration anchors',
          subtitle: l?.engineLabCalibrationHint ??
              'A published rating for an engine that takes part in the run is '
                  'the only way the relative scale becomes an absolute one.',
          actions: [
            TextButton.icon(
              onPressed: _running ? null : _addAnchor,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l?.engineLabAddAnchor ?? 'Add anchor'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_anchors.isEmpty)
                Text(l?.engineLabNoAnchors ??
                    'No anchor declared; ratings stay relative.')
              else
                for (final anchor in _anchors)
                  Row(
                    children: [
                      Expanded(
                        child: LabInfoRow(
                          label: '${anchor.engineName}'
                              '${anchor.engineVersion.isEmpty ? '' : ' ${anchor.engineVersion}'}',
                          value: '${anchor.rating.round()} ${anchor.scale} · '
                              '${anchor.publishedDate} · ${anchor.source}',
                        ),
                      ),
                      IconButton(
                        tooltip: l?.engineLabRemoveAnchor ?? 'Remove anchor',
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: _running ? null : () => _removeAnchor(anchor),
                      ),
                    ],
                  ),
              if (_anchors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l?.engineLabAnchorUsedHint ??
                        'The first anchor that matches an engine in the run is '
                            'used; an anchor for an engine that is not in the '
                            'run cannot calibrate anything.',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _running ? null : _start,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_running
                      ? (l?.engineLabRunning ?? 'Running…')
                      : (l?.startBenchmark ?? 'Start benchmark')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  BenchmarkConfig _applyPreset(BenchmarkPreset preset, BenchmarkConfig current) {
    switch (preset) {
      case BenchmarkPreset.quick:
        return BenchmarkConfig.quick.copyWith(
          openingSuiteId: current.openingSuiteId,
          threads: current.threads,
          hashMb: current.hashMb,
        );
      case BenchmarkPreset.standard:
        return BenchmarkConfig.standard.copyWith(
          openingSuiteId: current.openingSuiteId,
          threads: current.threads,
          hashMb: current.hashMb,
        );
      case BenchmarkPreset.accurate:
        return BenchmarkConfig.accurate.copyWith(
          openingSuiteId: current.openingSuiteId,
          threads: current.threads,
          hashMb: current.hashMb,
        );
      case BenchmarkPreset.custom:
        return current.copyWith(preset: BenchmarkPreset.custom);
    }
  }

  Widget _customConfiguration(AppLocalizations? l) {
    final suites = [
      for (final suite in availableOpeningSuites(extra: _userSuites))
        (id: suite.id, name: suite.name)
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 24),
        LabInfoRow(
          label: l?.engineLabEstimate ?? 'Estimated time',
          value: _formatDuration(
              estimateWorkload(_config,
                      engineCount: _selected.length < 2 ? 2 : _selected.length,
                      pairings: _selected.length < 2
                          ? 1
                          : _selected.length * (_selected.length - 1) ~/ 2)
                  .estimated),
        ),
        Row(
          children: [
            Text('${l?.engineLabOpeningSuite ?? 'Opening suite'}: ',
                style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              // A plain DropdownButton rather than a form field: the value is
              // always one of the items, and this matches how every other
              // dropdown in the app is built.
              child: DropdownButton<String>(
                isExpanded: true,
                value: suites.any((suite) => suite.id == _customSuiteId)
                    ? _customSuiteId
                    : suites.first.id,
                items: [
                  for (final suite in suites)
                    DropdownMenuItem(
                      value: suite.id,
                      child: Text(suite.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: _running
                    ? null
                    : (value) => setState(() {
                          _customSuiteId = value ?? _config.openingSuiteId;
                          _config =
                              _config.copyWith(openingSuiteId: _customSuiteId);
                        }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabMovesPerPairing ?? 'Games per pairing',
                value: _config.gamesPerPairing,
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    gamesPerPairing: (value ?? 2).clamp(2, 400).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabMaxGames ?? 'Max games',
                value: _config.maxGames ?? 0,
                helper: l?.engineLabZeroIsUnlimited ?? '0 = no limit',
                enabled: !_running,
                onChanged: (value) => setState(() {
                  final max = value ?? 0;
                  _config = _config.copyWith(
                    maxGames: () => max <= 0 ? null : max,
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabTimePerMoveMs ?? 'Time per move (ms)',
                value: _config.timePerMove.inMilliseconds,
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    timePerMove: Duration(
                        milliseconds:
                            (value ?? 100).clamp(10, 60000).toInt()),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabSearchDepth ?? 'Search depth',
                value: _config.searchDepth ?? 0,
                helper: l?.engineLabZeroIsTime ?? '0 = use the clock',
                enabled: !_running,
                onChanged: (value) => setState(() {
                  final depth = value ?? 0;
                  _config = _config.copyWith(
                    searchDepth: () => depth <= 0 ? null : depth,
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabPlyCap ?? 'Ply cap',
                value: _config.plyCap,
                helper: l?.engineLabPlyCapHint ??
                    'A game stopped here is adjudicated, not drawn',
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    plyCap: (value ?? 160).clamp(20, 2000).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabMaxMinutes ?? 'Max minutes',
                value: _config.maxDuration?.inMinutes ?? 0,
                helper: l?.engineLabZeroIsUnlimited ?? '0 = no limit',
                enabled: !_running,
                onChanged: (value) => setState(() {
                  final minutes = value ?? 0;
                  _config = _config.copyWith(
                    maxDuration: () =>
                        minutes <= 0 ? null : Duration(minutes: minutes),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabThreads ?? 'Threads',
                value: _config.threads,
                helper: l?.engineLabZeroIsEngineDefault ?? "0 = engine's own",
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    threads: (value ?? 0).clamp(0, 256).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabHash ?? 'Hash (MB)',
                value: _config.hashMb,
                helper: l?.engineLabZeroIsEngineDefault ?? "0 = engine's own",
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    hashMb: (value ?? 0).clamp(0, 65536).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabSeed ?? 'Seed',
                value: _config.seed,
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    seed: value ?? _config.seed,
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabRepetitions ?? 'Repetitions',
                value: _config.repetitions,
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    repetitions: (value ?? 1).clamp(1, 20).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                label: l?.engineLabWarmUp ?? 'Warm-up games',
                value: _config.warmUpGames,
                enabled: !_running,
                onChanged: (value) => setState(() {
                  _config = _config.copyWith(
                    warmUpGames: (value ?? 0).clamp(0, 20).toInt(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _numberField(
                label: l?.engineLabTargetStdErr ?? 'Stop at ±Elo',
                value: _config.targetStdErr?.round() ?? 0,
                helper: l?.engineLabZeroIsNever ?? '0 = run the whole plan',
                enabled: !_running,
                onChanged: (value) => setState(() {
                  final target = value ?? 0;
                  _config = _config.copyWith(
                    adaptiveStopping: target > 0,
                    targetStdErr: () => target <= 0 ? null : target.toDouble(),
                    preset: BenchmarkPreset.custom,
                  );
                }),
              ),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _config.balanceColors,
          onChanged: _running
              ? null
              : (value) => setState(() =>
                  _config = _config.copyWith(balanceColors: value)),
          title: Text(l?.engineLabBalanceColors ?? 'Both colours per opening'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _config.adaptiveStopping,
          onChanged: _running
              ? null
              : (value) => setState(() =>
                  _config = _config.copyWith(adaptiveStopping: value)),
          title: Text(l?.engineLabAdaptiveStopping ?? 'Stop early when precise'),
        ),
      ],
    );
  }

  Widget _numberField({
    required String label,
    required int value,
    required ValueChanged<int?> onChanged,
    bool enabled = true,
    String? helper,
  }) =>
      TextFormField(
        key: ValueKey('$label-$value-$enabled'),
        initialValue: '$value',
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          isDense: true,
        ),
        onChanged: (text) => onChanged(int.tryParse(text.trim())),
      );

  // ------------------------------------------------------------------- tab 3

  Widget _ratingsTab(AppLocalizations? l) {
    final run = _latestRun;
    if (run == null) {
      return LabEmptyState(
        icon: Icons.leaderboard_outlined,
        title: l?.engineLabNoRatings ?? 'No ratings yet',
        message: l?.engineLabNoRatingsHint ??
            'Run a benchmark and the ratings for the engines that took part '
                'appear here, with the interval behind each number.',
        action: FilledButton(
          onPressed: () => _tabs.animateTo(1),
          child: Text(l?.benchmarkNow ?? 'Benchmark now'),
        ),
      );
    }
    final standings = run.standings();
    final ratings = run.ratings.ratings;
    final low = ratings.isEmpty
        ? 0.0
        : ratings.map((r) => r.ciLow).reduce((a, b) => a < b ? a : b);
    final high = ratings.isEmpty
        ? 0.0
        : ratings.map((r) => r.ciHigh).reduce((a, b) => a > b ? a : b);
    final compareA = _compareA ?? (ratings.isEmpty ? null : ratings.first.engineId);
    final compareB = _compareB ?? (ratings.length < 2 ? null : ratings.last.engineId);
    final comparison = compareA != null && compareB != null
        ? run.ratings.compare(compareA, compareB)
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(
          title: l?.relativeElo ?? 'Relative Elo',
          subtitle: l?.engineLabRelativeScaleHint ??
              'Centred on 1500 across these engines. A relative scale, not '
                  'absolute strength.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final rating in ratings)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(rating.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ),
                          Text('${rating.rating.round()}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 6),
                          Text('±${(kZ95 * rating.stdErr).round()}',
                              style: const TextStyle(fontSize: 11)),
                          const SizedBox(width: 6),
                          QualityBadge(
                            quality: rating.quality,
                            label: _qualityLabel(l, rating.quality),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      RatingBar(
                        label: rating.label,
                        rating: rating.rating,
                        ciLow: rating.ciLow,
                        ciHigh: rating.ciHigh,
                        minRating: low - 20,
                        maxRating: high + 20,
                        color: qualityColor(context, rating.quality),
                      ),
                      Text(
                        '${rating.games} ${l?.engineLabRatedGames ?? 'rated'} · '
                        '${rating.wins}/${rating.draws}/${rating.losses} · '
                        '${rating.scorePercent.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              if (ratings.isEmpty)
                Text(l?.engineLabNoRatedGames ??
                    'This run produced no rating-eligible games.'),
              for (final warning in run.ratings.warnings)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('• $warning',
                      style:
                          TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
        if (ratings.length >= 2)
          LabSection(
            title: l?.engineLabCompare ?? 'Compare two engines',
            subtitle: l?.engineLabCompareHint ??
                'A difference smaller than its own interval is not a result.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: compareA,
                        items: [
                          for (final rating in ratings)
                            DropdownMenuItem(
                              value: rating.engineId,
                              child: Text(rating.label,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) => setState(() => _compareA = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: compareB,
                        items: [
                          for (final rating in ratings)
                            DropdownMenuItem(
                              value: rating.engineId,
                              child: Text(rating.label,
                                  overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (value) => setState(() => _compareB = value),
                      ),
                    ),
                  ],
                ),
                if (comparison != null) ...[
                  const SizedBox(height: 8),
                  Text(comparison.verdict,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    '${comparison.difference >= 0 ? '+' : '−'}'
                    '${comparison.difference.abs().toStringAsFixed(0)} '
                    '${l?.elo ?? 'Elo'}, 95% '
                    '${comparison.ciLow.toStringAsFixed(0)}…'
                    '${comparison.ciHigh.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  for (final warning in comparison.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $warning',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ],
            ),
          ),
        if (run.calibration.available)
          LabSection(
            title: l?.calibratedElo ?? 'Calibrated Elo',
            subtitle: run.calibration.reason,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in run.calibration.calibrated.entries)
                  LabInfoRow(
                    label: run.identityFor(entry.key)?.label ?? entry.key,
                    value: entry.value.toStringAsFixed(0),
                  ),
                for (final warning in run.calibration.warnings)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• $warning',
                        style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          )
        else
          LabSection(
            title: l?.calibratedElo ?? 'Calibrated Elo',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l?.engineLabCalibrationUnavailable ??
                    'No calibrated rating for this run:'),
                const SizedBox(height: 4),
                Text(run.calibration.reason,
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        LabSection(
          title: l?.engineLabPerformance ?? 'Performance',
          child: Column(
            children: [
              for (final aggregate in standings)
                LabInfoRow(
                  label: aggregate.label,
                  value: _performanceSummary(l, aggregate),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String? _compareA;
  String? _compareB;

  String _performanceSummary(AppLocalizations? l, EngineAggregate aggregate) {
    if (aggregate.moveMillis.isEmpty) {
      return l?.engineLabNoMetrics ?? 'no move timing recorded';
    }
    return 'p50 ${aggregate.percentile(50)} ms · '
        'p95 ${aggregate.percentile(95)} ms · '
        'p99 ${aggregate.percentile(99)} ms · '
        'max ${aggregate.maxMillis} ms';
  }

  // ------------------------------------------------------------------- tab 4

  Widget _historyTab(AppLocalizations? l) {
    if (_history.isEmpty) {
      return LabEmptyState(
        icon: Icons.history,
        title: l?.engineLabNoHistory ?? 'No stored runs',
        message: l?.engineLabNoHistoryHint ??
            'Every finished benchmark is kept here, with its games, ratings '
                'and report. Nothing is stored when a run starts; a partial '
                'run is kept only if games were actually played.',
        action: FilledButton(
          onPressed: () => _tabs.animateTo(1),
          child: Text(l?.benchmarkNow ?? 'Benchmark now'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final summary = _history[index];
        return ListTile(
          title: Text(
            summary.engineLabels.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${_formatDate(summary.finishedAt)} · '
            '${summary.gamesPlayed} ${l?.engineLabGames ?? 'games'} '
            '(${summary.ratedGames} ${l?.engineLabRated ?? 'rated'}) · '
            '${summary.preset}'
            '${summary.stopReason == 'in progress' ? ' · ${l?.engineLabInProgress ?? 'in progress'}' : ''}',
            style: const TextStyle(fontSize: 11),
          ),
          onTap: () => _openRun(summary.id),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => _historyAction(value, summary),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: 'open', child: Text(l?.engineLabOpenReport ?? 'Open')),
              PopupMenuItem(
                  value: 'json', child: Text(l?.exportJson ?? 'Export JSON')),
              PopupMenuItem(value: 'csv', child: Text(l?.exportCsv ?? 'Export CSV')),
              PopupMenuItem(value: 'pgn', child: Text(l?.exportPgn ?? 'Export PGN')),
              PopupMenuItem(
                  value: 'delete', child: Text(l?.delete ?? 'Delete')),
            ],
          ),
        );
      },
    );
  }

  Future<void> _historyAction(String action, BenchmarkRunSummary summary) async {
    if (action == 'delete') return _deleteRun(summary.id);
    if (action == 'open') return _openRun(summary.id);
    final run = await _service.loadRun(summary.id);
    if (run == null) {
      _snack(AppLocalizations.of(context)?.engineLabReportMissing ??
          'That run could not be read.', error: true);
      return;
    }
    await _exportRun(run, action);
  }

  Future<void> _exportRun(BenchmarkRun run, String kind) async {
    switch (kind) {
      case 'json':
        return _copy(BenchmarkStore.encodeRunDocument(run), 'JSON');
      case 'csv':
        return _copy('${run.enginesCsv()}\n\n${run.gamesCsv()}', 'CSV');
      case 'pgn':
        return _copy(run.pgn(), 'PGN');
      case 'report':
        return _copy(run.reportMarkdown(), 'Markdown');
    }
  }

  void _openRun(String id) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => BenchmarkReportScreen(runId: id)));
  }

  // ------------------------------------------------------------------- tab 5

  Widget _diagnosticsTab(AppLocalizations? l) {
    final choosable = [
      for (final candidate in _candidates)
        if (candidate.available) candidate
    ];
    final selected = _stabilityEngineId ??
        (choosable.isEmpty ? null : choosable.first.engineId);
    final identity = selected == null ? null : _identities[selected];
    final report = _stability;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabSection(
          title: l?.engineLabEnvironment ?? 'Environment',
          child: Column(
            children: [
              LabInfoRow(
                label: l?.engineLabPlatform ?? 'Platform',
                value: platformLabel(),
              ),
              LabInfoRow(label: l?.engineLabHost ?? 'Host', value: hostSummary()),
              LabInfoRow(
                label: l?.engineLabAppVersion ?? 'App',
                value: kBenchmarkFormatVersion,
              ),
              if (identity != null) ...[
                LabInfoRow(
                  label: l?.engineLabIdentity ?? 'Identity',
                  value: identity.label,
                ),
                LabInfoRow(
                  label: l?.engineLabFingerprint ?? 'Fingerprint',
                  value: identity.fingerprintKind == 'unavailable'
                      ? (l?.engineLabNoFingerprint ?? 'unavailable')
                      : '${identity.fingerprintKind} '
                          '${identity.shortFingerprint}',
                ),
                LabInfoRow(
                  label: l?.engineLabBackend ?? 'Backend',
                  value: identity.cohortKey,
                ),
              ],
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabStability ?? 'Stability',
          subtitle: l?.engineLabStabilityHint ??
              'Start an engine several times and search several times, and '
                  'report a hang, a crash or a missing answer instead of '
                  'averaging it away.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: selected,
                      items: [
                        for (final candidate in choosable)
                          DropdownMenuItem(
                            value: candidate.engineId,
                            child: Text(candidate.label,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: _probing
                          ? null
                          : (value) =>
                              setState(() => _stabilityEngineId = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _probing || selected == null
                        ? null
                        : () => _runStability(selected),
                    child: Text(l?.engineLabRunStability ?? 'Run check'),
                  ),
                ],
              ),
              if (_probing)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (report != null) ...[
                const SizedBox(height: 8),
                for (final check in report.checks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        StateChip(
                          label: check.ok ? 'ok' : 'fail',
                          color: check.ok
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                          icon: check.ok ? Icons.check : Icons.close,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${check.name} '
                            '(${check.passed}/${check.attempts})'
                            '${check.failures.isEmpty ? '' : ' — ${check.failures.join('; ')}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (report.failures.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        report.failures.join('\n'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        )),
                  ),
              ],
            ],
          ),
        ),
        LabSection(
          title: l?.engineLabMethod ?? 'Method and limits',
          child: Text(
            l?.engineLabMethodBody ??
                'Ratings are fitted to every game at once (Bradley–Terry), '
                    'centred on 1500 across the engines in one run. A rating '
                    'is only comparable with another from the same platform '
                    'and backend; the Lab records which cohort a run belongs '
                    'to. Games lost by forfeit, aborted, or stopped at the ply '
                    'cap are counted but not rated. Calibrated Elo exists only '
                    'when a published rating for an engine in the run was '
                    'declared, with its source, date, hardware and time '
                    'control, and the move budget matches within 20%.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------------- helpers

  String _presetLabel(AppLocalizations? l, BenchmarkPreset preset) =>
      switch (preset) {
        BenchmarkPreset.quick => l?.presetQuick ?? 'Quick',
        BenchmarkPreset.standard => l?.presetStandard ?? 'Standard',
        BenchmarkPreset.accurate => l?.presetAccurate ?? 'Accurate',
        BenchmarkPreset.custom => l?.presetCustom ?? 'Custom',
      };

  String _qualityLabel(AppLocalizations? l, RatingQuality? quality) =>
      switch (quality) {
        RatingQuality.high => l?.engineLabQualityHigh ?? 'precise',
        RatingQuality.moderate => l?.engineLabQualityModerate ?? 'usable',
        RatingQuality.low => l?.engineLabQualityLow ?? 'rough',
        _ => l?.engineLabQualityInsufficient ?? 'too few games',
      };

  String _formatDuration(Duration duration) {
    if (duration.inSeconds < 60) return '${duration.inSeconds}s';
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m ${seconds}s';
  }

  String _formatDate(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  String _shortDate(DateTime time) {
    final local = time.toLocal();
    return '${_two(local.month)}-${_two(local.day)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
