/// Engine Preflight: the step between choosing engines and starting a
/// benchmark.
///
/// Every selected engine is started, asked for one move and shut down, and
/// the outcome is shown per engine and per step — with the structured
/// diagnostic (stage, failure kind, cause, exit code, stderr tail) behind an
/// expandable section and a "copy diagnostics" action. Engines that did not
/// pass are listed, never dropped; the run continues with the passed engines
/// only after the user has explicitly reviewed the results. Nothing is
/// downloaded without asking first.
///
/// The logic lives in `lib/bench/engine_preflight.dart`; this file asks and
/// renders.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../bench/benchmark_config.dart';
import '../bench/benchmark_service.dart';
import '../bench/engine_preflight.dart';
import '../engines/engine_initialization.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/engine_lab/lab_widgets.dart';

class EnginePreflightScreen extends StatefulWidget {
  final BenchmarkService service;
  final List<String> engineIds;
  final Map<String, String> labels;
  final BenchmarkConfig config;

  /// When false the screen only checks (no "continue" action).
  final bool allowContinue;

  const EnginePreflightScreen({
    super.key,
    required this.service,
    required this.engineIds,
    required this.labels,
    required this.config,
    this.allowContinue = true,
  });

  /// Opens the screen; returns the engine ids to run with, or null.
  static Future<List<String>?> open(
    BuildContext context, {
    required BenchmarkService service,
    required List<String> engineIds,
    required Map<String, String> labels,
    required BenchmarkConfig config,
    bool allowContinue = true,
  }) =>
      Navigator.of(context).push<List<String>>(MaterialPageRoute(
        builder: (_) => EnginePreflightScreen(
          service: service,
          engineIds: engineIds,
          labels: labels,
          config: config,
          allowContinue: allowContinue,
        ),
      ));

  @override
  State<EnginePreflightScreen> createState() => _EnginePreflightScreenState();
}

class _EnginePreflightScreenState extends State<EnginePreflightScreen> {
  final Map<String, EnginePreflightResult> _results = {};
  final Map<String, List<PreflightStepResult>> _live = {};
  final Map<String, String> _stale = {};
  PreflightAdmission? _admission;
  String? _current;
  bool _running = false;
  bool _reviewed = false;
  PreflightCancellation? _cancellation;

  PreflightGate get _gate => widget.service.preflightGate;

  @override
  void initState() {
    super.initState();
    for (final id in widget.engineIds) {
      final previous = _gate.results[id];
      if (previous != null) _results[id] = previous;
    }
    _refreshAdmission().then((_) {
      // Check whatever has no current result; keep results that still match.
      final pending = [
        for (final id in widget.engineIds)
          if (_admission?.admitted.contains(id) != true &&
              _results[id]?.status != PreflightStatus.warning)
            id
      ];
      if (pending.isNotEmpty) _check(pending);
    });
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _refreshAdmission() async {
    final admission =
        await widget.service.preflightAdmission(widget.engineIds, widget.config);
    final stale = <String, String>{};
    for (final entry in admission.excluded.entries) {
      if (entry.value.startsWith('result is out of date')) {
        stale[entry.key] = entry.value;
      }
    }
    if (!mounted) return;
    setState(() {
      _admission = admission;
      _stale
        ..clear()
        ..addAll(stale);
    });
  }

  Future<void> _check(List<String> engineIds) async {
    if (_running) return;
    final cancellation = PreflightCancellation();
    setState(() {
      _running = true;
      _reviewed = false;
      _cancellation = cancellation;
      for (final id in engineIds) {
        _results.remove(id);
        _live[id] = [];
      }
    });
    try {
      await widget.service.preflight(
        engineIds: engineIds,
        config: widget.config,
        consent: _askDownload,
        cancellation: cancellation,
        onEngineStarted: (id) {
          if (mounted) setState(() => _current = id);
        },
        onStep: (id, step) {
          if (mounted) setState(() => (_live[id] ??= []).add(step));
        },
        onResult: (result) {
          if (mounted) setState(() => _results[result.engineId] = result);
        },
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(redactPersonalPaths('$error')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
          _current = null;
          _cancellation = null;
        });
        await _refreshAdmission();
      }
    }
  }

  Future<bool> _askDownload(
      String label, EngineDownloadRequirement requirement) async {
    if (!mounted) return false;
    final l = AppLocalizations.of(context);
    final allowed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('${l?.enginePreflightDownloadTitle ?? 'Download required'}'
            ' — $label'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l?.enginePreflightDownloadBody ??
                  'This engine needs to download a file before it can start. '
                      'Nothing is downloaded without your approval.'),
              const SizedBox(height: 8),
              Text(requirement.description,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              LabInfoRow(
                  label: l?.enginePreflightSource ?? 'Source',
                  value: requirement.source.toString()),
              if (requirement.license != null)
                LabInfoRow(
                    label: l?.enginePreflightLicense ?? 'License',
                    value: requirement.license!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l?.enginePreflightDownloadDeny ?? 'Skip this engine'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l?.enginePreflightDownloadAllow ?? 'Download'),
          ),
        ],
      ),
    );
    return allowed == true;
  }

  Future<void> _copy(EnginePreflightResult result) async {
    await Clipboard.setData(ClipboardData(text: result.toDiagnosticText()));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${l?.enginePreflightDiagnostics ?? 'Diagnostics'} '
          '${l?.copied ?? 'copied'}.'),
    ));
  }

  String _label(String id) =>
      _results[id]?.label ?? widget.labels[id] ?? id;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final admission = _admission;
    final admitted = admission?.admitted ?? const <String>[];
    final excluded = admission?.excluded ?? const <String, String>{};
    final enough = admitted.length >= 2;
    final needsReview = excluded.isNotEmpty;
    final canContinue = widget.allowContinue &&
        !_running &&
        admission != null &&
        enough &&
        (!needsReview || _reviewed);
    return Scaffold(
      appBar: AppBar(
        title: Text(l?.enginePreflight ?? 'Engine Preflight'),
        actions: [
          if (_running)
            TextButton.icon(
              onPressed: () => _cancellation?.cancel(),
              icon: const Icon(Icons.stop),
              label: Text(l?.enginePreflightCancel ?? 'Stop checking'),
            )
          else
            IconButton(
              tooltip: l?.enginePreflightRun ?? 'Check engines',
              onPressed: () => _check(widget.engineIds),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l?.enginePreflightSubtitle ??
                'Each engine is started, asked for a move and shut down '
                    'before the benchmark runs.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text('${admitted.length} / ${widget.engineIds.length} '
              '${l?.enginePreflightPassedCount ?? 'admitted'}'),
          if (_running) const LinearProgressIndicator(),
          for (final id in widget.engineIds) _engineCard(l, id, excluded[id]),
        ],
      ),
      bottomNavigationBar: widget.allowContinue
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_running && admission != null && !enough)
                      Text(
                        l?.enginePreflightNeedTwo ??
                            'At least two engines must pass to run a '
                                'benchmark.',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    if (needsReview && enough)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: _reviewed,
                        onChanged: _running
                            ? null
                            : (value) =>
                                setState(() => _reviewed = value == true),
                        title: Text(l?.enginePreflightReviewed ??
                            'I have reviewed the results; engines that did '
                                'not pass are left out of this run.'),
                      ),
                    FilledButton.icon(
                      onPressed: canContinue
                          ? () => Navigator.pop(context, List.of(admitted))
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text('${l?.enginePreflightContinue ?? 'Continue with passed engines'}'
                          ' (${admitted.length})'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _engineCard(AppLocalizations? l, String id, String? exclusion) {
    final theme = Theme.of(context);
    final result = _results[id];
    final running = _current == id;
    final steps = result?.steps ?? _live[id] ?? const <PreflightStepResult>[];
    final status = result?.status;
    final stale = _stale[id];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(_label(id), style: theme.textTheme.titleSmall),
                ),
                if (running)
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  _statusChip(l, status),
              ],
            ),
            if (result?.identity != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${result!.identity!.label} · ${result.identity!.platform}/'
                  '${result.identity!.backend} · '
                  '${result.identity!.fingerprintKind} '
                  '${result.identity!.shortFingerprint}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (stale != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${l?.enginePreflightStale ?? 'Out of date — check again'}'
                    ' ($stale)',
                    style: TextStyle(
                        fontSize: 12, color: theme.colorScheme.error)),
              ),
            if (!running &&
                exclusion != null &&
                stale == null &&
                result != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    '${l?.enginePreflightExcluded ?? 'Left out of this run'}'
                    ': $exclusion',
                    style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final step in steps)
                  Tooltip(
                    message: step.detail ?? '',
                    child: Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: Icon(_statusIcon(step.status),
                          size: 16, color: _statusColor(step.status)),
                      label: Text(_stepLabel(l, step.step),
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ),
              ],
            ),
            if (result != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(l?.enginePreflightDiagnostics ?? 'Diagnostics',
                    style: const TextStyle(fontSize: 13)),
                children: [
                  for (final step in result.steps)
                    if (step.status != PreflightStatus.skipped)
                      LabInfoRow(
                        label:
                            '${_stepLabel(l, step.step)} · ${_statusLabel(l, step.status)}',
                        value: [
                          if (step.detail != null) step.detail!,
                          if (step.millis != null) '${step.millis} ms',
                        ].join(' · '),
                      ),
                  if (result.diagnostic != null)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 6),
                      padding: const EdgeInsets.all(8),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: SelectableText(
                        _diagnosticLines(result.diagnostic!),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                ],
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _running ? null : () => _check([id]),
                  icon: const Icon(Icons.replay, size: 18),
                  label: Text(l?.enginePreflightRetry ?? 'Retry'),
                ),
                if (result != null)
                  TextButton.icon(
                    onPressed: () => _copy(result),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(l?.enginePreflightCopy ?? 'Copy diagnostics'),
                  ),
                if (result?.status == PreflightStatus.warning &&
                    stale == null &&
                    !_gate.warningsAcknowledged(id))
                  TextButton.icon(
                    onPressed: _running
                        ? null
                        : () async {
                            _gate.acknowledgeWarnings(id);
                            await _refreshAdmission();
                          },
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(l?.enginePreflightAcceptWarnings ??
                        'Accept warnings for this engine'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _diagnosticLines(Map<String, dynamic> diagnostic) {
    final out = StringBuffer();
    for (final entry in diagnostic.entries) {
      if (entry.key == 'causeStack' || entry.key == 'redacted') continue;
      final value = entry.value;
      if (value is List) {
        out.writeln('${entry.key}:');
        for (final line in value) {
          out.writeln('  $line');
        }
      } else {
        out.writeln('${entry.key}: $value');
      }
    }
    return out.toString().trimRight();
  }

  Widget _statusChip(AppLocalizations? l, PreflightStatus? status) {
    final shown = status ?? PreflightStatus.skipped;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(_statusIcon(shown), size: 16, color: _statusColor(shown)),
      label: Text(status == null
          ? (l?.enginePreflightStatusPending ?? 'Waiting')
          : _statusLabel(l, status)),
    );
  }

  IconData _statusIcon(PreflightStatus status) => switch (status) {
        PreflightStatus.passed => Icons.check_circle,
        PreflightStatus.warning => Icons.warning_amber,
        PreflightStatus.failed => Icons.error,
        PreflightStatus.unsupported => Icons.block,
        PreflightStatus.notInstalled => Icons.download_for_offline_outlined,
        PreflightStatus.timedOut => Icons.timer_off,
        PreflightStatus.cancelled => Icons.cancel_outlined,
        PreflightStatus.skipped => Icons.radio_button_unchecked,
      };

  Color _statusColor(PreflightStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      PreflightStatus.passed => Colors.green,
      PreflightStatus.warning => Colors.orange,
      PreflightStatus.skipped => scheme.outline,
      PreflightStatus.cancelled || PreflightStatus.unsupported => scheme.outline,
      _ => scheme.error,
    };
  }

  String _statusLabel(AppLocalizations? l, PreflightStatus status) =>
      switch (status) {
        PreflightStatus.passed => l?.enginePreflightStatusPassed ?? 'Passed',
        PreflightStatus.warning => l?.enginePreflightStatusWarning ?? 'Warning',
        PreflightStatus.failed => l?.enginePreflightStatusFailed ?? 'Failed',
        PreflightStatus.unsupported =>
          l?.enginePreflightStatusUnsupported ?? 'Not supported here',
        PreflightStatus.notInstalled =>
          l?.enginePreflightStatusNotInstalled ?? 'Not installed',
        PreflightStatus.timedOut =>
          l?.enginePreflightStatusTimedOut ?? 'Timed out',
        PreflightStatus.cancelled =>
          l?.enginePreflightStatusCancelled ?? 'Cancelled',
        PreflightStatus.skipped => l?.enginePreflightStatusSkipped ?? 'Not run',
      };

  String _stepLabel(AppLocalizations? l, PreflightStep step) => switch (step) {
        PreflightStep.platform => l?.enginePreflightStepPlatform ?? 'Platform',
        PreflightStep.runtime => l?.enginePreflightStepRuntime ?? 'Runtime',
        PreflightStep.initialization =>
          l?.enginePreflightStepInitialization ?? 'Initialization',
        PreflightStep.readiness =>
          l?.enginePreflightStepReadiness ?? 'Readiness',
        PreflightStep.identity => l?.enginePreflightStepIdentity ?? 'Identity',
        PreflightStep.options => l?.enginePreflightStepOptions ?? 'Options',
        PreflightStep.firstSearch =>
          l?.enginePreflightStepFirstSearch ?? 'First search',
        PreflightStep.legalMove =>
          l?.enginePreflightStepLegalMove ?? 'Legal move',
        PreflightStep.cleanup => l?.enginePreflightStepCleanup ?? 'Cleanup',
      };
}
