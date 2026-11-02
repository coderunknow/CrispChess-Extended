// The shared initialization contract every adapter now runs under
// (EngineInitCoordinator): initialize() completes normally only when the
// engine is ready, every failure is thrown as a structured
// EngineInitializationException, concurrent calls share one attempt, a retry
// after a failure starts fresh, dispose during a start can never end in
// `ready`, and the diagnostic is redacted for anything stored or exported.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:crispchess/engines/engine_slot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

EngineInitCoordinator _coordinator(ValueNotifier<EngineState> state) =>
    EngineInitCoordinator(state);

Future<void> _run(
  EngineInitCoordinator init,
  Future<void> Function(EngineInitScope scope) body, {
  FutureOr<void> Function()? cleanup,
  bool retryable = true,
}) =>
    init.run(
      engine: 'Test',
      version: '1',
      requestedVersion: '1',
      backend: 'native-process',
      body: body,
      cleanup: cleanup,
      retryable: retryable,
    );

void main() {
  group('EngineInitCoordinator', () {
    test('success sets ready and records the effective backend', () async {
      final state = ValueNotifier(EngineState.idle);
      final init = _coordinator(state);
      await _run(init, (scope) async {
        scope.backend = 'onnx-dart';
        scope.fallbackReason = 'native library missing';
        scope.detectedVersion = '1.1';
      });
      expect(state.value, EngineState.ready);
      expect(init.effectiveBackend, 'onnx-dart');
      expect(init.fallbackReason, 'native library missing');
      expect(init.detectedVersion, '1.1');
      expect(init.lastFailure, isNull);
    });

    test('a failure throws a structured exception and leaves error', () async {
      final state = ValueNotifier(EngineState.idle);
      final init = _coordinator(state);
      var cleanedUp = 0;
      Object? thrown;
      try {
        await _run(init, (scope) async {
          scope.stage = EngineInitStage.launchProcess;
          scope.runtimePath = '/home/alice/bin/engine';
          scope.exitCode = 126;
          scope.stderrTail = ['/home/alice/bin/engine: Permission denied'];
          throw StateError('Permission denied');
        }, cleanup: () => cleanedUp++);
      } catch (error) {
        thrown = error;
      }
      expect(thrown, isA<EngineInitializationException>());
      final failure = thrown! as EngineInitializationException;
      expect(failure.kind, EngineFailureKind.permissionDenied);
      expect(failure.stage, EngineInitStage.launchProcess);
      expect(failure.exitCode, 126);
      expect(failure.cause, isA<StateError>(), reason: 'original cause kept');
      expect(failure.elapsedMicros, isNotNull);
      expect(state.value, EngineState.error);
      expect(init.lastFailure, same(failure));
      expect(cleanedUp, 1);
      final json = jsonEncode(failure.toJson());
      expect(json, isNot(contains('alice')));
      expect(failure.toJson()['runtimePath'], '…/engine');
      expect(failure.toJson(redact: false)['runtimePath'],
          '/home/alice/bin/engine');
      expect(failure.summary, contains('permissionDenied'));
      expect(failure.summary, isNot(contains('Bad state: initialize returned')));
    });

    test('an EngineStartupFailure keeps its kind and message', () async {
      final init = _coordinator(ValueNotifier(EngineState.idle));
      await expectLater(
        _run(init, (scope) async {
          throw const EngineStartupFailure(
              EngineFailureKind.dependencyMissing, 'VCRUNTIME140.dll missing');
        }),
        throwsA(isA<EngineInitializationException>()
            .having((e) => e.kind, 'kind', EngineFailureKind.dependencyMissing)
            .having((e) => e.detail, 'detail', contains('VCRUNTIME140'))),
      );
    });

    test('concurrent calls share one attempt', () async {
      final init = _coordinator(ValueNotifier(EngineState.idle));
      final gate = Completer<void>();
      var bodies = 0;
      Future<void> body(EngineInitScope scope) async {
        bodies++;
        await gate.future;
      }

      final first = _run(init, body);
      final second = _run(init, body);
      expect(init.isInitializing, isTrue);
      gate.complete();
      await Future.wait([first, second]);
      expect(bodies, 1);
    });

    test('a ready engine returns at once without running the body again',
        () async {
      final init = _coordinator(ValueNotifier(EngineState.idle));
      var bodies = 0;
      await _run(init, (_) async => bodies++);
      await _run(init, (_) async => bodies++);
      expect(bodies, 1);
    });

    test('a retry after a failure starts a fresh attempt', () async {
      final state = ValueNotifier(EngineState.idle);
      final init = _coordinator(state);
      var attempt = 0;
      Future<void> body(EngineInitScope scope) async {
        attempt++;
        if (attempt == 1) throw StateError('first try fails');
      }

      await expectLater(_run(init, body), throwsA(anything));
      await _run(init, body);
      expect(attempt, 2);
      expect(state.value, EngineState.ready);
      expect(init.lastFailure, isNull);
    });

    test('a non-retryable failure is returned again', () async {
      final init = _coordinator(ValueNotifier(EngineState.idle));
      var attempt = 0;
      Future<void> body(EngineInitScope scope) async {
        attempt++;
        throw StateError('broken');
      }

      await expectLater(_run(init, body, retryable: false), throwsA(anything));
      await expectLater(_run(init, body, retryable: false),
          throwsA(isA<EngineInitializationException>()));
      expect(attempt, 1);
    });

    test('dispose during a start ends cancelled, never ready', () async {
      final state = ValueNotifier(EngineState.idle);
      final init = _coordinator(state);
      final gate = Completer<void>();
      final pending = _run(init, (scope) async {
        await gate.future;
        scope.checkCancelled();
      });
      init.markDisposed();
      state.value = EngineState.disposed;
      gate.complete();
      await expectLater(
        pending,
        throwsA(isA<EngineInitializationException>().having(
            (e) => e.kind, 'kind', EngineFailureKind.cancelled)),
      );
      expect(state.value, EngineState.disposed);
      await expectLater(_run(init, (_) async {}),
          throwsA(isA<EngineInitializationException>()));
    });

    test('a body that returns after dispose without checking is cancelled',
        () async {
      final state = ValueNotifier(EngineState.idle);
      final init = _coordinator(state);
      final gate = Completer<void>();
      final pending = _run(init, (_) => gate.future);
      init.markDisposed();
      gate.complete();
      await expectLater(pending, throwsA(isA<EngineInitializationException>()));
      expect(state.value, isNot(EngineState.ready));
    });
  });

  group('requireEngineReady and engineFailureOf', () {
    test('a normal return while not ready is a readinessFailed violation', () {
      final engine = ScriptedEngine('Lazy');
      expect(
        () => requireEngineReady(engine, platform: 'linux'),
        throwsA(isA<EngineInitializationException>()
            .having((e) => e.kind, 'kind', EngineFailureKind.readinessFailed)
            .having((e) => e.stage, 'stage', EngineInitStage.verifyReady)),
      );
    });

    test('an unstructured error is wrapped and classified', () {
      final failure = engineFailureOf(
          ScriptedEngine('X'), TimeoutException('no answer'), null,
          engineId: 'builtin:X');
      expect(failure.engineId, 'builtin:X');
      expect(failure.kind, EngineFailureKind.readinessTimeout);
    });

    test('classification by stage', () {
      expect(classifyEngineFailure(EngineInitStage.handshake,
          TimeoutException('x')), EngineFailureKind.handshakeTimeout);
      expect(classifyEngineFailure(EngineInitStage.handshake, StateError('x')),
          EngineFailureKind.handshakeFailed);
      expect(classifyEngineFailure(EngineInitStage.readiness,
          TimeoutException('x')), EngineFailureKind.readinessTimeout);
      expect(classifyEngineFailure(EngineInitStage.download, StateError('x')),
          EngineFailureKind.downloadFailed);
      expect(classifyEngineFailure(EngineInitStage.loadLibrary, StateError('x')),
          EngineFailureKind.dependencyMissing);
      expect(classifyEngineFailure(EngineInitStage.loadBackend, StateError('x')),
          EngineFailureKind.backendInitializationFailed);
      expect(classifyEngineFailure(EngineInitStage.resolveRuntime,
          StateError('x')), EngineFailureKind.runtimeMissing);
      expect(classifyEngineFailure(EngineInitStage.initialize,
          UnsupportedError('no FFI on the web')),
          EngineFailureKind.unsupportedPlatform);
    });

    test('every failure kind round-trips through its id', () {
      for (final kind in EngineFailureKind.values) {
        expect(EngineFailureKind.fromId(kind.id), kind);
        expect(kind.explanation, isNotEmpty);
      }
    });
  });

  group('redaction', () {
    test('home directories and app containers are removed', () {
      expect(redactPersonalPaths('/home/alice/x and /Users/bob/y'),
          '~/x and ~/y');
      expect(redactPersonalPaths(r'C:\Users\carol\sf.exe'), r'~\sf.exe');
      expect(redactPath('/opt/engines/stockfish'), '…/stockfish');
    });
  });

  group('EngineSlot', () {
    test('concurrent get() calls join one start', () async {
      final engine = ScriptedEngine('Slot')..initGate = Completer<void>();
      var built = 0;
      final slot = EngineSlot(() {
        built++;
        return engine;
      });
      final first = slot.get();
      final second = slot.get();
      await Future<void>.delayed(Duration.zero);
      engine.initGate!.complete();
      final engines = await Future.wait([first, second]);
      expect(identical(engines[0], engines[1]), isTrue);
      expect(engine.initialised, ['Slot'], reason: 'initialized once');
      expect(built, 1);
      slot.dispose();
    });

    test('a failed start is rethrown, structured, to every waiter', () async {
      final engine = ScriptedEngine('Broken')
        ..initGate = Completer<void>()
        ..initFailure = const EngineStartupFailure(
            EngineFailureKind.binaryMissing, 'gone');
      final slot = EngineSlot(() => engine);
      final first = slot.get();
      final second = slot.get();
      engine.initGate!.complete();
      await expectLater(first, throwsA(isA<EngineStartupFailure>()));
      await expectLater(second, throwsA(isA<EngineStartupFailure>()));
      slot.dispose();
    });
  });

  group('stored results', () {
    test('EngineRunStatus omits a missing diagnostic (old checksums hold)', () {
      const status = EngineRunStatus(status: 'completed', gamesCompleted: 4);
      expect(status.toJson().containsKey('diagnostic'), isFalse);
      expect(EngineRunStatus.fromJson(status.toJson()).diagnostic, isNull);
    });

    test('EngineRunStatus keeps a diagnostic and its failure kind', () {
      const status = EngineRunStatus(
        status: 'failed',
        reason: 'Stockfish could not start',
        diagnostic: {'kind': 'runtimeMissing', 'stage': 'resolve-runtime'},
      );
      final restored = EngineRunStatus.fromJson(
          jsonDecode(jsonEncode(status.toJson())) as Map<String, dynamic>);
      expect(restored.failureKind, 'runtimeMissing');
      expect(restored.isFailure, isTrue);
    });

    test('withRuntime records the detected version and a fallback', () {
      final identity = EngineIdentity.forBuiltIn(
          name: 'Stockfish', engineVersion: '16', appBuild: 'x');
      final same = identity.withRuntime(
          detectedVersion: '16', backend: 'native-process');
      expect(same.identityKey, identity.identityKey);

      final newer = identity.withRuntime(detectedVersion: '17');
      expect(newer.engineVersion, '17');
      expect(newer.identityKey, isNot(identity.identityKey));

      final fellBack = identity.withRuntime(
          backend: 'onnx-dart',
          fallbackReason: 'could not load /home/alice/lib/onnxruntime.so');
      expect(fellBack.backend, 'onnx-dart (fallback)');
      expect(fellBack.fallbackReason, isNot(contains('alice')));
      expect(fellBack.identityKey, isNot(identity.identityKey));
      final restored = EngineIdentity.fromJson(
          jsonDecode(jsonEncode(fellBack.toJson())) as Map<String, dynamic>);
      expect(restored.fallbackReason, fellBack.fallbackReason);
      expect(restored.backend, fellBack.backend);
    });

    test('an identity without a fallback does not export the key', () {
      final identity = EngineIdentity.forBuiltIn(
          name: 'Stockfish', engineVersion: '16', appBuild: 'x');
      expect(identity.toJson().containsKey('fallbackReason'), isFalse);
    });
  });
}
