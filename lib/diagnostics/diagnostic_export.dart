/// Builds the shareable `diagnostic-report.zip`.
///
/// Every text in the bundle passes through export-time redaction first: the
/// user can preview the files, but nothing that leaves the device carries a
/// username-shaped path, a token, a password or an email (dev6). Nothing is
/// uploaded by this class — the zip is handed back so the app can show a
/// save/share dialog that the user controls.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../bench/benchmark_fingerprint.dart' show hostSummary;
import 'app_logger.dart';
import 'diag_log_record.dart';
import 'redaction.dart';
import 'resource_sampler.dart';

/// Components whose events describe engine and background-task lifecycle.
const _lifecycleComponents = {'engine', 'benchmark', 'app', 'ui.engineManager'};

/// One file inside the report, for the user-facing preview.
class DiagnosticPreviewFile {
  final String name;
  final int bytes;
  final int lines;

  const DiagnosticPreviewFile({
    required this.name,
    required this.bytes,
    required this.lines,
  });
}

/// What would be shared: the files and their sizes, before any dialog.
class DiagnosticPreview {
  final List<DiagnosticPreviewFile> files;
  final int totalBytes;

  const DiagnosticPreview({required this.files, required this.totalBytes});
}

/// One exported log line: structured fields pass field-aware redaction
/// first (a `password` field with several words would otherwise leak the
/// words after the first one through the text-only pass), then the whole
/// line goes through text redaction. Used for `application.log` and for the
/// viewer's copy action, which have the same ordering requirement.
String redactedRecordLine(DiagLogRecord record) {
  final safe = DiagLogRecord(
    timestamp: record.timestamp,
    level: record.level,
    component: record.component,
    event: record.event,
    message: record.message,
    sessionId: record.sessionId,
    correlationId: record.correlationId,
    profileId: record.profileId,
    durationMs: record.durationMs,
    error: record.error,
    stackTrace: record.stackTrace,
    fields: redactFields(record.fields),
  );
  return redactText(safe.toLine());
}

/// Assembles and encodes the diagnostic bundle.
class DiagnosticReportBuilder {
  final AppLogger logger;
  final ResourceSampler? sampler;

  DiagnosticReportBuilder({required this.logger, this.sampler});

  /// Builds the zip. Returns its bytes and the preview shown to the user
  /// before sharing. Throws only when the platform cannot produce a bundle
  /// at all; every individual file is best-effort.
  Future<({Uint8List zip, DiagnosticPreview preview})> build() async {
    final files = <String, Uint8List>{};

    final persisted = await logger.loadPersisted(maxLines: 5000);
    final all = <DiagLogRecord>[...persisted];
    // In-memory records that are not yet on disk (last flush window).
    for (final record in logger.records) {
      if (!all.any((entry) =>
          entry.timestamp == record.timestamp &&
          entry.correlationId == record.correlationId)) {
        all.add(record);
      }
    }
    all.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final applicationLog = StringBuffer();
    for (final record in all) {
      applicationLog.writeln(redactedRecordLine(record));
    }
    files['application.log'] = _bytes(applicationLog.toString());

    final errors = <Map<String, dynamic>>[
      for (final record in all)
        if (record.level.index >= DiagLevel.error.index)
          redactRecordJson(record.toJson()),
    ];
    files['errors.json'] = _bytes(jsonEncode(errors));

    final lifecycle = <Map<String, dynamic>>[
      for (final record in all)
        if (_lifecycleComponents.contains(record.component))
          redactRecordJson(record.toJson()),
    ];
    files['lifecycle.json'] = _bytes(jsonEncode(lifecycle));

    if (sampler != null && sampler!.samples.isNotEmpty) {
      files['performance.csv'] = _bytes(sampler!.toCsv());
    }

    final metadata = await _metadata();
    files['metadata.json'] = _bytes(jsonEncode(metadata));

    // The summary interpolates values straight out of log records (the
    // latest error and its message), so it passes the same redaction pass as
    // everything else in the bundle — a personal path inside an error string
    // must not survive into the one file users read first.
    final summary = _summary(all, metadata);
    files['summary.md'] = _bytes(redactText(summary));

    final archive = Archive();
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    final encoded = ZipEncoder().encode(archive);

    final preview = DiagnosticPreview(
      files: [
        for (final entry in files.entries)
          DiagnosticPreviewFile(
            name: entry.key,
            bytes: entry.value.length,
            lines: _lineCount(entry.value),
          ),
      ],
      totalBytes: encoded.length,
    );
    return (zip: Uint8List.fromList(encoded), preview: preview);
  }

  Future<Map<String, dynamic>> _metadata() async {
    String version = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // In a widget test there is no platform channel; the report says so.
      version = 'unknown (package info unavailable)';
    }
    return {
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'application': 'CrispChess',
      'version': version,
      'platform': kIsWeb ? 'web' : hostSummary(),
      'diagnosticsSessionId': logger.sessionId,
      if (sampler != null) 'resources': sampler!.summaryJson(),
      'privacy':
          'Text in this bundle passed export-time redaction: usernames in '
              'paths, tokens, passwords and emails are replaced. Local log '
              'files on this device are not redacted; only exports are.',
    };
  }

  /// The human-readable header the bug-report workflow copies.
  String _summary(List<DiagLogRecord> all, Map<String, dynamic> metadata) {
    final errorCount = all
        .where((record) => record.level.index >= DiagLevel.error.index)
        .length;
    final warningCount = all
        .where((record) => record.level == DiagLevel.warning)
        .length;
    final latestError = all
        .where((record) => record.level.index >= DiagLevel.error.index)
        .fold<DiagLogRecord?>(null, (latest, record) => record);
    final buffer = StringBuffer()
      ..writeln('# CrispChess diagnostic report')
      ..writeln()
      ..writeln('- Version: ${metadata['version']}')
      ..writeln('- Platform: ${metadata['platform']}')
      ..writeln('- Session: ${metadata['diagnosticsSessionId']}')
      ..writeln('- Generated: ${metadata['generatedAt']}')
      ..writeln('- Records: ${all.length} ($errorCount errors, '
          '$warningCount warnings)');
    if (latestError != null) {
      buffer
        ..writeln('- Latest error: `${latestError.component}.'
            '${latestError.event}`')
        ..writeln(
            '  at ${latestError.timestamp.toIso8601String()}'
            '${latestError.error != null ? ' — ${latestError.error}' : ''}');
    }
    if (sampler != null) {
      buffer.writeln('- Engine processes alive now: '
          '${sampler!.samples.isEmpty ? 0 : sampler!.samples.last.engineProcessCount}');
    }
    buffer
      ..writeln()
      ..writeln('## Files')
      ..writeln()
      ..writeln('| File | Purpose |')
      ..writeln('|---|---|')
      ..writeln('| metadata.json | app/platform/session facts |')
      ..writeln('| application.log | all structured log entries |')
      ..writeln('| errors.json | entries of level ERROR and above |')
      ..writeln('| lifecycle.json | engine, benchmark and screen lifecycle |')
      ..writeln('| performance.csv | resource samples of this session |')
      ..writeln()
      ..writeln(_privacyNote());
    return buffer.toString();
  }

  String _privacyNote() =>
      'Sharing is manual: the app writes this bundle where the user chooses '
      'and never uploads anything by itself. All text has passed export-time '
      'redaction.';

  Map<String, dynamic> redactRecordJson(Map<String, dynamic> json) {
    final redacted = <String, dynamic>{
      for (final entry in json.entries)
        entry.key: entry.value is String
            ? redactText(entry.value as String)
            : entry.value,
    };
    if (redacted['fields'] is Map) {
      redacted['fields'] = redactFields(
          Map<String, String>.from(redacted['fields'] as Map));
    }
    return redacted;
  }

  Uint8List _bytes(String text) => Uint8List.fromList(utf8.encode(text));

  int _lineCount(Uint8List bytes) {
    var count = 0;
    for (final byte in bytes) {
      if (byte == 10) count++;
    }
    return count == 0 && bytes.isNotEmpty ? 1 : count;
  }
}
