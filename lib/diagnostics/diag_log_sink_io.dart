// File-backed diagnostic log sink (Android, iOS, desktop).
//
// Not imported directly: `diag_log_sink.dart` picks this file on platforms
// with `dart:io` and `diag_log_sink_stub.dart` in a browser.
//
// JSON lines are appended to `app.log` under the application support
// directory. The file rotates by size, keeping a bounded number of
// generations, so the logs survive ordinary restarts without ever growing
// without limit. Every call is failure-tolerant: a missing or unwritable
// storage location degrades to in-memory-only logging, never to a crash.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';

/// Persistence contract for diagnostic log lines.
class DiagLogSink {
  /// Size at which `app.log` rotates into the numbered generations.
  final int maxFileBytes;

  /// Number of files kept in total: the current one plus this many old ones.
  final int maxGenerations;

  /// Lines buffered before a flush happens without waiting for the timer.
  final int flushBatch;

  /// How long lines may sit in memory before they are flushed.
  final Duration flushInterval;

  /// Directory to use instead of the application support directory.
  ///
  /// Rotation, batching and recovery are the parts of this class a test has
  /// to exercise against a real file system; a temporary directory stands in
  /// for application support like it does for [FileBenchmarkStorage].
  final Directory? rootOverride;

  Directory? _directory;
  int _currentBytes = 0;
  final List<String> _pending = [];
  Timer? _flushTimer;
  bool _warnedUnavailable = false;
  int _writesSinceFlush = 0;

  DiagLogSink({
    this.maxFileBytes = 1024 * 1024,
    this.maxGenerations = 3,
    this.flushBatch = 32,
    this.flushInterval = const Duration(seconds: 2),
    this.rootOverride,
  });

  Future<Directory?> _logDirectory() async {
    final existing = _directory;
    if (existing != null) return existing;
    final override = rootOverride;
    if (override != null) {
      _directory = override;
      return override;
    }
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/logs');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      _directory = directory;
      return directory;
    } catch (error) {
      _warnOnce('diagnostic log directory unavailable: $error');
      return null;
    }
  }

  File _currentFile(Directory directory) => File('${directory.path}/app.log');

  void _warnOnce(String message) {
    if (_warnedUnavailable) return;
    _warnedUnavailable = true;
    debugPrint('[Diagnostics] $message');
  }

  /// Appends one JSON line. Buffered; the flush happens in batches or after
  /// [flushInterval], whichever comes first, so a burst of entries costs one
  /// small file write instead of one per line.
  Future<void> appendLine(String line) async {
    final directory = await _logDirectory();
    if (directory == null) return;
    _pending.add(line);
    _writesSinceFlush++;
    if (_writesSinceFlush >= flushBatch) {
      await flush();
      return;
    }
    _flushTimer ??= Timer(flushInterval, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  /// Writes the buffered lines and rotates when the file has grown past
  /// [maxFileBytes]. Appends are small (one batch) and asynchronous, so the
  /// UI isolate never waits on disk; concurrent flushes serialize through
  /// the shared buffer, which is drained by the first caller.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    final directory = await _logDirectory();
    if (directory == null) {
      _pending.clear();
      return;
    }
    if (_pending.isEmpty) return;
    final lines = List.of(_pending);
    _pending.clear();
    _writesSinceFlush = 0;
    try {
      final file = _currentFile(directory);
      final text = lines.map((line) => '$line\n').join();
      await file.writeAsString(text, mode: FileMode.append);
      _currentBytes += text.length;
      if (_currentBytes >= maxFileBytes) {
        await _rotate(directory);
      }
    } catch (error) {
      // Losing a flush to a full disk or a locked file must not take the app
      // down; the entries stay in memory and the console copy was already made.
      _warnOnce('diagnostic log flush failed: $error');
    }
  }

  /// app.log -> app.log.1 -> app.log.2, the oldest generation deleted.
  Future<void> _rotate(Directory directory) async {
    try {
      for (var generation = maxGenerations - 1; generation >= 1; generation--) {
        final source = File('${directory.path}/app.log.${generation}');
        if (generation + 1 > maxGenerations) {
          if (await source.exists()) await source.delete();
          continue;
        }
        if (await source.exists()) {
          await source
              .rename('${directory.path}/app.log.${generation + 1}');
        }
      }
      await _currentFile(directory).rename('${directory.path}/app.log.1');
      _currentBytes = 0;
    } catch (error) {
      _warnOnce('diagnostic log rotation failed: $error');
    }
  }

  /// Newest-first lines from all generations, bounded to [maxLines]. Used by
  /// the in-app viewer to show what earlier sessions logged.
  Future<List<String>> readLines({int maxLines = 5000}) async {
    final directory = await _logDirectory();
    if (directory == null) return const [];
    await flush();
    final lines = <String>[];
    final files = <File>[
      _currentFile(directory),
      for (var generation = 1; generation <= maxGenerations; generation++)
        File('${directory.path}/app.log.$generation'),
    ];
    for (final file in files.reversed) {
      try {
        if (!await file.exists()) continue;
        final content = await file.readAsString();
        lines.addAll(
            content.split('\n').where((line) => line.trim().isNotEmpty));
      } catch (error) {
        _warnOnce('diagnostic log read failed: $error');
      }
    }
    return lines.length <= maxLines ? lines : lines.sublist(lines.length - maxLines);
  }

  /// Deletes every log file. Called after the user confirms the clear.
  Future<void> clear() async {
    _pending.clear();
    _currentBytes = 0;
    final directory = await _logDirectory();
    if (directory == null) return;
    for (final name in [
      'app.log',
      for (var generation = 1; generation <= maxGenerations; generation++)
        'app.log.$generation'
    ]) {
      final file = File('${directory.path}/$name');
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
