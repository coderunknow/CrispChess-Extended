// The Stability Probe reports *why* an engine failed to start, not only that
// it did: a structured root cause (failure kind, stage, exit code, backend),
// one diagnostic per distinct cause, redacted for export, and never a crash
// of the probe itself.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crispchess/bench/stability_probe.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

/// White to move in the probe's default position (Italian-game setup):
/// short castling is legal.
const _legal = 'e1g1';

class _SilentFailureEngine extends ScriptedEngine {
  _SilentFailureEngine() : super('Silent');
  bool _started = false;
  bool _gone = false;

  @override
  EngineState get state => _gone
      ? EngineState.disposed
      : (_started ? EngineState.error : EngineState.idle);

  @override
  Future<void> initialize() async => _started = true;

  @override
  void dispose() {
    super.dispose();
    _gone = true;
  }
}

const _probe = StabilityProbe(
  initialisationCycles: 3,
  searchCycles: 2,
  moveTime: Duration(milliseconds: 5),
  timeout: Duration(seconds: 2),
);

void main() {
  test('a healthy engine passes with no root cause', () async {
    final report = await _probe.run(
      identity: testIdentity('Healthy'),
      build: () => ScriptedEngine('Healthy')..ask = (_, __) async => _legal,
    );
    expect(report.passed, isTrue, reason: report.failures.join('\n'));
    expect(report.rootCause, isNull);
  });

  test('a structured startup failure becomes the root cause, once', () async {
    final report = await _probe.run(
      identity: testIdentity('Stockfish'),
      build: () => ScriptedEngine('Stockfish')
        ..initFailure = EngineInitializationException(
          engine: 'Stockfish',
          version: '16',
          stage: EngineInitStage.resolveRuntime,
          platform: 'windows',
          kind: EngineFailureKind.runtimeMissing,
          backend: 'native-process',
          runtimePath: r'C:\Users\alice\stockfish.exe',
          cause: StateError('Stockfish is not installed'),
        ),
    );
    expect(report.passed, isFalse);
    final cause = report.rootCause!;
    expect(cause['kind'], 'runtimeMissing');
    expect(cause['stage'], EngineInitStage.resolveRuntime);
    expect(cause['backend'], 'native-process');
    final initialisation = report.checks.first;
    expect(initialisation.failures, hasLength(3), reason: 'every cycle counts');
    expect(initialisation.diagnostics, hasLength(1),
        reason: 'three identical failures are one root cause');
    final exported = jsonEncode(report.toJson());
    expect(exported, isNot(contains('alice')), reason: 'redacted for export');
    expect(report.toMarkdown(), contains('Root cause: `runtimeMissing`'));
  });

  test('initialize() returning while not ready is readinessFailed', () async {
    final report = await _probe.run(
      identity: testIdentity('Silent'),
      build: _SilentFailureEngine.new,
    );
    expect(report.passed, isFalse);
    expect(report.rootCause!['kind'], 'readinessFailed');
    expect(report.rootCause!['stage'], EngineInitStage.verifyReady);
  });

  test('a hanging start is readinessTimeout, not a hung probe', () async {
    final report = await const StabilityProbe(
      initialisationCycles: 1,
      searchCycles: 1,
      timeout: Duration(milliseconds: 50),
    ).run(
      identity: testIdentity('Hangs'),
      build: () => ScriptedEngine('Hangs')..initGate = Completer<void>(),
    );
    expect(report.passed, isFalse);
    expect(report.rootCause!['kind'], 'readinessTimeout');
  });

  test('distinct causes are kept apart', () async {
    var built = 0;
    final report = await _probe.run(
      identity: testIdentity('Flaky'),
      build: () {
        built++;
        return ScriptedEngine('Flaky')
          ..initFailure = built.isOdd
              ? const EngineStartupFailure(
                  EngineFailureKind.processExited, 'exited with code 3')
              : const EngineStartupFailure(
                  EngineFailureKind.handshakeTimeout, 'no uciok');
      },
    );
    final kinds = report.checks.first.diagnostics.map((d) => d['kind']).toSet();
    expect(kinds, {'processExited', 'handshakeTimeout'});
  });

  test('diagnostics survive a JSON round trip', () async {
    final report = await _probe.run(
      identity: testIdentity('Broken'),
      build: () => ScriptedEngine('Broken')
        ..initFailure = const EngineStartupFailure(
            EngineFailureKind.processLaunchFailed, 'exec format error'),
    );
    final restored = StabilityReport.fromJson(
        jsonDecode(jsonEncode(report.toJson())) as Map<String, dynamic>);
    expect(restored.rootCause!['kind'], 'processLaunchFailed');
    expect(restored.passed, isFalse);
  });
}
