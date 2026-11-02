// Engine Preflight: every engine is started, asked for one move and shut down
// before a benchmark schedules games for it.
//
// The engines here are scripted `ChessEngine`s (see support/bench_harness), so
// the real preflight code runs against each failure shape: unsupported
// platform, a download the user declines, a failed or hanging initialization,
// an engine that returns from initialize() without being ready (the shape of
// the original "initialize returned with state error" bug), an illegal move,
// a search that never answers, options that are not advertised, cancellation
// and a failing cleanup.
library;

import 'dart:async';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/engine_preflight.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

/// White to move after 1.e4 e5 2.Nf3 Nc6 — the preflight's default position.
const _legal = 'f1c4';

class _DownloadEngine extends ScriptedEngine implements DownloadAwareEngine {
  final EngineDownloadRequirement? requirement;
  _DownloadEngine(this.requirement) : super('Downloader');

  @override
  Future<EngineDownloadRequirement?> pendingDownload() async => requirement;
}

/// Returns from initialize() normally while not ready — a contract violation.
class _SilentFailureEngine extends ScriptedEngine {
  _SilentFailureEngine() : super('Silent');
  EngineState _mine = EngineState.idle;

  @override
  EngineState get state => _mine == EngineState.idle ? super.state : _mine;

  @override
  Future<void> initialize() async {
    initialised.add(name);
    _mine = EngineState.error;
  }

  @override
  void dispose() {
    super.dispose();
    _mine = EngineState.disposed;
  }
}

class _ReportingEngine extends ScriptedEngine implements EngineRuntimeReport {
  @override
  final String? requestedVersion;
  @override
  final String? detectedVersion;
  @override
  final String? fallbackReason;
  @override
  final String effectiveBackend;

  _ReportingEngine({
    this.requestedVersion,
    this.detectedVersion,
    this.fallbackReason,
    this.effectiveBackend = 'native-process',
  }) : super('Reporter');

  @override
  EngineInitializationException? get initializationError => null;
}

class _FewOptionsEngine extends ScriptedEngine {
  _FewOptionsEngine() : super('FewOptions');
  @override
  List<String> get advertisedOptionNames => const ['Threads'];
}

class _BadDisposeEngine extends ScriptedEngine {
  _BadDisposeEngine() : super('BadDispose');
  @override
  void dispose() {
    disposeCalls++;
    throw StateError('process would not exit');
  }
}

BenchmarkConfig _config({int hashMb = 0}) =>
    benchConfig().copyWith(threads: 1, hashMb: hashMb);

final EngineIdentity _identity = testIdentity('Engine');

Future<EnginePreflightResult> _check(
  ChessEngine engine, {
  EnginePreflight checker = const EnginePreflight(
      moveTime: Duration(milliseconds: 10),
      searchGrace: Duration(seconds: 2),
      initTimeout: Duration(seconds: 2)),
  bool available = true,
  EngineIdentity? identity,
  BenchmarkConfig? config,
  PreflightDownloadConsent? consent,
  PreflightCancellation? cancellation,
  List<PreflightStepResult>? live,
}) =>
    checker.check(
      engineId: identity?.engineId ?? _identity.engineId,
      label: engine.name,
      available: available,
      unavailableReason: available ? null : 'not on this platform',
      build: () => engine,
      identity: available ? (identity ?? _identity) : null,
      config: config ?? _config(),
      appBuild: 'test',
      consent: consent ?? (_, __) async => false,
      cancellation: cancellation,
      onStep: live?.add,
    );

PreflightStatus _step(EnginePreflightResult result, PreflightStep step) =>
    result.steps.singleWhere((s) => s.step == step).status;

void main() {
  group('EnginePreflight.check', () {
    test('a working engine passes every step and is shut down', () async {
      final engine = ScriptedEngine('Good')..ask = (_, __) async => _legal;
      final live = <PreflightStepResult>[];
      final result = await _check(engine, live: live);
      expect(result.status, PreflightStatus.passed);
      for (final step in PreflightStep.values) {
        expect(_step(result, step), PreflightStatus.passed, reason: step.id);
      }
      expect(engine.disposed, isTrue);
      expect(result.binding, isNotNull);
      expect(live.map((s) => s.step).toList(), PreflightStep.values);
      expect(result.decisiveStep, isNull);
    });

    test('an engine this platform cannot run is unsupported and never built',
        () async {
      var built = false;
      final result = await const EnginePreflight().check(
        engineId: 'builtin:X',
        label: 'X',
        available: false,
        unavailableReason: 'needs a desktop',
        build: () {
          built = true;
          return ScriptedEngine('X');
        },
        identity: null,
        config: _config(),
        appBuild: 'test',
        consent: (_, __) async => true,
      );
      expect(built, isFalse);
      expect(result.status, PreflightStatus.unsupported);
      expect(_step(result, PreflightStep.platform), PreflightStatus.unsupported);
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.skipped);
      expect(result.steps, hasLength(PreflightStep.values.length));
    });

    test('nothing is downloaded without consent', () async {
      final requirement = EngineDownloadRequirement(
        description: 'stockfish.js 10.0.2',
        source: Uri.parse('https://example.org/stockfish.js'),
        license: 'GPL-3.0',
      );
      final engine = _DownloadEngine(requirement);
      String? askedFor;
      final result = await _check(engine, consent: (label, req) async {
        askedFor = '$label:${req.description}';
        return false;
      });
      expect(askedFor, 'Downloader:stockfish.js 10.0.2');
      expect(engine.initialised, isEmpty,
          reason: 'initialize() would download');
      expect(result.status, PreflightStatus.notInstalled);
      expect(result.pendingDownload, same(requirement));
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.passed);
      expect(result.toJson()['pendingDownload']['license'], 'GPL-3.0');
    });

    test('an approved download proceeds to initialization', () async {
      final engine = _DownloadEngine(EngineDownloadRequirement(
          description: 'model', source: Uri.parse('https://example.org/m')))
        ..ask = (_, __) async => _legal;
      final result = await _check(engine, consent: (_, __) async => true);
      expect(engine.initialised, ['Downloader']);
      expect(result.status, PreflightStatus.passed);
      expect(_step(result, PreflightStep.runtime), PreflightStatus.passed);
    });

    test('a structured initialization failure is reported with its diagnostic',
        () async {
      final engine = ScriptedEngine('Broken')
        ..initFailure = EngineInitializationException(
          engine: 'Broken',
          version: '1.0',
          stage: EngineInitStage.launchProcess,
          platform: 'linux',
          kind: EngineFailureKind.processLaunchFailed,
          exitCode: 127,
          runtimePath: '/home/alice/engines/broken',
          cause: StateError('exec format error'),
        );
      final result = await _check(engine);
      expect(result.status, PreflightStatus.failed);
      expect(_step(result, PreflightStep.initialization), PreflightStatus.failed);
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.passed);
      expect(engine.disposed, isTrue);
      expect(result.diagnostic!['kind'], 'processLaunchFailed');
      expect(result.diagnostic!['stage'], EngineInitStage.launchProcess);
      expect(result.diagnostic!['exitCode'], 127);
      final text = result.toDiagnosticText();
      expect(text, isNot(contains('alice')), reason: 'paths are redacted');
      expect(result.decisiveStep!.step, PreflightStep.initialization);
    });

    test('a missing runtime is notInstalled, not failed', () async {
      final engine = ScriptedEngine('Missing')
        ..initFailure = const EngineStartupFailure(
            EngineFailureKind.runtimeMissing, 'Stockfish is not installed');
      final result = await _check(engine);
      expect(result.status, PreflightStatus.notInstalled);
      expect(result.diagnostic!['kind'], 'runtimeMissing');
    });

    test('initialize() returning while not ready fails readiness', () async {
      final engine = _SilentFailureEngine();
      final result = await _check(engine);
      expect(result.status, PreflightStatus.failed);
      expect(_step(result, PreflightStep.initialization), PreflightStatus.passed);
      expect(_step(result, PreflightStep.readiness), PreflightStatus.failed);
      expect(result.diagnostic!['kind'], 'readinessFailed');
      expect(engine.askedPositions, isEmpty);
    });

    test('a hanging initialization times out and is still cleaned up',
        () async {
      final engine = ScriptedEngine('Hangs')..initGate = Completer<void>();
      final result = await _check(engine,
          checker: const EnginePreflight(
              initTimeout: Duration(milliseconds: 50)));
      expect(result.status, PreflightStatus.timedOut);
      expect(result.diagnostic!['kind'], 'readinessTimeout');
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.passed);
      expect(engine.disposed, isTrue);
    });

    test("an adapter's own timeout keeps its diagnostic, not Preflight's",
        () async {
      final engine = AdapterTimeoutEngine('No uciok');
      final result = await _check(engine);
      expect(result.status, PreflightStatus.timedOut);
      expect(result.diagnostic!['kind'], 'handshakeTimeout');
      expect(result.diagnostic!['stage'], EngineInitStage.handshake);
      expect('${result.diagnostic!['detail'] ?? ''}',
          isNot(contains('Preflight stopped waiting')));
    });

    test('an illegal first move fails the legal-move step', () async {
      final engine = ScriptedEngine('Illegal')..ask = (_, __) async => 'e2e4';
      final result = await _check(engine);
      expect(result.status, PreflightStatus.failed);
      expect(_step(result, PreflightStep.firstSearch), PreflightStatus.passed);
      expect(_step(result, PreflightStep.legalMove), PreflightStatus.failed);
    });

    test('a search that never answers times out and is stopped', () async {
      final engine = ScriptedEngine('Mute')
        ..ask = (_, __) => Completer<String>().future;
      final result = await _check(engine,
          checker: const EnginePreflight(
              moveTime: Duration(milliseconds: 10),
              searchGrace: Duration(milliseconds: 50)));
      expect(result.status, PreflightStatus.timedOut);
      expect(_step(result, PreflightStep.firstSearch), PreflightStatus.timedOut);
      expect(engine.stopCalls, greaterThanOrEqualTo(1));
      expect(engine.disposed, isTrue);
    });

    test('a requested option the engine does not advertise is a warning',
        () async {
      final engine = _FewOptionsEngine()..ask = (_, __) async => _legal;
      final result = await _check(engine, config: _config(hashMb: 64));
      expect(result.status, PreflightStatus.warning);
      expect(_step(result, PreflightStep.options), PreflightStatus.warning);
      expect(result.steps.singleWhere((s) => s.step == PreflightStep.options)
          .detail, contains('Hash'));
    });

    test('a version mismatch or a backend fallback is a warning', () async {
      final mismatch = _ReportingEngine(
          requestedVersion: '16', detectedVersion: '17')
        ..ask = (_, __) async => _legal;
      final first = await _check(mismatch);
      expect(first.status, PreflightStatus.warning);
      expect(_step(first, PreflightStep.identity), PreflightStatus.warning);

      final same = _ReportingEngine(
          requestedVersion: '16', detectedVersion: '16.0')
        ..ask = (_, __) async => _legal;
      expect((await _check(same)).status, PreflightStatus.passed);

      final fallback = _ReportingEngine(
          fallbackReason: 'native library missing',
          effectiveBackend: 'onnx-dart')
        ..ask = (_, __) async => _legal;
      final third = await _check(fallback);
      expect(third.status, PreflightStatus.warning);
      expect(third.identity!.backend, contains('fallback'));
    });

    test('a failing cleanup fails the engine', () async {
      final engine = _BadDisposeEngine()..ask = (_, __) async => _legal;
      final result = await _check(engine);
      expect(result.status, PreflightStatus.failed);
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.failed);
    });

    test('cancellation during initialization stops and cleans up', () async {
      final engine = ScriptedEngine('Slow')..initGate = Completer<void>();
      final cancellation = PreflightCancellation();
      final pending = _check(engine, cancellation: cancellation);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      cancellation.cancel();
      final result = await pending;
      expect(result.status, PreflightStatus.cancelled);
      expect(_step(result, PreflightStep.initialization),
          PreflightStatus.cancelled);
      expect(_step(result, PreflightStep.cleanup), PreflightStatus.passed);
      expect(engine.disposed, isTrue);
    });

    test('cancellation before an engine is built never starts it', () async {
      final engine = ScriptedEngine('Never');
      final cancellation = PreflightCancellation()..cancel();
      final result = await _check(engine, cancellation: cancellation);
      expect(result.status, PreflightStatus.cancelled);
      expect(engine.initialised, isEmpty);
    });

    test('notReached reports an engine instead of omitting it', () {
      final result =
          EnginePreflightResult.notReached(engineId: 'builtin:Y', label: 'Y');
      expect(result.status, PreflightStatus.cancelled);
      expect(result.steps, hasLength(PreflightStep.values.length));
      expect(_step(result, PreflightStep.platform), PreflightStatus.cancelled);
      expect(result.status.admits, isFalse);
    });
  });

  group('preflightStatusForKind', () {
    test('maps the failure taxonomy onto preflight statuses', () {
      expect(preflightStatusForKind(EngineFailureKind.unsupportedPlatform),
          PreflightStatus.unsupported);
      expect(preflightStatusForKind(EngineFailureKind.binaryMissing),
          PreflightStatus.notInstalled);
      expect(preflightStatusForKind(EngineFailureKind.downloadRequired),
          PreflightStatus.notInstalled);
      expect(preflightStatusForKind(EngineFailureKind.handshakeTimeout),
          PreflightStatus.timedOut);
      expect(preflightStatusForKind(EngineFailureKind.cancelled),
          PreflightStatus.cancelled);
      expect(preflightStatusForKind(EngineFailureKind.handshakeFailed),
          PreflightStatus.failed);
      expect(preflightStatusForKind(EngineFailureKind.downloadFailed),
          PreflightStatus.failed);
    });
  });

  group('PreflightGate', () {
    EnginePreflightResult result(PreflightStatus status, BenchmarkConfig config,
            {EngineIdentity? identity, String appBuild = 'test'}) =>
        EnginePreflightResult(
          engineId: (identity ?? _identity).engineId,
          label: 'Engine',
          status: status,
          steps: const [],
          identity: identity ?? _identity,
          binding: PreflightBinding.of(identity ?? _identity, config,
              appBuild: appBuild),
          checkedAt: DateTime.now(),
        );

    Map<String, PreflightBinding?> bindings(BenchmarkConfig config,
            {EngineIdentity? identity, String appBuild = 'test'}) =>
        {
          (identity ?? _identity).engineId: PreflightBinding.of(
              identity ?? _identity, config,
              appBuild: appBuild)
        };

    test('an unchecked engine is not admitted', () {
      final gate = PreflightGate();
      final admission =
          gate.admission([_identity.engineId], bindings(_config()));
      expect(admission.admitted, isEmpty);
      expect(admission.excluded[_identity.engineId], 'not checked');
    });

    test('a passed engine is admitted while nothing changed', () {
      final gate = PreflightGate()..record(result(PreflightStatus.passed, _config()));
      final admission =
          gate.admission([_identity.engineId], bindings(_config()));
      expect(admission.admitted, [_identity.engineId]);
      expect(admission.allAdmitted, isTrue);
    });

    test('changed settings, identity or app build make a result stale', () {
      final gate = PreflightGate()..record(result(PreflightStatus.passed, _config()));
      final settings =
          gate.admission([_identity.engineId], bindings(_config(hashMb: 128)));
      expect(settings.excluded[_identity.engineId],
          contains('benchmark settings changed'));

      final updated = EngineIdentity.forBuiltIn(
          name: 'Engine', engineVersion: '2.0', appBuild: 'test');
      final identity = gate.admission(
          [_identity.engineId], bindings(_config(), identity: updated));
      expect(identity.excluded[_identity.engineId], contains('identity changed'));

      final app = gate.admission(
          [_identity.engineId], bindings(_config(), appBuild: 'next'));
      expect(app.excluded[_identity.engineId], contains('app was updated'));
    });

    test('warnings admit only after review, and a new result resets review',
        () {
      final gate = PreflightGate()
        ..record(result(PreflightStatus.warning, _config()));
      expect(
          gate.admission([_identity.engineId], bindings(_config()))
              .excluded[_identity.engineId],
          'warnings not reviewed');
      gate.acknowledgeWarnings(_identity.engineId);
      expect(gate.admission([_identity.engineId], bindings(_config())).admitted,
          [_identity.engineId]);
      gate.record(result(PreflightStatus.warning, _config()));
      expect(gate.warningsAcknowledged(_identity.engineId), isFalse);
    });

    test('failed, timed out and not installed engines are never admitted', () {
      for (final status in [
        PreflightStatus.failed,
        PreflightStatus.timedOut,
        PreflightStatus.notInstalled,
        PreflightStatus.unsupported,
        PreflightStatus.cancelled,
      ]) {
        final gate = PreflightGate()..record(result(status, _config()));
        gate.acknowledgeWarnings(_identity.engineId);
        final admission =
            gate.admission([_identity.engineId], bindings(_config()));
        expect(admission.admitted, isEmpty, reason: status.id);
        expect(admission.excluded[_identity.engineId], status.id);
      }
    });
  });

  test('a commit-hash suffix is the same release, other suffixes are not', () {
    expect(sameEngineVersion('16', '16'), isTrue);
    expect(sameEngineVersion('16', '16.0'), isTrue);
    expect(sameEngineVersion('1.11.0', '1.11.0-2e4b458f'), isTrue);
    expect(sameEngineVersion('1.11.0', '1.11.0-rc1'), isFalse);
    expect(sameEngineVersion('16', '16-1'), isFalse);
    expect(sameEngineVersion('16', '17'), isFalse);
    expect(sameEngineVersion('1', '10'), isFalse);
  });
}
