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

import '../diagnostics/engine_process_registry.dart'
    show managedProcessRegistry;
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

    // Register the process by its stable id so Hardware Protection can sum
    // exactly the engine processes this app started, without matching names.
    managedProcessRegistry.register(process.pid, label: processLabel);

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
      // exit against the one now being watched. But its PID was registered when
      // it started, and nothing else will ever unregister it once it is no
      // longer `_latest`/`_watched` — so unregister it here before returning,
      // otherwise a stale PID stays in the registry and, after PID reuse, the
      // memory monitor could charge an unrelated process as an engine.
      if (!identical(_latest, process)) {
        managedProcessRegistry.unregister(process.pid);
        return;
      }
      _exitCode = code;
      if (!_disposingProcess) {
        debugPrint('[$processLabel] exited with code $code');
      }
      // The process has truly exited: stop accounting for it so its memory is
      // not summed after it has died. Unregister here (the exit path) rather
      // than inside [releaseOnLoss], because stdout can close while the
      // process is still running.
      managedProcessRegistry.unregister(process.pid);
      releaseOnLoss();
    }));
  }

  /// Note that the far end is gone and let the host finish what is pending.
  ///
  /// Routed from both the exit code and stdout closing, because they do not
  /// arrive together and a request should end on whichever comes first.
  ///
  /// This only releases pending work — it deliberately does NOT unregister the
  /// process from [managedProcessRegistry]. stdout can close while the process
  /// is still running (a `GenericUciEngine` may close its stdout without
  /// exiting), and unregistering here would drop a live, still-consuming
  /// process from the memory monitor's accounting. The process is unregistered
  /// only when its exit code actually lands (see [watchProcess]) or on explicit
  /// teardown ([stopWatchingProcess]).
  void releaseOnLoss() {
    if (_exited) return;
    _exited = true;
    onProcessLost();
  }

  /// Whether a teardown is in progress, so state changes can stay quiet.
  bool get disposingProcess => _disposingProcess;

  void beginProcessDispose() => _disposingProcess = true;

  void stopWatchingProcess() {
    _stderrSub?.cancel();
    _stderrSub = null;
    // A replaced or disposed process is no longer a managed engine process.
    final watched = _watched;
    if (watched != null) managedProcessRegistry.unregister(watched.pid);
    final latest = _latest;
    if (latest != null && latest != watched) {
      managedProcessRegistry.unregister(latest.pid);
    }
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
