import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:crispchess/diagnostics/app_logger.dart';
import 'package:crispchess/diagnostics/diag_log_record.dart';
import 'package:crispchess/diagnostics/diag_log_sink_io.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('diag-logger-');
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
    AppLogger.setInstanceForTesting(null);
  });

  AppLogger loggerFor({int maxFileBytes = 1024 * 1024, int flushBatch = 4}) =>
      AppLogger(
        sink: DiagLogSink(
          rootOverride: temp,
          maxFileBytes: maxFileBytes,
          flushBatch: flushBatch,
          flushInterval: const Duration(milliseconds: 20),
        ),
      );

  test('levels below the threshold are dropped at no cost', () {
    final logger = loggerFor()..minLevel = DiagLevel.warning;
    expect(logger.trace('test', 'a'), isFalse);
    expect(logger.debug('test', 'b'), isFalse);
    expect(logger.info('test', 'c'), isFalse);
    expect(logger.warning('test', 'd'), isTrue);
    expect(logger.records.map((r) => r.event), ['d']);
  });

  test('the in-memory buffer is bounded', () {
    final logger = loggerFor();
    for (var i = 0; i < 2100; i++) {
      logger.info('test', 'event_$i');
    }
    expect(logger.records.length, AppLogger.instance.bufferLimit);
    // Oldest dropped, newest kept.
    expect(logger.records.first.event, 'event_${2100 - 2000}');
    expect(logger.records.last.event, 'event_2099');
  });

  test('records persist as JSONL and survive a new logger', () async {
    final logger = loggerFor();
    logger.info('engine', 'initialize.started',
        profileId: 'p1', fields: {'path': '/tmp/x'});
    logger.error('engine', 'initialize.failed', error: 'boom');
    await logger.sink.flush();

    final second = loggerFor();
    final persisted = await second.loadPersisted();
    expect(persisted, isNotEmpty);
    expect(
        persisted.any((r) => r.event == 'initialize.started'), isTrue);
    expect(persisted.any((r) => r.event == 'initialize.failed'), isTrue);
    final started =
        persisted.firstWhere((r) => r.event == 'initialize.started');
    expect(started.level, DiagLevel.info);
    expect(started.profileId, 'p1');
    expect(started.fields['path'], '/tmp/x');
  });

  test('the log file rotates at the size cap and keeps bounded generations',
      () async {
    final logger = loggerFor(maxFileBytes: 512);
    // Each record is comfortably over the cap once several accumulate, so a
    // flush rotates.
    for (var i = 0; i < 40; i++) {
      logger.info('rotate', 'line_$i',
          message: 'padding-padding-padding-padding-padding-padding');
    }
    // The batched flushes are unawaited by design; give them time to settle,
    // then flush whatever is left.
    final first = File('${temp.path}/app.log.1');
    for (var i = 0; i < 50 && !await first.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await logger.sink.flush();

    final thirdGen = File('${temp.path}/app.log.3');
    expect(await first.exists(), isTrue,
        reason: 'rotation must have produced app.log.1');
    // The generations never exceed the configured maximum (3 files: current
    // + app.log.1 + app.log.2); app.log.3 must not exist.
    expect(await thirdGen.exists(), isFalse);
    // Rotation must not lose anything: every line is still readable.
    final parsed = await logger.loadPersisted();
    expect(parsed.length, 40);
    expect(parsed.first.event, 'line_0');
    expect(parsed.last.event, 'line_39');
  });

  test('concurrent bursts produce a parseable, loss-free log file',
      () async {
    final logger = loggerFor(flushBatch: 1000);
    // Interleave appends without awaits, like several subsystems logging at
    // the same moment.
    for (var i = 0; i < 200; i++) {
      logger.info('concurrent', 'line_$i');
    }
    await logger.sink.flush();

    final file = File('${temp.path}/app.log');
    final content = await file.readAsString();
    final lines =
        content.split('\n').where((line) => line.trim().isNotEmpty).toList();
    expect(lines.length, 200);
    var parsed = 0;
    for (final line in lines) {
      final decoded = jsonDecode(line);
      expect(decoded, isA<Map>());
      parsed++;
    }
    expect(parsed, 200);
  });

  test('a corrupt persisted line is skipped, the rest still loads',
      () async {
    final logger = loggerFor();
    logger.info('test', 'good1');
    logger.info('test', 'good2');
    await logger.sink.flush();
    // Simulate a torn final line from a crash mid-write.
    final file = File('${temp.path}/app.log');
    await file.writeAsString('${await file.readAsString()}{"torn": ');

    final second = loggerFor();
    final persisted = await second.loadPersisted();
    expect(persisted.map((r) => r.event), containsAll(['good1', 'good2']));
  });

  test('clearPersisted removes the files, logging continues after',
      () async {
    final logger = loggerFor();
    logger.info('test', 'before-clear');
    await logger.sink.flush();
    expect(await File('${temp.path}/app.log').exists(), isTrue);

    await logger.clearPersisted();
    expect(await File('${temp.path}/app.log').exists(), isFalse);

    logger.info('test', 'after-clear');
    await logger.sink.flush();
    final persisted = await logger.loadPersisted();
    expect(persisted.map((r) => r.event), ['after-clear']);
  });

  test('timed logs duration on success and failure', () async {
    final logger = loggerFor();
    await logger.timed(
        DiagLevel.info, 'component', 'op', () async => 'result');
    expect(logger.records.map((r) => r.event),
        contains('op.done'));

    await expectLater(
      logger.timed(DiagLevel.info, 'component', 'failing',
          () async => throw StateError('no')),
      throwsA(isA<StateError>()),
    );
    expect(logger.records.map((r) => r.event), contains('failing.failed'));
    final failed =
        logger.records.firstWhere((r) => r.event == 'failing.failed');
    expect(failed.level, DiagLevel.error);
    expect(failed.error, contains('no'));
  });

  test('the Flutter error hook routes framework errors into the log',
      () async {
    final logger = loggerFor()..installErrorHooks();
    // Restore the original hook afterwards so other tests are unaffected.
    addTearDown(() {
      FlutterError.onError = null;
    });
    FlutterError.reportError(FlutterErrorDetails(
        exception: StateError('hook-test'),
        stack: StackTrace.current,
        library: 'test'));
    expect(logger.records.map((r) => r.event), contains('framework.error'));
    final record = logger.records
        .firstWhere((r) => r.event == 'framework.error');
    expect(record.level, DiagLevel.error);
    expect(record.error, contains('hook-test'));
  });
}
