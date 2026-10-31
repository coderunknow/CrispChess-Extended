import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engines/chess_engine.dart';
import '../engines/chess_lm_engine.dart' show availableChessLmNames;
import '../engines/engine_registry.dart';
import '../engines/engine_fingerprint.dart';
import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../engines/searchless_engine.dart' show availableSearchlessSizes;
import '../services/engine_lab_models.dart';
import '../services/engine_lab_store.dart';
import '../services/engine_match_service.dart';
import '../services/engine_profile_store.dart';
import '../services/rating_fit.dart';

/// A local-first benchmark dashboard. The runner deliberately uses the same
/// match/tournament services as the existing Engine-vs-Engine feature.
class EngineLabScreen extends StatefulWidget {
  const EngineLabScreen({super.key, this.initialEngineId, this.autoStart = false});

  final String? initialEngineId;
  final bool autoStart;

  @override
  State<EngineLabScreen> createState() => _EngineLabScreenState();
}

class _EngineLabScreenState extends State<EngineLabScreen> {
  static const _autoVersionKey = 'engine_lab_auto_quick_on_binary_change';
  static const _builtIns = [
    'Built-in', 'Frozenight', 'Stockfish', 'Lynx', 'Maia3 Dart', 'ChessMamba', 'Lc0',
    for (final e in availableSearchlessSizes) e.engineName,
    ...availableChessLmNames,
  ];

  final _profileStore = EngineProfileStore();
  final _historyStore = EngineLabStore();
  final Set<String> _selected = {
    builtInEngineId('Built-in'),
    builtInEngineId('Frozenight'),
  };
  final _timeController = TextEditingController(text: '100');
  final _gamesController = TextEditingController(text: '2');
  final _gameCapController = TextEditingController(text: '120');
  final _plyController = TextEditingController(text: '160');
  List<EngineProfile> _profiles = const [];
  List<EngineBenchmarkRun> _history = const [];
  List<GameResult> _liveGames = [];
  EngineBenchmarkPreset _preset = EngineBenchmarkPreset.quick;
  TournamentService? _runner;
  StreamSubscription<MatchEvent>? _subscription;
  bool _loading = true;
  bool _running = false;
  String? _error;
  String? _versionNotice;
  int _expectedGames = 0;
  int _runCompleted = 0;
  String _progressText = '';
  bool _cancelRequested = false;

  List<({String id, String label})> get _choices => matchEngineChoices(_builtIns, _profiles);

  EngineBenchmarkConfig get _config => EngineBenchmarkConfig(
        preset: _preset,
        timePerMoveMs: int.tryParse(_timeController.text) ?? -1,
        gamesPerPairing: int.tryParse(_gamesController.text) ?? -1,
        maxGames: int.tryParse(_gameCapController.text) ?? -1,
        plyLimit: int.tryParse(_plyController.text) ?? -1,
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        _profileStore.load(),
        _historyStore.load(),
      ]);
      final profiles = values[0] as List<EngineProfile>;
      final history = values[1] as List<EngineBenchmarkRun>;
      final prefs = await SharedPreferences.getInstance();
      EngineProfile? changedProfile;
      for (final profile in profiles) {
        final oldFingerprint = profile.binaryFingerprint;
        final oldMetadata = profile.binaryFingerprintMetadata;
        try {
          await refreshEngineFingerprint(profile);
        } catch (e) {
          debugPrint('[EngineLab] fingerprint refresh failed for profile ${profile.id}: $e');
        }
        if (oldFingerprint != profile.binaryFingerprint ||
            oldMetadata != profile.binaryFingerprintMetadata) {
          await _profileStore.update(profile);
        }
        final id = customEngineId(profile);
        final previous = history
            .where((run) => run.engines.any((engine) => engine.id == id && engine.binaryFingerprint != null))
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
        if (changedProfile == null && previous.isNotEmpty &&
            profile.binaryFingerprint != previous.first.engines
                .firstWhere((engine) => engine.id == id)
                .binaryFingerprint) {
          changedProfile = profile;
        }
      }
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _history = history;
        final availableIds = _choices.map((choice) => choice.id).toSet();
        _selected.removeWhere((id) => !availableIds.contains(id));
        if (widget.initialEngineId != null && availableIds.contains(widget.initialEngineId)) {
          final builtIn = builtInEngineId('Built-in');
          _selected
            ..clear()
            ..addAll([if (availableIds.contains(builtIn)) builtIn, widget.initialEngineId!]);
        }
        for (final choice in _choices) {
          if (_selected.length >= 2) break;
          _selected.add(choice.id);
        }
        _loading = false;
        if (changedProfile != null) {
          _versionNotice = 'Engine binary changed: ${changedProfile!.displayName}. '
              'A new Quick benchmark is recommended.';
        }
      });
      if (widget.autoStart) {
        await _startBenchmark();
      } else if (changedProfile != null && prefs.getBool(_autoVersionKey) == true) {
        _selected
          ..clear()
          ..add(builtInEngineId('Built-in'))
          ..add(customEngineId(changedProfile));
        _preset = EngineBenchmarkPreset.quick;
        _timeController.text = '100';
        _gamesController.text = '2';
        _progressText = 'A changed custom-engine fingerprint triggered a Quick benchmark.';
        await _startBenchmark();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load benchmark history: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    if (_running) _runner?.stop();
    _runner?.dispose();
    for (final c in [_timeController, _gamesController, _gameCapController, _plyController]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectPreset(EngineBenchmarkPreset preset) {
    setState(() {
      _preset = preset;
      final ms = EngineBenchmarkConfig.defaults[preset];
      if (ms != null) _timeController.text = '$ms';
    });
  }

  Future<void> _startBenchmark() async {
    final config = _config;
    final selectedChoices = _choices.where((choice) => _selected.contains(choice.id)).toList();
    final problems = config.validate(selectedChoices.length);
    if (problems.isNotEmpty) {
      setState(() => _error = problems.join('\n'));
      return;
    }

    _runner?.stop();
    _runner?.dispose();
    await _subscription?.cancel();
    final engines = <ChessEngine>[];
    final identities = <EngineBenchmarkIdentity>[];
    final previousFingerprints = <String, String?>{};
    try {
      for (final choice in selectedChoices) {
        final profile = _profiles.where((p) => customEngineId(p) == choice.id).firstOrNull;
        if (profile != null) {
          previousFingerprints[choice.id] = profile.binaryFingerprint;
          // Explicit user-triggered runs refresh the content hash. Ordinary
          // starts use stat metadata to avoid repeatedly hashing large binaries.
          profile.binaryFingerprintMetadata = null;
        }
        final engine = createEngineForId(choice.id, profiles: _profiles);
        engines.add(engine);
        identities.add(EngineBenchmarkIdentity(
          id: choice.id,
          name: choice.label,
          version: profile == null ? engine.version : 'unknown',
          detectedName: profile?.detectedName,
          author: profile?.detectedAuthor,
          implementation: _implementationFor(choice.id),
          optionsDescription: _profiles
              .where((profile) => customEngineId(profile) == choice.id)
              .map((profile) => safeEngineOptionsDescription(profile.optionOverrides))
              .firstOrNull ?? '',
          binaryFingerprint: profile?.binaryFingerprint,
        ));
      }
    } catch (e) {
      _disposeEngines(engines);
      setState(() => _error = 'A selected engine could not be created; no engine was silently skipped. $e');
      return;
    }

    _expectedGames = config.estimatedGames(engines.length);
    _cancelRequested = false;
    _runCompleted = 0;
    _liveGames = [];
    _error = null;
    _progressText = 'Initializing ${engines.length} engines';
    setState(() => _running = true);

    final ids = identities.map((e) => e.id).toList();
    _runner = TournamentService(
      engines: engines,
      engineIds: ids,
      gamesPerPairing: config.gamesPerPairing,
      depthPerMove: null,
      moveTime: Duration(milliseconds: config.timePerMoveMs),
      plyLimit: config.plyLimit,
    );
    _subscription = _runner!.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case TournamentRoundStart(:final round, :final totalRounds, :final white, :final black):
          setState(() => _progressText = 'Game $round of $totalRounds · $white vs $black');
        case MatchGameFinished(:final result):
          setState(() {
            _liveGames.add(result);
            _runCompleted = _liveGames.length;
          });
        case MatchFinished():
          break;
        default:
          break;
      }
    });

    final startedAt = DateTime.now().toUtc();
    try {
      final games = await _runner!.run();
      final reportIdentities = identities.map((identity) {
        final profile = _profiles.where((p) => customEngineId(p) == identity.id).firstOrNull;
        return EngineBenchmarkIdentity(
          id: identity.id,
          name: identity.name,
          version: identity.version,
          detectedName: profile?.detectedName ?? identity.detectedName,
          author: profile?.detectedAuthor ?? identity.author,
          implementation: identity.implementation,
          optionsDescription: identity.optionsDescription,
          binaryFingerprint: profile?.binaryFingerprint ?? identity.binaryFingerprint,
        );
      }).toList();
      for (final profile in _profiles.where((p) => _selected.contains(customEngineId(p)))) {
        await _profileStore.update(profile);
      }
      final changedBinaries = reportIdentities.where((identity) {
        final previous = previousFingerprints[identity.id];
        return previous != null && identity.binaryFingerprint != null &&
            previous != identity.binaryFingerprint;
      }).map((identity) => identity.name).toList();
      if (games.isNotEmpty) {
        final run = EngineBenchmarkRun(
          id: '${startedAt.microsecondsSinceEpoch}-${math.Random().nextInt(1 << 30).toRadixString(16)}',
          startedAt: startedAt,
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
          environment: 'device-local; hardware identity not collected',
          config: config,
          engines: reportIdentities,
          games: games,
        );
        await _historyStore.addRun(run);
        if (mounted) setState(() => _history = [..._history, run]);
      }
      if (mounted) {
        setState(() {
          _running = false;
          _progressText = _cancelRequested
              ? games.isEmpty
                  ? 'Stopped before any game completed; no report saved'
                  : 'Stopped; partial results saved'
              : changedBinaries.isEmpty
                  ? 'Benchmark finished'
                  : 'Binary fingerprint changed: ${changedBinaries.join(', ')}; this run records the new build';
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _running = false;
        _error = 'Benchmark failed: $e';
      });
    } finally {
      _disposeEngines(engines);
    }
  }

  void _disposeEngines(List<ChessEngine> engines) {
    for (final engine in engines) {
      try {
        engine.dispose();
      } catch (e) {
        debugPrint('[EngineLab] dispose failed for ${engine.name}: $e');
      }
    }
  }

  void _cancel() {
    _cancelRequested = true;
    _runner?.stop();
    setState(() => _progressText = 'Cancelling after the current search…');
  }

  Future<void> _importJson() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Import benchmark JSON'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            minLines: 8,
            maxLines: 16,
            decoration: const InputDecoration(
              hintText: 'Paste a report or exported report collection',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Validate and import')),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.trim().isEmpty) return;
    try {
      final count = await _historyStore.importJson(input);
      final history = await _historyStore.load();
      if (mounted) setState(() => _history = history);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported $count report(s); existing reports were preserved.')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Import rejected; no history was changed. $e');
    }
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  List<PlayerRating> _ratingsFor(List<GameResult> games) => fitRatings([
        for (final game in games)
          if (game.eligibleForRating)
            (white: game.whiteId, black: game.blackId, score: game.whiteScore),
      ]);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final liveRatings = _ratingsFor(_liveGames);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Engine Lab'),
        actions: [
          IconButton(
            tooltip: 'Import benchmark JSON',
            onPressed: _importJson,
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: 'Copy rating history as CSV',
            onPressed: _history.isEmpty ? null : () => _copy(EngineBenchmarkRun.toCsv(_history), 'CSV'),
            icon: const Icon(Icons.table_chart_outlined),
          ),
          IconButton(
            tooltip: 'Copy benchmark history as JSON',
            onPressed: _history.isEmpty ? null : () async => _copy(await _historyStore.exportJson(), 'JSON'),
            icon: const Icon(Icons.data_object),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final content = <Widget>[
                _dashboard(theme),
                const SizedBox(height: 16),
                _benchmarkBuilder(theme),
                if (_versionNotice != null) ...[
                  const SizedBox(height: 12),
                  Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      const Icon(Icons.system_update_alt),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_versionNotice!)),
                    ]),
                  )),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Card(color: theme.colorScheme.errorContainer, child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  )),
                ],
                if (_running || _liveGames.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _currentReport(theme, liveRatings),
                ],
                const SizedBox(height: 16),
                _historyView(theme),
              ];
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16, vertical: 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: wide
                        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content)
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: content),
                  ),
                ),
              );
            }),
    );
  }

  Widget _dashboard(ThemeData theme) {
    final latestGames = _history.fold<int>(0, (n, run) => n + run.completedGames);
    final latestForfeits = _history.fold<int>(0, (n, run) => n + run.forfeits);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metricCard(theme, Icons.analytics_outlined, 'Saved reports', '${_history.length}'),
        _metricCard(theme, Icons.sports_score, 'Rated games', '$latestGames'),
        _metricCard(theme, Icons.health_and_safety_outlined, 'Engine forfeits', '$latestForfeits'),
        _metricCard(theme, Icons.public, 'Calibrated Elo', 'Unavailable'),
      ],
    );
  }

  Widget _metricCard(ThemeData theme, IconData icon, String title, String value) =>
      SizedBox(
        width: 220,
        child: Card(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: theme.textTheme.labelMedium),
              Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            ])),
          ]),
        )),
      );

  Widget _benchmarkBuilder(ThemeData theme) {
    final estimate = _config.estimatedGames(_selected.length);
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Benchmark setup', style: theme.textTheme.titleLarge),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final preset in EngineBenchmarkPreset.values)
            ChoiceChip(
              label: Text(switch (preset) {
                EngineBenchmarkPreset.quick => 'Quick · 100 ms',
                EngineBenchmarkPreset.standard => 'Standard · 300 ms',
                EngineBenchmarkPreset.accurate => 'Accurate · 1,000 ms',
                EngineBenchmarkPreset.custom => 'Custom',
              }),
              selected: _preset == preset,
              onSelected: _running ? null : (_) => _selectPreset(preset),
            ),
        ]),
        const SizedBox(height: 8),
        Text('Select engines (${_selected.length} selected)', style: theme.textTheme.titleMedium),
        Wrap(spacing: 8, runSpacing: 4, children: [
          TextButton.icon(
            onPressed: _running ? null : () => setState(() => _selected.addAll(_choices.map((e) => e.id))),
            icon: const Icon(Icons.select_all), label: const Text('Select all available choices'),
          ),
          TextButton(onPressed: _running ? null : () => setState(_selected.clear), child: const Text('Clear')),
          for (final choice in _choices)
            FilterChip(
              label: Text(choice.label),
              selected: _selected.contains(choice.id),
              onSelected: _running ? null : (selected) => setState(() {
                selected ? _selected.add(choice.id) : _selected.remove(choice.id);
              }),
            ),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 12, runSpacing: 8, children: [
          _numberField('Time / move (ms)', _timeController, 72),
          _numberField('Games / pairing (even)', _gamesController, 72),
          _numberField('Maximum games', _gameCapController, 72),
          _numberField('Ply limit', _plyController, 72),
        ]),
        const SizedBox(height: 10),
        Text('Estimated workload: $estimate games · ${_config.timePerMoveMs} ms per move. '
            'Accurate runs can take a long time and use substantial battery.',
          style: theme.textTheme.bodyMedium),
        const SizedBox(height: 6),
        Text('Relative Elo is fitted only within connected engine groups and centred at 1500. '
            'Calibrated Elo is unavailable without an environment-matched published reference. '
            'This runner uses the standard start position and each custom profile’s saved options; opening suites, option sweeps, warm-ups '
            'and adaptive stops are not yet implemented. Opt-in custom-binary change detection runs when Engine Lab opens; '
            'built-in version changes are not detected. Web can run browser-compatible engines only; custom executables are unavailable there.',
          style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        Row(children: [
          if (_running)
            OutlinedButton.icon(onPressed: _cancel, icon: const Icon(Icons.stop), label: const Text('Cancel'))
          else
            FilledButton.icon(onPressed: _startBenchmark, icon: const Icon(Icons.play_arrow), label: const Text('Benchmark Now')),
          const SizedBox(width: 12),
          if (_selected.length < 2) const Text('Select at least two engines to compare.'),
        ]),
        if (_running) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _expectedGames == 0
              ? null
              : (_runCompleted / _expectedGames).clamp(0.0, 1.0).toDouble()),
          const SizedBox(height: 6),
          Text('$_progressText · $_runCompleted / $_expectedGames game records'),
        ],
      ]),
    ));
  }

  Widget _numberField(String label, TextEditingController controller, double width) =>
      SizedBox(width: width + 100, child: TextField(
        controller: controller,
        enabled: !_running,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {
          if (_preset != EngineBenchmarkPreset.custom) _preset = EngineBenchmarkPreset.custom;
        }),
        decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      ));

  EngineLatencyStats _latencyFor(String engineId, List<GameResult> games) => EngineLatencyStats([
        for (final game in games) ...[
          if (game.whiteId == engineId) ...game.whiteMoveMillis,
          if (game.blackId == engineId) ...game.blackMoveMillis,
        ],
      ]);

  Widget _currentReport(ThemeData theme, List<PlayerRating> ratings) {
    return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_running ? 'Live benchmark' : 'Latest run', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            if (ratings.isEmpty)
              const Text('No eligible completed games yet. Forfeits and cancelled games are excluded from ratings.'),
            if (ratings.map((rating) => rating.component).toSet().length > 1)
              Text('Disconnected engine groups: each group is centered independently at 1500 and must not be compared across groups.',
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.w600)),

            for (final rating in ratings) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_labelFor(rating.name)),
                subtitle: Text('${rating.wins} wins · ${rating.draws} draws · ${rating.losses} losses · '
                    '${rating.games} rated games · ${(rating.score * 100).toStringAsFixed(1)}% score · ${rating.sampleQuality} sample · '
                    '${_latencyFor(rating.name, _liveGames).medianMs ?? '—'} / ${_latencyFor(rating.name, _liveGames).p95Ms ?? '—'} / ${_latencyFor(rating.name, _liveGames).p99Ms ?? '—'} ms median / p95 / p99'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${rating.rating.round()} Rel. Elo', style: theme.textTheme.titleMedium),
                  Text(rating.stdErr.isFinite
                      ? '±${(1.96 * rating.stdErr).round()} (95%)'
                      : 'uncertainty unavailable', style: theme.textTheme.bodySmall),
                ]),
              ),
            ],
            Text('Forfeits: ${_liveGames.where((g) => g.status == GameResultStatus.forfeit).length} · '
                'Aborted: ${_liveGames.where((g) => g.status == GameResultStatus.aborted).length} · '
                'Cancelled: ${_liveGames.where((g) => g.status == GameResultStatus.cancelled).length}',
              style: theme.textTheme.bodySmall),
          ]),
        ),
      );
  }

  Widget _historyView(ThemeData theme) {
    final allRows = <({EngineBenchmarkRun run, PlayerRating rating})>[
      for (final run in _history)
        for (final rating in run.ratings) (run: run, rating: rating),
    ];
    return Card(child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rating history & reports', style: theme.textTheme.titleLarge),
        if (_history.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No saved benchmarks yet. Run a benchmark to build your local leaderboard.')),
          )
        else ...[
          const SizedBox(height: 8),
          for (final run in _history.reversed) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('${run.startedAt.toLocal()} · ${run.config.preset.name} · ${run.platform}'),
              subtitle: Text('${run.completedGames} rated games · ${run.forfeits} forfeits · '
                  '${run.abortedGames} aborted · ${run.cancelledGames} cancelled · '
                  '${run.config.timePerMoveMs} ms/move · ${run.engines.length} engines'),
              children: [
                for (final rating in run.ratings)
                  ListTile(
                    dense: true,
                    title: Text(_labelInRun(run, rating.name)),
                    subtitle: Text('${rating.wins}/${rating.draws}/${rating.losses} · ${rating.games} games · '
                        '${rating.stdErr.isFinite ? '95% CI ${rating.ci95Low.round()}–${rating.ci95High.round()}' : 'CI unavailable'} · '
                        'median ${run.latencyByEngine[rating.name]?.medianMs ?? '—'} / p95 ${run.latencyByEngine[rating.name]?.p95Ms ?? '—'} / p99 ${run.latencyByEngine[rating.name]?.p99Ms ?? '—'} ms'),
                    trailing: Text(rating.hasUsableEstimate ? '${rating.rating.round()}' : 'insufficient',
                      style: theme.textTheme.titleMedium),
                  ),
                for (final game in run.games.where((game) => game.failureReason != null))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber_rounded),
                    title: Text('${_labelInRun(run, game.whiteId)} vs ${_labelInRun(run, game.blackId)} · ${game.status.name}'),
                    subtitle: Text(game.failureReason!),
                  ),
                TextButton.icon(
                  onPressed: () => _copy(run.games.map((g) => g.pgn).where((pgn) => pgn.isNotEmpty).join('\n\n'), 'PGN'),
                  icon: const Icon(Icons.copy), label: const Text('Copy PGN'),
                ),
                TextButton.icon(
                  onPressed: () => _copy(run.toJsonText(), 'Report JSON'),
                  icon: const Icon(Icons.data_object), label: const Text('Copy report JSON'),
                ),
              ],
            ),
          ],
          const Divider(),
          Text('Leaderboard (runs are not pooled across different platforms, time budgets or engine implementations)',
              style: theme.textTheme.bodySmall),
          for (final row in allRows.take(30))
            ListTile(
              dense: true,
              title: Text(_labelInRun(row.run, row.rating.name)),
              subtitle: Text('${row.run.platform} · ${row.run.config.timePerMoveMs} ms · ${row.rating.games} games'),
              trailing: Text(row.rating.hasUsableEstimate ? '${row.rating.rating.round()}' : '—'),
            ),
        ],
      ]),
    ));
  }

  String _implementationFor(String id) {
    if (isCustomEngineId(id)) return 'custom-uci process (${defaultTargetPlatform.name})';
    return switch (builtInNameFromId(id)) {
      'Frozenight' => kIsWeb ? 'Frozenight WASM' : 'Frozenight native FFI',
      'Stockfish' => kIsWeb ? 'Stockfish JavaScript/WASM' : 'Stockfish native/downloadable',
      'Lynx' => kIsWeb ? 'Lynx .NET WASM' : 'Lynx native',
      'Lc0' => kIsWeb ? 'Lc0 browser backend' : 'Lc0 native/Dart backend',
      'Maia3 Dart' => 'Maia3 Dart/ONNX ${kIsWeb ? 'Web' : 'native'}',
      _ => 'Dart/runtime ${defaultTargetPlatform.name}',
    };
  }

  String _labelFor(String id) => _choices.where((choice) => choice.id == id).map((choice) => choice.label).firstOrNull ?? id;
  String _labelInRun(EngineBenchmarkRun run, String id) =>
      run.engines.where((engine) => engine.id == id).map((engine) => engine.name).firstOrNull ?? id;
}
