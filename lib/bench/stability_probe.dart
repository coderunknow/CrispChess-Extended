/// Stability diagnostics: does this engine keep working when asked repeatedly?
///
/// A rating says how strong an engine is when it works. This answers the other
/// question — whether it starts, searches, returns legal moves and shuts down
/// without leaving anything behind — because an engine that fails one game in
/// twenty has a rating that means less than its interval suggests.
///
/// Everything here is measured from the outside: real initialisations, real
/// searches, a real board to check legality against. Nothing is inferred from
/// what the engine claims about itself.
library;

import 'dart:async';

import 'package:chess/chess.dart' as chess;

import '../engines/chess_engine.dart';
import '../engines/engine_initialization.dart';
import 'engine_identity.dart';
import 'game_player.dart' show applyUciMove;

/// One diagnostic.
class StabilityCheck {
  final String name;

  /// Runs attempted and runs that came back without an error.
  final int attempts;
  final int passed;

  /// What went wrong, in order.
  final List<String> failures;

  /// Durations of the successful runs, in milliseconds.
  final List<int> durations;

  /// Structured root causes (redacted `EngineInitializationException.toJson`
  /// maps: stage, failure kind, cause, exit code, stderr tail, backend), one
  /// per distinct startup failure. Empty when nothing failed to start.
  final List<Map<String, dynamic>> diagnostics;

  const StabilityCheck({
    required this.name,
    required this.attempts,
    required this.passed,
    this.failures = const [],
    this.durations = const [],
    this.diagnostics = const [],
  });

  bool get ok => attempts > 0 && passed == attempts && failures.isEmpty;

  int get medianMillis {
    if (durations.isEmpty) return 0;
    final sorted = [...durations]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  int get maxMillis =>
      durations.isEmpty ? 0 : durations.reduce((a, b) => a > b ? a : b);

  Map<String, dynamic> toJson() => {
        'name': name,
        'attempts': attempts,
        'passed': passed,
        if (failures.isNotEmpty) 'failures': failures,
        if (durations.isNotEmpty) 'medianMillis': medianMillis,
        if (durations.isNotEmpty) 'maxMillis': maxMillis,
        if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
      };

  factory StabilityCheck.fromJson(Map<String, dynamic> json) {
    final failures = <String>[];
    final rawFailures = json['failures'];
    if (rawFailures is List) {
      for (final failure in rawFailures) {
        failures.add('$failure');
      }
    }
    int of(String key) => json[key] is num ? (json[key] as num).toInt() : 0;
    final median = of('medianMillis');
    final diagnostics = <Map<String, dynamic>>[];
    final rawDiagnostics = json['diagnostics'];
    if (rawDiagnostics is List) {
      for (final entry in rawDiagnostics) {
        if (entry is Map) diagnostics.add(Map<String, dynamic>.from(entry));
      }
    }
    return StabilityCheck(
      name: (json['name'] as String?) ?? 'check',
      attempts: of('attempts'),
      passed: of('passed'),
      failures: failures,
      durations: median > 0 ? [median] : const [],
      diagnostics: diagnostics,
    );
  }
}

/// The full result for one engine.
class StabilityReport {
  final EngineIdentity identity;
  final DateTime startedAt;
  final DateTime finishedAt;
  final List<StabilityCheck> checks;

  const StabilityReport({
    required this.identity,
    required this.startedAt,
    required this.finishedAt,
    required this.checks,
  });

  bool get passed => checks.every((check) => check.ok);

  List<String> get failures => [
        for (final check in checks)
          for (final failure in check.failures) '${check.name}: $failure'
      ];

  Duration get duration => finishedAt.difference(startedAt);

  /// The first structured startup failure, when the engine failed to start:
  /// the root cause the report leads with instead of a list of symptoms.
  Map<String, dynamic>? get rootCause {
    for (final check in checks) {
      if (check.diagnostics.isNotEmpty) return check.diagnostics.first;
    }
    return null;
  }

  String toMarkdown() {
    final out = StringBuffer();
    out.writeln('### ${identity.label} — '
        '${passed ? 'passed' : 'FAILED'}');
    out.writeln();
    out.writeln('| Check | Passed | Median | Worst | Failures |');
    out.writeln('|---|---|---|---|---|');
    for (final check in checks) {
      out.writeln('| ${check.name} | ${check.passed}/${check.attempts} '
          '| ${check.medianMillis} ms | ${check.maxMillis} ms '
          '| ${check.failures.length} |');
    }
    final cause = rootCause;
    if (cause != null) {
      out.writeln();
      out.writeln('Root cause: `${cause['kind']}` at `${cause['stage']}`'
          '${cause['exitCode'] != null ? ' (exit code ${cause['exitCode']})' : ''}'
          '${cause['backend'] != null ? ' — backend ${cause['backend']}' : ''}');
    }
    for (final failure in failures) {
      out.writeln();
      out.writeln('> $failure');
    }
    return out.toString();
  }

  Map<String, dynamic> toJson() => {
        'identity': identity.toJson(),
        'startedAt': startedAt.toIso8601String(),
        'finishedAt': finishedAt.toIso8601String(),
        'checks': [for (final check in checks) check.toJson()],
        'passed': passed,
      };

  factory StabilityReport.fromJson(Map<String, dynamic> json) {
    final checks = <StabilityCheck>[];
    final raw = json['checks'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          checks.add(StabilityCheck.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    final identity = json['identity'];
    return StabilityReport(
      identity: identity is Map
          ? EngineIdentity.fromJson(Map<String, dynamic>.from(identity))
          : EngineIdentity.fromJson(const {}),
      startedAt: DateTime.tryParse((json['startedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      finishedAt: DateTime.tryParse((json['finishedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      checks: checks,
    );
  }
}

/// Runs the diagnostics against an engine.
class StabilityProbe {
  /// How many times the engine is started from scratch.
  final int initialisationCycles;

  /// How many searches one running instance is asked for.
  final int searchCycles;

  /// Per-move budget for the diagnostic searches.
  final Duration moveTime;

  /// Position the searches are run from (a quiet middlegame).
  final String positionFen;

  /// How long one diagnostic call may take before it counts as a hang.
  final Duration timeout;

  const StabilityProbe({
    this.initialisationCycles = 3,
    this.searchCycles = 5,
    this.moveTime = const Duration(milliseconds: 100),
    this.positionFen =
        'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4',
    this.timeout = const Duration(seconds: 30),
  });

  /// Runs every check for one engine.
  ///
  /// [build] is called for each cycle: an engine that has been disposed cannot
  /// be initialised again, and reusing one would test the app's state machine
  /// rather than the engine.
  Future<StabilityReport> run({
    required EngineIdentity identity,
    required ChessEngine Function() build,
  }) async {
    final startedAt = DateTime.now();
    final checks = <StabilityCheck>[];

    // 1. Repeated initialisation, each from a fresh instance, with disposal
    //    after every cycle: a leak or a wedged process shows up here as a
    //    failure on a later cycle.
    final initDurations = <int>[];
    final initFailures = <String>[];
    final initDiagnostics = <Map<String, dynamic>>[];
    var initPassed = 0;
    for (var cycle = 0; cycle < initialisationCycles; cycle++) {
      final engine = build();
      final stopwatch = Stopwatch()..start();
      try {
        await _initialize(engine);
        stopwatch.stop();
        initDurations.add(stopwatch.elapsedMilliseconds);
        initPassed++;
      } catch (error, stack) {
        stopwatch.stop();
        final failure = _structured(engine, error, stack, identity);
        initFailures.add('cycle ${cycle + 1}: ${_short(failure.summary)}');
        _addDistinct(initDiagnostics, failure);
      } finally {
        try {
          engine.dispose();
        } catch (error) {
          initFailures.add('cycle ${cycle + 1}: dispose failed: '
              '${_short(error)}');
        }
      }
    }
    checks.add(StabilityCheck(
      name: 'Initialisation',
      attempts: initialisationCycles,
      passed: initPassed,
      failures: initFailures,
      durations: initDurations,
      diagnostics: initDiagnostics,
    ));

    // 2. Repeated searches on one instance, each move checked for legality.
    final engine = build();
    final searchDurations = <int>[];
    final searchFailures = <String>[];
    final searchDiagnostics = <Map<String, dynamic>>[];
    var searchPassed = 0;
    var disposeOk = true;
    var started = false;
    try {
      await _initialize(engine);
      started = true;
      for (var cycle = 0; cycle < searchCycles; cycle++) {
        final board = chess.Chess();
        if (!board.load(positionFen)) {
          searchFailures.add('the diagnostic position did not load');
          break;
        }
        final stopwatch = Stopwatch()..start();
        try {
          final move = await engine
              .bestMove('position fen $positionFen',
                  moveTime: moveTime)
              .timeout(timeout + moveTime);
          stopwatch.stop();
          if (move.trim().isEmpty) {
            searchFailures.add('search ${cycle + 1}: no move returned');
            continue;
          }
          if (!applyUciMove(board, move)) {
            searchFailures.add('search ${cycle + 1}: illegal move "$move" in '
                '$positionFen');
            continue;
          }
          searchDurations.add(stopwatch.elapsedMilliseconds);
          searchPassed++;
        } catch (error) {
          stopwatch.stop();
          searchFailures.add('search ${cycle + 1}: ${_short(error)}');
        }
      }
    } catch (error, stack) {
      if (started) {
        searchFailures.add('search checks: ${_short(error)}');
      } else {
        final failure = _structured(engine, error, stack, identity);
        searchFailures.add('initialisation for the search checks: '
            '${_short(failure.summary)}');
        _addDistinct(searchDiagnostics, failure);
      }
    } finally {
      try {
        engine.dispose();
        if (engine.state != EngineState.disposed) {
          disposeOk = false;
          searchFailures.add('the engine reported ${engine.state.name} after '
              'dispose');
        }
      } catch (error) {
        disposeOk = false;
        searchFailures.add('dispose failed: ${_short(error)}');
      }
    }
    checks.add(StabilityCheck(
      name: 'Repeated searches',
      attempts: searchCycles,
      passed: searchPassed,
      failures: searchFailures,
      durations: searchDurations,
      diagnostics: searchDiagnostics,
    ));
    checks.add(StabilityCheck(
      name: 'Clean shutdown',
      attempts: 1,
      passed: disposeOk ? 1 : 0,
      failures: disposeOk ? const [] : const ['the instance did not shut down'],
    ));

    // No separate "protocol conformance" row: an engine that cannot answer
    // `uci`, `isready` or `bestmove` fails the two checks above, and a row that
    // always passes would be a pass nobody earned.

    return StabilityReport(
      identity: identity,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      checks: checks,
    );
  }

  /// Starts [engine] under the probe's timeout. A normal return that leaves
  /// the engine anything but ready is a contract violation and reported as
  /// one (with the adapter's recorded cause when it has one).
  Future<void> _initialize(ChessEngine engine) async {
    try {
      await engine.initialize().timeout(timeout);
    } on TimeoutException catch (error, stack) {
      // The adapter's own timeouts are shorter; this is the probe giving up.
      throw EngineInitializationException(
        engine: engine.name,
        version: engine.version,
        stage: EngineInitStage.initialize,
        platform: enginePlatformLabel(),
        cause: error,
        causeStack: stack,
        kind: EngineFailureKind.readinessTimeout,
        detail: 'the Stability Probe stopped waiting after '
            '${timeout.inSeconds}s',
      );
    }
    requireEngineReady(engine, platform: enginePlatformLabel());
  }

  EngineInitializationException _structured(ChessEngine engine, Object error,
          StackTrace stack, EngineIdentity identity) =>
      engineFailureOf(engine, error, stack, engineId: identity.engineId);

  /// One diagnostic per distinct (kind, stage, cause): three identical
  /// failed cycles are one root cause, not three.
  void _addDistinct(
      List<Map<String, dynamic>> into, EngineInitializationException failure) {
    final json = Map<String, dynamic>.from(failure.toJson());
    final key = '${json['kind']}|${json['stage']}|${json['cause']}';
    if (into.any((d) => '${d['kind']}|${d['stage']}|${d['cause']}' == key)) {
      return;
    }
    into.add(json);
  }
}

String _short(Object error) {
  final text = redactPersonalPaths(error.toString()).replaceAll('\n', ' ');
  return text.length <= 200 ? text : '${text.substring(0, 200)}…';
}
