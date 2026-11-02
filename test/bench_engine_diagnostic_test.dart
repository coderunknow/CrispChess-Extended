// An engine that cannot start is a failed engine in the run — with the
// structured root cause stored, redacted, in its status — never a completed
// one, and never the bare "initialize returned with state error".
library;

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
}
