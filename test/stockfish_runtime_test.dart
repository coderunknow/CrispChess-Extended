// The built-in Stockfish 16 adapter on desktop: where it finds the executable
// and what it reports when it cannot start.
//
// The reported bug was "Stockfish 16: failed — Bad state: initialize returned
// with state error": the desktop adapter swallowed a failed executable lookup,
// returned normally from initialize() in EngineState.error, and the Engine Lab
// could only say that the contract was violated. These tests drive the real
// adapter against small shell scripts (no Stockfish binary is needed or
// faked as real) and assert that every failure is thrown, structured and
// classified, and that a successful start reports what actually started.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:crispchess/engines/stockfish_engine.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _dir;

String _script(String name, String body, {bool executable = true}) {
  final file = File('${_dir.path}/$name');
  file.writeAsStringSync('#!/bin/bash\n$body\n');
  if (executable) Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

/// A UCI responder that introduces itself as [idName].
String _fakeStockfish({String idName = 'Stockfish 16', String name = 'stockfish'}) =>
    _script(name, '''
while IFS= read -r line; do
  case "\$line" in
    uci)
      echo "id name $idName"
      echo "id author the Stockfish developers (see AUTHORS file)"
      echo "option name Threads type spin default 1 min 1 max 1024"
      echo "option name Hash type spin default 16 min 1 max 33554432"
      echo "uciok"
      ;;
    isready) echo "readyok" ;;
    go*) echo "info depth 1 score cp 20 pv e2e4"; echo "bestmove e2e4" ;;
    quit) exit 0 ;;
  esac
done''');

Future<EngineInitializationException> _failure(StockfishEngine engine) async {
  try {
    await engine.initialize();
  } on EngineInitializationException catch (error) {
    return error;
  }
  fail('initialize() returned normally in state ${engine.state.name}');
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('crisp_sf'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('resolveStockfishRuntime', () {
    test('an explicit path that does not exist is binaryMissing', () async {
      await expectLater(
        resolveStockfishRuntime(explicitPath: '${_dir.path}/nope'),
        throwsA(isA<EngineStartupFailure>().having(
            (e) => e.kind, 'kind', EngineFailureKind.binaryMissing)),
      );
    });

    test('an explicit file that is not executable is permissionDenied',
        () async {
      final path = _script('plain', 'exit 0', executable: false);
      await expectLater(
        resolveStockfishRuntime(explicitPath: path),
        throwsA(isA<EngineStartupFailure>().having(
            (e) => e.kind, 'kind', EngineFailureKind.permissionDenied)),
      );
    });

    test('the environment variable is authoritative, also when wrong',
        () async {
      // A Stockfish on PATH must not hide a broken explicit configuration.
      _fakeStockfish();
      await expectLater(
        resolveStockfishRuntime(environment: {
          kStockfishPathEnvironment: '${_dir.path}/missing',
          'PATH': _dir.path,
        }),
        throwsA(isA<EngineStartupFailure>().having(
            (e) => e.kind, 'kind', EngineFailureKind.binaryMissing)),
      );
      final ok = _script('sf-env', 'exit 0');
      final runtime = await resolveStockfishRuntime(
          environment: {kStockfishPathEnvironment: ok});
      expect(runtime.path, ok);
      expect(runtime.source, 'environment');
    });

    test('PATH is searched for a stockfish executable', () async {
      final path = _fakeStockfish();
      final runtime = await resolveStockfishRuntime(environment: {
        'PATH': '/nonexistent-dir:${_dir.path}',
      });
      expect(runtime.path, path);
      expect(runtime.source, 'path');
    });

    test('nothing found is runtimeMissing with an install hint', () async {
      final wellKnown = stockfishWellKnownLocations(const {})
          .where((p) => File(p).existsSync());
      if (wellKnown.isNotEmpty) {
        markTestSkipped('a Stockfish is installed at a well-known location');
        return;
      }
      await expectLater(
        resolveStockfishRuntime(environment: {'PATH': _dir.path}),
        throwsA(isA<EngineStartupFailure>()
            .having((e) => e.kind, 'kind', EngineFailureKind.runtimeMissing)
            .having((e) => e.message, 'message', contains('Stockfish'))),
      );
    });
  });

  group('stockfishVersionFromIdName', () {
    test('reads the version Stockfish reports', () {
      expect(stockfishVersionFromIdName('Stockfish 16'), '16');
      expect(stockfishVersionFromIdName('Stockfish 16.1'), '16.1');
      expect(stockfishVersionFromIdName('Stockfish dev-20231105-1a2b3c'),
          'dev-20231105-1a2b3c');
      expect(stockfishVersionFromIdName('Stockfish.js 10.0.2'), '10.0.2');
      expect(stockfishVersionFromIdName('Komodo 14'), isNull);
    });
  });

  group('StockfishEngine (native)', () {
    test('runtimeDigest names the executable without starting it', () async {
      final path = _fakeStockfish();
      final engine = StockfishEngine(executablePath: path);
      addTearDown(engine.dispose);
      final first = await engine.runtimeDigest();
      expect(first, isNotNull);
      expect(first, isNot(contains(_dir.path)));
      expect(engine.state, EngineState.idle, reason: 'nothing was started');
      final again = StockfishEngine(executablePath: path);
      addTearDown(again.dispose);
      expect(await again.runtimeDigest(), first);

      // Same contents somewhere else: a different executable.
      final copy = File(path).copySync('${_dir.path}/stockfish-copy');
      Process.runSync('chmod', ['+x', copy.path]);
      final elsewhere = StockfishEngine(executablePath: copy.path);
      addTearDown(elsewhere.dispose);
      expect(await elsewhere.runtimeDigest(), isNot(first));

      // Same path, replaced contents.
      File(path).writeAsStringSync('# replaced\n', mode: FileMode.append);
      expect(await engine.runtimeDigest(), isNot(first));
    });

    test('runtimeDigest is null when no executable is found', () async {
      final engine = StockfishEngine(executablePath: '${_dir.path}/missing');
      addTearDown(engine.dispose);
      expect(await engine.runtimeDigest(), isNull);
      expect(engine.state, EngineState.idle);
    });

    test('a missing executable fails initialize() instead of returning',
        () async {
      final engine = StockfishEngine(executablePath: '${_dir.path}/stockfish');
      addTearDown(engine.dispose);
      final failure = await _failure(engine);
      expect(failure.kind, EngineFailureKind.binaryMissing);
      expect(failure.stage, EngineInitStage.resolveRuntime);
      expect(failure.requestedVersion, '16');
      expect(failure.backend, 'native-process');
      expect(engine.state, EngineState.error);
      expect(engine.initializationError, same(failure));
      expect(failure.toString(), isNot(contains('initialize returned')));
    });

    test('a resolver failure keeps its kind (runtimeMissing)', () async {
      final engine = StockfishEngine(
        resolver: () async => throw const EngineStartupFailure(
            EngineFailureKind.runtimeMissing, 'Stockfish is not installed'),
      );
      addTearDown(engine.dispose);
      final failure = await _failure(engine);
      expect(failure.kind, EngineFailureKind.runtimeMissing);
      expect(failure.summary, contains('not installed'));
    });

    test('starts a UCI engine and reports the version it detected', () async {
      final engine = StockfishEngine(executablePath: _fakeStockfish());
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(engine.state, EngineState.ready);
      expect(engine.detectedVersion, '16');
      expect(engine.requestedVersion, '16');
      expect(engine.version, '16');
      expect(engine.effectiveBackend, 'native-process');
      expect(engine.advertisesOption('Hash'), isTrue);
      final move = await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 20));
      expect(move, 'e2e4');
    });

    test('a different Stockfish version is reported, not relabelled',
        () async {
      final engine = StockfishEngine(
          executablePath: _fakeStockfish(idName: 'Stockfish 17'));
      addTearDown(engine.dispose);
      await engine.initialize();
      expect(engine.detectedVersion, '17');
      expect(engine.requestedVersion, '16');
      expect(engine.version, '17');
    });

    test('a process that exits during the handshake reports exit code and '
        'stderr', () async {
      final path = _script('dying', 'echo "illegal instruction" >&2; exit 3');
      final engine = StockfishEngine(executablePath: path);
      addTearDown(engine.dispose);
      final failure = await _failure(engine);
      expect(failure.kind, EngineFailureKind.processExited);
      expect(failure.exitCode, 3);
      expect(failure.stderrTail.join('\n'), contains('illegal instruction'));
      expect(engine.state, EngineState.error);
    });

    test('an executable that never says uciok times out in the handshake',
        () async {
      final path = _script('mute', 'while IFS= read -r line; do :; done');
      final engine = StockfishEngine(
        executablePath: path,
        handshakeTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(engine.dispose);
      final failure = await _failure(engine);
      expect(failure.kind, EngineFailureKind.handshakeTimeout);
      expect(failure.stage, EngineInitStage.handshake);
    });

    test('a retry after a failure starts a fresh process and can succeed',
        () async {
      var attempts = 0;
      final good = _fakeStockfish();
      final engine = StockfishEngine(resolver: () async {
        attempts++;
        if (attempts == 1) {
          throw const EngineStartupFailure(
              EngineFailureKind.runtimeMissing, 'not yet');
        }
        return StockfishRuntime(good, 'explicit');
      });
      addTearDown(engine.dispose);
      await _failure(engine);
      await engine.initialize();
      expect(engine.state, EngineState.ready);
      expect(engine.initializationError, isNull);
      expect(attempts, 2);
    });

    test('concurrent initialize() calls share one attempt', () async {
      var attempts = 0;
      final good = _fakeStockfish();
      final engine = StockfishEngine(resolver: () async {
        attempts++;
        return StockfishRuntime(good, 'explicit');
      });
      addTearDown(engine.dispose);
      await Future.wait([engine.initialize(), engine.initialize()]);
      expect(attempts, 1);
      expect(engine.state, EngineState.ready);
    });

    test('dispose during initialization never ends in ready', () async {
      final good = _fakeStockfish();
      final engine = StockfishEngine(resolver: () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return StockfishRuntime(good, 'explicit');
      });
      final pending = engine.initialize();
      engine.dispose();
      await expectLater(
        pending,
        throwsA(isA<EngineInitializationException>().having(
            (e) => e.kind, 'kind', EngineFailureKind.cancelled)),
      );
      expect(engine.state, isNot(EngineState.ready));
    });
  });
}
