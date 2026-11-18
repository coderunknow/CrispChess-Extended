/// The application's structured logger.
///
/// One instance per process ([instance]); records go to a bounded in-memory
/// buffer for the in-app viewer and to a rotating JSONL file for the next
/// session. Logging is deliberately cheap: a rejected record costs one level
/// comparison, an accepted one costs a small object and — batched — one short
/// file append. Nothing here blocks the UI isolate on disk, and nothing grows
/// without limit (dev6).
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';

import 'diag_log_record.dart';
import 'diag_log_sink.dart';

/// Bounded entry count of the in-memory buffer shown live in the viewer.
const int kDiagBufferLimit = 2000;

/// The structured logger. Use [instance]; construct directly only in tests.
class AppLogger {
  final DiagLogSink sink;
  final int bufferLimit;

  DiagLevel _minLevel =
      kDebugMode ? DiagLevel.debug : DiagLevel.info;
  String? _sessionId;
  int _correlation = 0;

  final ListQueue<DiagLogRecord> _buffer =
      ListQueue<DiagLogRecord>(kDiagBufferLimit);

  final StreamController<List<DiagLogRecord>> _updates =
      StreamController<List<DiagLogRecord>>.broadcast();

  AppLogger({DiagLogSink? sink, this.bufferLimit = kDiagBufferLimit})
      : sink = sink ?? DiagLogSink();

  static AppLogger? _instance;

  /// The process-wide logger.
  static AppLogger get instance => _instance ??= AppLogger();

  /// Replaces the singleton. For tests.
  static void setInstanceForTesting(AppLogger? logger) => _instance = logger;

  /// Id shared by every record of one launch, so a shared report can be told
  /// apart from a previous session's logs.
  String get sessionId => _sessionId ??= _generateSessionId();

  /// Every entry this session produced, oldest first. Bounded by
  /// [bufferLimit]; older entries remain in the rotated files.
  List<DiagLogRecord> get records => List.unmodifiable(_buffer);

  /// Emits the buffer every time new records arrive; the live viewer listens.
  Stream<List<DiagLogRecord>> get updates => _updates.stream;

  /// Severity threshold. Records below it are dropped at zero cost beyond
  /// the call itself. Raising the level in the viewer does not rewrite
  /// history: persisted entries were chosen when they were written.
  DiagLevel get minLevel => _minLevel;
  set minLevel(DiagLevel level) => _minLevel = level;

  /// One-time set-up: loads nothing, writes nothing — safe to call before
  /// `runApp` from inside `main`.
  Future<void> init() async {
    info('app', 'session.started',
        message: 'Diagnostic logging active for session $sessionId');
    await sink.flush();
  }

  static String _generateSessionId() {
    final random = math.Random();
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix =
        List.generate(4, (_) => random.nextInt(36).toRadixString(36)).join();
    return '$stamp-$suffix';
  }

  /// Logs at [level]. Returns false when the record was below the threshold,
  /// which is the cheap path most calls take.
  bool log(
    DiagLevel level,
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) {
    if (level.index < _minLevel.index) return false;
    final record = DiagLogRecord(
      timestamp: DateTime.now(),
      level: level,
      component: component,
      event: event,
      message: message == null ? null : message,
      sessionId: sessionId,
      correlationId: ++_correlation,
      profileId: profileId,
      durationMs: durationMs,
      error: error == null ? null : '$error',
      stackTrace: stackTrace == null ? null : stackTrace.toString(),
      fields: fields.isEmpty ? const {} : Map.of(fields),
    );
    _buffer.addLast(record);
    while (_buffer.length > bufferLimit) {
      _buffer.removeFirst();
    }
    _updates.add(_buffer.toList(growable: false));
    // One console line keeps `flutter run` sessions useful without a viewer.
    debugPrint('[${record.level.label}] ${record.component}.${record.event}'
        '${record.durationMs != null ? ' ${record.durationMs}ms' : ''}'
        '${record.message != null ? ' :: ${record.message}' : ''}'
        '${record.error != null ? ' :: ${record.error}' : ''}');
    // File persistence: fire-and-forget. A failed sink is handled inside.
    unawaited(sink
        .appendLine(jsonEncode(record.toJson()))
        .catchError((_) {}));
    return true;
  }

  bool trace(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.trace, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  bool debug(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.debug, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  bool info(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.info, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  bool warning(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.warning, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  bool error(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.error, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  bool fatal(
    String component,
    String event, {
    String? message,
    String? profileId,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    Map<String, String> fields = const {},
  }) =>
      log(DiagLevel.fatal, component, event,
          message: message,
          profileId: profileId,
          durationMs: durationMs,
          error: error,
          stackTrace: stackTrace,
          fields: fields);

  /// Times [action] and logs its duration as `[component].[event].done`.
  Future<T> timed<T>(
    DiagLevel level,
    String component,
    String event,
    Future<T> Function() action, {
    String? profileId,
    Map<String, String> fields = const {},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      log(level, component, '$event.done',
          durationMs: stopwatch.elapsedMilliseconds,
          profileId: profileId,
          fields: fields);
      return result;
    } catch (caught) {
      stopwatch.stop();
      log(DiagLevel.error, component, '$event.failed',
          durationMs: stopwatch.elapsedMilliseconds,
          profileId: profileId,
          error: caught,
          fields: fields);
      rethrow;
    }
  }

  /// Loads persisted entries from earlier sessions (and this one), oldest
  /// first, bounded. Corrupt lines are skipped: a half-written final line
  /// from a crash must not hide the rest.
  Future<List<DiagLogRecord>> loadPersisted({int maxLines = 5000}) async {
    final lines = await sink.readLines(maxLines: maxLines);
    final parsed = <DiagLogRecord>[];
    for (final line in lines) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map) {
          parsed.add(DiagLogRecord.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // A torn line from a crash between flushes; skip it.
      }
    }
    return parsed;
  }

  /// Deletes the persisted logs (the in-memory buffer stays). The viewer
  /// asks for confirmation before calling this.
  Future<void> clearPersisted() => sink.clear();

  /// Routes unhandled framework and zone errors into the log, so "the app
  /// crashed somewhere" arrives here as a specific entry with a stack trace.
  /// Called once from `main`.
  void installErrorHooks() {
    FlutterError.onError = (details) {
      error('flutter', 'framework.error',
          message: details.informationCollector?.toString() ??
              details.context?.toString(),
          error: details.exception,
          stackTrace: details.stack);
    };
    PlatformDispatcher.instance.onError = (caught, stack) {
      fatal('app', 'uncaught.zone.error', error: caught, stackTrace: stack);
      return false;
    };
  }
}
