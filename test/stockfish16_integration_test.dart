// Genuine Stockfish 16 through the app's own built-in Stockfish adapter.
//
// Runs only against a real binary named by CRISPCHESS_STOCKFISH_PATH (CI
// builds official Stockfish sf_16 from source at a pinned commit, see the
// "Real Stockfish 16" job in .github/workflows/ci.yml). Without it the tests
// are skipped visibly — and with CRISP_STOCKFISH16_REQUIRED=1 a missing binary
// is a failure — so a skipped run can never be mistaken for a pass.
@TestOn('vm')
library;

import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/engine_preflight.dart';
import 'package:crispchess/bench/game_player.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/stockfish_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bench_harness.dart';

final String? _path = Platform.environment[kStockfishPathEnvironment];
final bool _required =
    Platform.environment['CRISP_STOCKFISH16_REQUIRED'] == '1';

void main() {
  final skip = _path == null
      ? 'NOT RUN: set $kStockfishPathEnvironment to a Stockfish 16 binary'
      : false;

  test('a Stockfish 16 binary is present when the job requires one', () {
    expect(_path, isNotNull,
        reason: 'CRISP_STOCKFISH16_REQUIRED=1 but $kStockfishPathEnvironment '
            'is not set');
    expect(File(_path!).existsSync(), isTrue);
  }, skip: _required ? false : 'CRISP_STOCKFISH16_REQUIRED is not set');

  test('the built-in adapter finds, starts and identifies Stockfish 16',
      () async {
    // No explicit path: the adapter's own resolver reads the environment
    // variable, which is the path a user configuration takes.
    final engine = StockfishEngine();
    addTearDown(engine.dispose);
    await engine.initialize();
    expect(engine.state, EngineState.ready);
    expect(engine.runtime?.source, 'environment');
    expect(engine.detectedName, startsWith('Stockfish 16'));
    expect(engine.detectedVersion, '16');
    expect(engine.requestedVersion, '16');
    expect(engine.advertisesOption('Hash'), isTrue);
    expect(engine.advertisesOption('Threads'), isTrue);

    const fen =
        'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3';
    final move = await engine.bestMove('position fen $fen',
        moveTime: const Duration(milliseconds: 300));
    final board = chess.Chess()..load(fen);
    expect(applyUciMove(board, move), isTrue,
        reason: 'bestmove $move must be legal');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('Engine Preflight passes Stockfish 16 on every step', () async {
    final identity = EngineIdentity.forBuiltIn(
        name: 'Stockfish', engineVersion: '16', appBuild: 'ci');
    final result = await const EnginePreflight().check(
      engineId: identity.engineId,
      label: 'Stockfish',
      available: true,
      build: StockfishEngine.new,
      identity: identity,
      config: benchConfig().copyWith(threads: 1, hashMb: 16),
      appBuild: 'ci',
      consent: (_, __) async => false,
    );
    expect(result.status, PreflightStatus.passed,
        reason: result.toDiagnosticText());
    expect(result.identity!.engineVersion, '16');
    // ignore: avoid_print
    print(result.toDiagnosticText());
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('initialize, search and dispose repeatedly without a leak', () async {
    for (var cycle = 0; cycle < 5; cycle++) {
      final engine = StockfishEngine();
      await engine.initialize();
      final move = await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 50));
      expect(move, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
      engine.dispose();
      expect(engine.state, EngineState.disposed);
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
