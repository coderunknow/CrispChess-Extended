// An engine that cannot start is a failed engine in the run — with the
// structured root cause stored, redacted, in its status — never a completed
// one, and never the bare "initialize returned with state error".
library;

import 'dart:async';
import 'dart:convert';

import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

class _SilentFailureEngine extends ScriptedEngine {
  _SilentFailureEngine(super.name);
  bool _started = false;
  bool _gone = false;

  @override
  EngineState get state => _gone
      ? EngineState.disposed
      : (_started ? EngineState.error : EngineState.idle);

  @override
  Future<void> initialize() async {
    initialised.add(name);
    _started = true;
  }

  @override
  void dispose() {
    super.dispose();
    _gone = true;
  }
}

/// Starts fine, then fails while its options are synchronised and ends up in
/// `error` (like Stockfish over a disposed custom UCI delegate).
class _ConfigFailureEngine extends ScriptedEngine {
  _ConfigFailureEngine(super.name);
  bool _broken = false;

  @override
  EngineState get state => _broken ? EngineState.error : super.state;

  @override
  Future<void> synchronizeOptions() async {
    _broken = true;
    throw TimeoutException('no readyok after setoption');
  }
}

void main() {
  test('a startup failure is stored as a structured, redacted diagnostic',
      () async {
    final alpha = ScriptedEngine('Alpha')
      ..initFailure = EngineInitializationException(
        engine: 'Alpha',
        version: '16',
        stage: EngineInitStage.resolveRuntime,
        platform: 'windows',
        kind: EngineFailureKind.runtimeMissing,
        runtimePath: r'C:\Users\dave\stockfish.exe',
        cause: StateError('Stockfish is not installed'),
      );
    final result = await runScriptedBenchmark(alpha: alpha);
    addTearDown(result.runner.dispose);
    final status = result.run.engineStatus[testIdentity('Alpha').engineId]!;
    expect(status.status, 'failed');
    expect(status.isFailure, isTrue);
    expect(status.failureKind, 'runtimeMissing');
    expect(status.diagnostic!['stage'], EngineInitStage.resolveRuntime);
    expect(status.reason, isNot(contains('initialize returned')));
    final stored = jsonEncode(result.run.toJson());
    expect(stored, isNot(contains('dave')));
    final restored = BenchmarkRun.fromJson(
        jsonDecode(stored) as Map<String, dynamic>);
    expect(
        restored.engineStatus[testIdentity('Alpha').engineId]!.failureKind,
        'runtimeMissing');
  });

  test('initialize() returning while not ready fails the engine', () async {
    final result =
        await runScriptedBenchmark(alpha: _SilentFailureEngine('Alpha'));
    addTearDown(result.runner.dispose);
    final status = result.run.engineStatus[testIdentity('Alpha').engineId]!;
    expect(status.status, 'failed');
    expect(status.failureKind, 'readinessFailed');
    expect(status.status, isNot('completed'));
    expect(result.alpha.askedPositions, isEmpty,
        reason: 'no game is played with an engine that did not start');
  });

  test('a failure while configuring a started engine is not a startup failure',
      () async {
    final result = await runScriptedBenchmark(
      alpha: _ConfigFailureEngine('Alpha'),
      config: benchConfig().copyWith(threads: 2),
    );
    addTearDown(result.runner.dispose);
    final status = result.run.engineStatus[testIdentity('Alpha').engineId]!;
    expect(status.status, 'failed');
    expect(status.diagnostic, isNull,
        reason: 'it started; its live error state must not make the '
            'configuration failure look like a startup failure');
    expect(status.reason, contains('no readyok after setoption'));
    expect(result.alpha.askedPositions, isEmpty);
  });
}
