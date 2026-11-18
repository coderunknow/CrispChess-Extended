import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crispchess/diagnostics/app_logger.dart';
import 'package:crispchess/diagnostics/diag_log_record.dart';
import 'package:crispchess/diagnostics/diag_log_sink_io.dart';
import 'package:crispchess/diagnostics/diagnostic_export.dart';
import 'package:crispchess/diagnostics/redaction.dart';
import 'package:crispchess/diagnostics/resource_sampler.dart';

void main() {
  late Directory temp;
  late AppLogger logger;
  late ResourceSampler sampler;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diag-export-');
    logger = AppLogger(
      sink: DiagLogSink(
          rootOverride: temp,
          flushBatch: 4,
          flushInterval: const Duration(milliseconds: 20)),
    );
    sampler = ResourceSampler();
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
    AppLogger.setInstanceForTesting(null);
  });

  Future<void> seed() async {
    logger.info('engine', 'process.started', profileId: 'p1');
    logger.warning('engine', 'process.slow', message: 'handshake 900ms');
    logger.error('engine', 'initialize.failed',
        profileId: 'p1',
        error: r'binary missing at C:\Users\alice\engine.exe',
        fields: {'path': r'C:\Users\alice\engine.exe'});
    logger.info('benchmark', 'run.started',
        fields: {'trigger': 'automatic', 'password': 'correct horse battery staple'});
    await logger.sink.flush();
    sampler.sample();
    sampler.sample();
  }

  test('the bundle is a valid zip with the documented files', () async {
    await seed();
    final result = await DiagnosticReportBuilder(
            logger: logger, sampler: sampler)
        .build();

    final decoded = ZipDecoder().decodeBytes(result.zip);
    final names = decoded.files.map((f) => f.name).toSet();
    expect(names, containsAll([
      'summary.md',
      'metadata.json',
      'application.log',
      'errors.json',
      'lifecycle.json',
      'performance.csv',
    ]));

    // Every advertised file is intact: the content decodes and matches the
    // preview the user confirms.
    for (final previewFile in result.preview.files) {
      final entry = decoded.files.firstWhere((f) => f.name == previewFile.name);
      expect(entry.size, previewFile.bytes,
          reason: 'preview must describe the real bundle');
    }
    final metadata =
        jsonDecode(utf8.decode(decoded.files.firstWhere((f) => f.name == 'metadata.json').content as List<int>))
            as Map<String, dynamic>;
    expect(metadata['application'], 'CrispChess');
    expect(metadata.keys, contains('platform'));
    expect(metadata.keys, contains('privacy'));
  });

  test('the exported text is redacted while local logs are not', () async {
    await seed();
    final result = await DiagnosticReportBuilder(
            logger: logger, sampler: sampler)
        .build();

    final decoded = ZipDecoder().decodeBytes(result.zip);
    final applicationLog = utf8
        .decode(decoded.files.firstWhere((f) => f.name == 'application.log').content as List<int>);
    // The local record carries the personal path; the bundle must not.
    expect(containsSensitiveText(applicationLog), isFalse);
    expect(applicationLog, isNot(contains(r'C:\Users\alice')));
    expect(applicationLog, isNot(contains('horse battery')),
        reason: 'structured secrets must be redacted before toLine');

    final errorsJson = utf8
        .decode(decoded.files.firstWhere((f) => f.name == 'errors.json').content as List<int>);
    expect(errorsJson, isNot(contains(r'C:\Users\alice')));
    final errors = jsonDecode(errorsJson) as List<dynamic>;
    expect(errors, isNotEmpty);
    expect(
        (errors.first as Map)['event'], 'initialize.failed');

    final lifecycleJson = utf8
        .decode(decoded.files.firstWhere((f) => f.name == 'lifecycle.json').content as List<int>);
    expect(lifecycleJson, contains('process.started'));
    expect(lifecycleJson, contains('run.started'));
  });

  test('summary.md is redacted like the rest of the bundle', () async {
    await seed();
    final result = await DiagnosticReportBuilder(logger: logger).build();
    final decoded = ZipDecoder().decodeBytes(result.zip);
    final summary = utf8.decode(
        decoded.files.firstWhere((f) => f.name == 'summary.md').content as List<int>);
    expect(summary, isNot(contains(r'C:\Users\alice')));
    expect(summary, contains(r'C:\Users\<user>'));
    expect(summary, contains('engine.initialize.failed'));
  });

  test('errors.json holds only ERROR and above', () async {
    await seed();
    final result = await DiagnosticReportBuilder(logger: logger).build();
    final decoded = ZipDecoder().decodeBytes(result.zip);
    final errors = jsonDecode(utf8.decode(
        decoded.files.firstWhere((f) => f.name == 'errors.json').content as List<int>))
        as List<dynamic>;
    expect(errors.length, 1);
    expect((errors.first as Map)['level'], 'ERROR');
  });

  test('performance.csv carries the samples that were taken', () async {
    await seed();
    final result = await DiagnosticReportBuilder(
            logger: logger, sampler: sampler)
        .build();
    final decoded = ZipDecoder().decodeBytes(result.zip);
    final csv = utf8.decode(
        decoded.files.firstWhere((f) => f.name == 'performance.csv').content as List<int>);
    final rows = csv.trim().split('\n');
    expect(rows.first, 'timestamp_utc,rss_bytes,engine_processes,initializations,probes,benchmarks');
    expect(rows.length, 3); // header + two samples
  });

  test('the summary names the latest error', () async {
    await seed();
    final result = await DiagnosticReportBuilder(logger: logger).build();
    final decoded = ZipDecoder().decodeBytes(result.zip);
    final summary = utf8.decode(
        decoded.files.firstWhere((f) => f.name == 'summary.md').content as List<int>);
    expect(summary, contains('engine.initialize.failed'));
    expect(summary, contains('binary missing'));
    expect(summary, contains('1 errors'));
  });

  test('records round-trip through JSON and toLine', () {
    final record = DiagLogRecord(
      timestamp: DateTime(2026, 11, 18, 9, 30),
      level: DiagLevel.error,
      component: 'engine',
      event: 'handshake.failed',
      message: 'no uciok',
      sessionId: 's1',
      correlationId: 7,
      profileId: 'p1',
      durationMs: 1000,
      error: 'TimeoutException',
      stackTrace: '#1 main',
      fields: {'path': '/tmp/e'},
    );
    final restored = DiagLogRecord.fromJson(record.toJson());
    expect(restored.level, DiagLevel.error);
    expect(restored.event, 'handshake.failed');
    expect(restored.profileId, 'p1');
    expect(restored.durationMs, 1000);
    expect(restored.fields['path'], '/tmp/e');
    expect(record.toLine(), contains('[ERROR] engine.handshake.failed'));
    expect(record.toLine(), contains('profile=p1'));
    expect(record.toLine(), contains('1000ms'));
  });
}
