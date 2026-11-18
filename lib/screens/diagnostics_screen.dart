import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diagnostics/app_logger.dart';
import '../diagnostics/diag_log_record.dart';
import '../diagnostics/diagnostic_export.dart';
import '../diagnostics/redaction.dart';
import '../diagnostics/resource_sampler.dart';

/// In-app Diagnostics & Logs (dev6).
///
/// Reached from Settings → "Diagnostics & Logs" and from the Engine Manager's
/// error surfaces. Shows the structured log with level/component/text
/// filters, live resource snapshots while open, and an export workflow whose
/// bundle passes privacy redaction and is only saved where the user chooses.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final AppLogger _logger = AppLogger.instance;
  final ResourceSampler _sampler =
      ResourceSampler();
  final TextEditingController _query = TextEditingController();

  DiagLevel _minFilter = DiagLevel.trace;
  String? _componentFilter;
  List<DiagLogRecord> _persisted = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _sampler.start();
    _logger.updates.listen((_) {
      if (mounted) setState(() {});
    });
    _logger.info('ui.diagnostics', 'viewer.opened');
  }

  @override
  void dispose() {
    _sampler.stop();
    _query.dispose();
    _logger.info('ui.diagnostics', 'viewer.closed');
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final persisted = await _logger.loadPersisted(maxLines: 5000);
      if (!mounted) return;
      setState(() {
        _persisted = persisted;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not read the persisted logs: $error')));
    }
  }

  /// Persisted entries first, then the live buffer's newest additions; the
  /// merge is by identity, and duplicates from the last flush window are
  /// shown once.
  List<DiagLogRecord> get _all {
    final live = _logger.records;
    if (_persisted.isEmpty) return live;
    final merged = [..._persisted];
    for (final record in live) {
      final known = merged.any((entry) =>
          entry.timestamp == record.timestamp &&
          entry.correlationId == record.correlationId);
      if (!known) merged.add(record);
    }
    merged.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  List<DiagLogRecord> get _visible {
    final all = _all;
    final query = _query.text.trim().toLowerCase();
    return [
      for (final record in all)
        if (record.level.index >= _minFilter.index)
          if (_componentFilter == null ||
              record.component == _componentFilter)
            if (query.isEmpty ||
                record.event.toLowerCase().contains(query) ||
                (record.message ?? '').toLowerCase().contains(query) ||
                (record.error ?? '').toLowerCase().contains(query))
              record,
    ];
  }

  Color _levelColor(DiagLevel level) {
    switch (level) {
      case DiagLevel.trace:
      case DiagLevel.debug:
        return Colors.blueGrey;
      case DiagLevel.info:
        return Colors.blue;
      case DiagLevel.warning:
        return Colors.orange;
      case DiagLevel.error:
        return Colors.red;
      case DiagLevel.fatal:
        return Colors.deepPurple;
    }
  }

  void _copyVisible() {
    final text = [
      for (final record in _visible.reversed) record.toLine(),
    ].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_visible.length} entries copied')));
  }

  Future<void> _exportReport() async {
    _logger.info('ui.diagnostics', 'export.started');
    final messenger = ScaffoldMessenger.of(context);
    try {
      final builder =
          DiagnosticReportBuilder(logger: _logger, sampler: _sampler);
      final result = await builder.build();
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Export diagnostic report'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This bundle will be saved where you choose. '
                    'Nothing is uploaded. All text passed privacy redaction:'),
                const SizedBox(height: 8),
                for (final file in result.preview.files)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.description, size: 18),
                    title: Text(file.name, style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${file.lines} lines · ${(file.bytes / 1024).toStringAsFixed(1)} kB',
                        style: const TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save…'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final saved = await FilePicker.saveFile(
        fileName: 'diagnostic-report.zip',
        bytes: result.zip,
        mimeType: 'application/zip',
        dialogTitle: 'Save diagnostic report',
      );
      _logger.info('ui.diagnostics', 'export.finished',
          message: saved?.toString());
      messenger.showSnackBar(const SnackBar(
          content: Text('Diagnostic report saved')));
    } catch (error) {
      _logger.error('ui.diagnostics', 'export.failed', error: error);
      messenger.showSnackBar(SnackBar(
          content: Text('Export failed: $error'),
          backgroundColor: Colors.red));
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear local logs?'),
        content: const Text('The persisted log files on this device are '
            'deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed == true) {
      await _logger.clearPersisted();
      await _refresh();
      _logger.info('ui.diagnostics', 'logs.cleared');
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final components = [
      for (final record in _all) record.component,
    ]..sort();
    final latest = _sampler.samples.isEmpty ? null : _sampler.samples.last;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics & Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: () {
              setState(() => _loading = true);
              _refresh();
            },
          ),
          IconButton(
            icon: const Icon(Icons.content_copy),
            tooltip: 'Copy visible',
            onPressed: visible.isEmpty ? null : _copyVisible,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export report',
            onPressed: _exportReport,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: _clearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          _resourceHeader(latest),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: Row(
              children: [
                DropdownButton<DiagLevel>(
                  value: _minFilter,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final level in DiagLevel.values)
                      DropdownMenuItem(
                          value: level, child: Text(level.label)),
                  ],
                  onChanged: (level) =>
                      setState(() => _minFilter = level ?? DiagLevel.trace),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _componentFilter,
                  underline: const SizedBox.shrink(),
                  hint: const Text('Component'),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All components')),
                    ...{
                      for (final component in components) component,
                    }.map((component) => DropdownMenuItem(
                        value: component, child: Text(component))),
                  ],
                  onChanged: (component) =>
                      setState(() => _componentFilter = component),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Search logs',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : visible.isEmpty
                    ? const Center(
                        child: Text('No log entries match the current filters'))
                    : ListView.builder(
                        itemCount: visible.length,
                        // Newest last in the log order; the user reads the
                        // most recent entries fastest at the bottom.
                        itemBuilder: (context, index) {
                          final record = visible[index];
                          return ListTile(
                            dense: true,
                            leading: Chip(
                              label: Text(record.level.label,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                              backgroundColor: _levelColor(record.level),
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                            ),
                            title: Text('${record.component}.${record.event}',
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                              [
                                if (record.message != null) record.message!,
                                if (record.error != null) record.error!,
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              _timeOnly(record.timestamp),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => _showRecord(record),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _resourceHeader(ResourceSample? latest) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _stat('Session', _logger.sessionId),
                  _stat(
                      'Memory',
                      latest == null
                          ? '—'
                          : '${(latest.rssBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
                  _stat('Engine processes',
                      '${latest?.engineProcessCount ?? 0}'),
                  _stat('Probes', '${latest?.probeCount ?? 0}'),
                  _stat('Benchmarks', '${latest?.benchmarkCount ?? 0}'),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sampling',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                Switch(
                  value: _sampler.isRunning,
                  onChanged: (value) {
                    setState(() {
                      if (value) {
                        _sampler.start();
                      } else {
                        _sampler.stop();
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 13)),
      ],
    );
  }

  String _timeOnly(DateTime timestamp) {
    final local = timestamp.toLocal();
    final two = (int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  void _showRecord(DiagLogRecord record) {
    final pretty = const JsonEncoder.withIndent('  ').convert(record.toJson());
    final sanitized = redactText(record.toLine());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${record.component}.${record.event}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Level: ${record.level.label} · '
                    '${record.timestamp.toLocal().toIso8601String()}'),
                if (record.profileId != null)
                  Text('Profile: ${record.profileId}'),
                if (record.durationMs != null)
                  Text('Duration: ${record.durationMs} ms'),
                const SizedBox(height: 8),
                SelectableText(pretty, style: const TextStyle(fontSize: 12)),
                if (record.stackTrace != null) ...[
                  const SizedBox(height: 8),
                  const Text('Stack trace',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  SelectableText(record.stackTrace!,
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace')),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sanitized));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Entry copied')));
            },
            child: const Text('Copy'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close')),
        ],
      ),
    );
  }
}
