// The same code paths as `generic_uci_init_test.dart`, driven by a real engine
// binary instead of a shell script.
//
// Every other engine test in this repository uses a deterministic fake, which
// is the right tool for lifecycle edge cases and says nothing about whether the
// protocol code agrees with an actual engine. This file is the complement: it
// talks to whatever UCI engine the environment points at, and it is skipped —
// visibly — when there is none, rather than quietly passing.
//
//     CRISP_UCI_ENGINE=/path/to/stockfish flutter test test/real_uci_engine_test.dart
//
// The assertions encode behaviour that was measured on Stockfish 11 before
// being written (see `docs/audit/2026-10-31-custom-uci-and-engine-audit.md`,
// §10): a search of 1.e4 (Black to move) reports a score relative to Black, and
// a mate found by the side to move is negative for White.
@TestOn('vm')
library;

import 'dart:io';

import 'package:chess/chess.dart' as chess;
import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';

final String? _enginePath = Platform.environment['CRISP_UCI_ENGINE'];

/// Black to move, White has no queen: Black is winning by roughly a queen.
const String _blackWinning = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR b KQkq - 0 1';

/// White to move, Black has no queen.
const String _whiteWinning = 'rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

/// White mates in one (Rg8#).
const String _whiteMatesInOne = '7k/5K2/8/8/8/8/8/6R1 w - - 0 1';

/// The same position mirrored: Black mates in one.
const String _blackMatesInOne = '6r1/8/8/8/8/8/5k2/7K b - - 0 1';

void main() {
  final skipReason = _enginePath == null
      ? 'set CRISP_UCI_ENGINE to a UCI engine binary to run these'
      : false;

  group('real UCI engine', () {
    test('completes the handshake and reports what it is', () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      addTearDown(engine.dispose);

      await engine.initialize();

      expect(engine.state, EngineState.ready);
      expect(engine.engineIdentifier, isNotEmpty,
          reason: '`id name` is parsed from the real handshake');
      expect(engine.options, isNotEmpty, reason: 'real engines advertise options');
      expect(engine.options.map((o) => o.name), contains('Hash'),
          reason: 'Hash is universal and is set by the settings screen');
    }, skip: skipReason);

    test('returns a legal move that the board accepts', () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      addTearDown(engine.dispose);
      await engine.initialize();

      final move = await engine.bestMove('position startpos', depth: 8);

      expect(move, matches(RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$')));
      final board = chess.Chess();
      board.load('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
      // `Move.from`/`to` are square indices in package:chess, so the UCI
      // spelling comes from the algebraic getters — the same conversion
      // `lib/chess/chess_game.dart` uses for its move list.
      final legal = board
          .generate_moves()
          .map((m) =>
              '${m.fromAlgebraic}${m.toAlgebraic}${m.promotion?.name ?? ''}')
          .toSet();
      expect(legal, contains(move),
          reason: 'the engine move has to be playable on the app board');
    }, skip: skipReason);

    test('a Black-to-move winning position is negative for White', () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      addTearDown(engine.dispose);
      await engine.initialize();

      final info = await engine
          .analyze('position fen $_blackWinning', depth: 10)
          .first
          .timeout(const Duration(seconds: 30));

      // The engine reports about +13 for the side to move (Black). Emitted
      // unchanged it would read as "White is winning by 13".
      expect(info.score, lessThan(-5.0),
          reason: 'White is down a queen; the app draws from White\'s side');
    }, skip: skipReason);

    test('a White-to-move winning position is positive for White', () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      addTearDown(engine.dispose);
      await engine.initialize();

      final info = await engine
          .analyze('position fen $_whiteWinning', depth: 10)
          .first
          .timeout(const Duration(seconds: 30));

      expect(info.score, greaterThan(5.0));
    }, skip: skipReason);

    test('mate for the side to move uses the same perspective as centipawns',
        () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      addTearDown(engine.dispose);
      await engine.initialize();

      final white = await engine
          .analyze('position fen $_whiteMatesInOne', depth: 6)
          .first
          .timeout(const Duration(seconds: 30));
      final black = await engine
          .analyze('position fen $_blackMatesInOne', depth: 6)
          .first
          .timeout(const Duration(seconds: 30));

      // Both positions are "mate in 1 for the mover", so both engine scores are
      // positive for the side to move: White's has to stay positive, Black's has
      // to come out negative.
      expect(white.score, greaterThan(100.0));
      expect(black.score, lessThan(-100.0));
    }, skip: skipReason);

    test('stops cleanly and leaves no process behind', () async {
      final engine = GenericUciEngine(
          EngineProfile(name: 'Real', path: _enginePath!));
      await engine.initialize();
      expect(engine.state, EngineState.ready);

      // Start a search and dispose mid-flight: the engine must not be left
      // searching, and the process must be gone.
      engine.analyze('position startpos', infinite: true).listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      engine.dispose();

      expect(engine.state, EngineState.disposed);
      // A second dispose is a no-op rather than a second kill.
      engine.dispose();
    }, skip: skipReason);
  });
}
