/// Noticing when an engine process dies.
///
/// A UCI engine that crashes mid-search owes an answer it will never send.
/// Without something watching the process, nothing completes the outstanding
/// request: the caller waits out its own cap — 6.8 seconds for a 300ms budget
/// — and then reports a timeout. A crashed engine and a slow one are then
/// indistinguishable, which is the wrong thing to tell someone, because a slow
/// engine wants a bigger budget and a dead one wants its stderr read.
///
/// Measured on a stub engine that exits on `go`: the death is visible in 13ms.
///
/// Every engine here that spawns a process needs this, so it lives in one
/// place rather than three.
library;

// The exception itself lives in chess_engine.dart: it is part of the
// contract a caller sees, and this file imports dart:io, which the web
// build cannot.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'chess_engine.dart';

/// Watches a spawned engine process and reports its death.
///
/// The host calls [watchProcess] once the process is up, routes stdout's
/// `onDone`/`onError` to [releaseOnLoss], and asks [processGone] before and
/// after a search so it can tell a death from a timeout.
mixin UciProcessLifecycle {
  Process? _watched;
  StreamSubscription<String>? _stderrSub;

  /// Set once the connection is gone, so a request can say so instead of
  /// waiting. Stdout closing is the earliest sign and arrives well before the
  /// exit code — watching only the code left a 13ms death reported 6.8 seconds
  /// later, as the wrong thing.
  bool _exited = false;
  int? _exitCode;

  /// The last few stderr lines, kept for the report. A crash usually explains
  /// itself there, and that output was being discarded.
  final List<String> _stderrTail = [];

  /// Set while tearing down on purpose, so a kill is not called a crash.
  bool _disposingProcess = false;

  /// True once the process is known to be gone.
  bool get processGone => _exited;

  /// Called when the connection is lost, to complete anything outstanding.
  /// The host supplies this — only it knows what a pending request looks like.
  void onProcessLost();

  /// A label for the report.
  String get processLabel;

  /// The most recently watched process. Unlike [_watched] it survives
  /// [stopWatchingProcess], so a death that lands just after teardown still
  /// records its exit code — but a process replaced by a retry does not.
  Process? _latest;

  void watchProcess(Process process) {
    _watched = process;
    _latest = process;
    _exited = false;
    _exitCode = null;
    _disposingProcess = false;
    _stderrTail.clear();

    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      _stderrTail.add(line);
      if (_stderrTail.length > 10) _stderrTail.removeAt(0);
      debugPrint('[$processLabel stderr] $line');
    });

    // A write to stdin after the process has exited (an executable that
    // dies at once: wrong architecture, a missing DLL, not an engine) fails
    // asynchronously with "Broken pipe" on the sink's `done` future. Nobody
    // else listens to it, so without this the error escapes as an unhandled
    // exception instead of becoming the death report below.
    unawaited(process.stdin.done.then<void>((_) {}, onError: (Object error) {
      if (!identical(_latest, process)) return;
      debugPrint('[$processLabel] stdin closed with error: $error');
    }));

    unawaited(process.exitCode.then((code) {
      // A process replaced by a retry (or already let go) must not report its
      // exit against the one now being watched.
      if (!identical(_latest, process)) return;
      _exitCode = code;
      if (!_disposingProcess) {
        debugPrint('[$processLabel] exited with code $code');
      }
      releaseOnLoss();
    }));
  }

  /// Note that the far end is gone and let the host finish what is pending.
  ///
  /// Routed from both the exit code and stdout closing, because they do not
  /// arrive together and a request should end on whichever comes first.
  void releaseOnLoss() {
    _exited = true;
    onProcessLost();
  }

  /// Whether a teardown is in progress, so state changes can stay quiet.
  bool get disposingProcess => _disposingProcess;

  void beginProcessDispose() => _disposingProcess = true;

  void stopWatchingProcess() {
    _stderrSub?.cancel();
    _stderrSub = null;
    _watched = null;
  }

  /// The death report, with the exit code if it can be had.
  ///
  /// Stdout closes a moment before the exit code lands, and the code is the
  /// most useful part, so this waits briefly rather than saying "unknown" —
  /// which also lets a last stderr line be delivered.
  Future<EngineProcessDiedException> processDeathReport() async {
    final process = _watched ?? (_exited ? _latest : null);
    if (_exitCode == null && process != null) {
      try {
        _exitCode = await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        // Gone but not reaped; report it without a code.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return EngineProcessDiedException(
        processLabel, _exitCode, List.of(_stderrTail));
  }
}
