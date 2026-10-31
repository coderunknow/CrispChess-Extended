/// The single engine-versus-engine game loop.
///
/// Before this file there were two loops — `EngineMatchService._playGame` for
/// the match screen and a copy inside the CI harness — and both treated "the
/// game ended without checkmate" as a draw. That is how an engine that threw
/// an exception, returned an illegal move or died mid-search was recorded as a
/// well-earned half point.
///
/// Everything the benchmark needs to be honest about a game lives here:
///
///  * a legal-move check on every engine answer (an illegal move is a forfeit,
///    not a break out of the loop);
///  * failure classification (timeout, crash, protocol error);
///  * per-move wall-clock latency and, where the engine reports it, node and
///    depth counters;
///  * an explicit outcome — win, loss, draw, forfeit, adjudicated, aborted,
///    cancelled — so `1/2-1/2` is never a catch-all.
library;

import 'dart:async';

import 'package:chess/chess.dart' as chess;

import '../engines/chess_engine.dart' show EngineProcessDiedException;
import '../engines/search_telemetry.dart';
import 'game_record.dart';
import 'opening_suite.dart';

/// One move, as measured.
class EngineMove {
  /// The move in UCI form.
  final String uci;

  /// Wall-clock time the engine took, measured around the move request.
  final int micros;

  /// Nodes the engine reported for this move, when it reports them.
  final int? nodes;

  /// Depth the engine reported.
  final int? depth;

  /// Nodes per second the engine reported (or its last sample).
  final int? nps;

  const EngineMove(
    this.uci,
    this.micros, {
    this.nodes,
    this.depth,
    this.nps,
  });

  int get millis => (micros / 1000).round();
}

/// Asks an engine for a move in [positionCommand].
///
/// The whole benchmark talks to engines through this, so a real engine, a
/// wrapper that adds telemetry and a test double are interchangeable.
typedef MoveRequester = Future<EngineMove> Function(
  String positionCommand,
  int? depth,
  Duration? moveTime,
);

/// Thrown by a move requester when the engine failed in a way the game loop has
/// to classify rather than guess at.
class EngineFailure implements Exception {
  final ForfeitReason reason;
  final String message;

  const EngineFailure(this.reason, this.message);

  @override
  String toString() => 'EngineFailure(${reason.id}): $message';
}

/// Wraps a [MoveRequester] so the engine's own search counters are captured.
///
/// [statsOf] is null for engines that do not implement `SearchTelemetry`; the
/// move is then measured by wall clock only and the report says the counters
/// are unavailable.
MoveRequester measuredRequester(
  Future<String> Function(String positionCommand) askMove, {
  SearchStatistics Function()? statsOf,
}) =>
    (positionCommand, depth, moveTime) async {
      final stopwatch = Stopwatch()..start();
      try {
        final uci = await askMove(positionCommand);
        stopwatch.stop();
        final stats = statsOf?.call() ?? SearchStatistics.none;
        return EngineMove(
          uci,
          stopwatch.elapsedMicroseconds,
          nodes: stats.nodes,
          depth: stats.depth,
          nps: stats.nps,
        );
      } catch (e) {
        stopwatch.stop();
        throw classifyEngineFailure(e);
      }
    };

/// Maps an exception from an engine to the reason a game is forfeited.
EngineFailure classifyEngineFailure(Object error) {
  if (error is EngineFailure) return error;
  if (error is TimeoutException) {
    return EngineFailure(ForfeitReason.timeOut, error.message ?? '$error');
  }
  if (error is EngineProcessDiedException) {
    return EngineFailure(ForfeitReason.engineCrash, error.toString());
  }
  final text = error.toString();
  if (error is StateError) {
    // "Not initialized", "Engine disposed": the harness asked an engine that is
    // not running. Reported as a protocol error, not as a draw.
    return EngineFailure(ForfeitReason.protocolError, text);
  }
  return EngineFailure(ForfeitReason.engineError, text);
}

/// Result of playing one game.
class PlayedGame {
  final BenchGame game;

  const PlayedGame(this.game);
}

/// Plays one game between two engines.
///
/// [cancelled] is polled between moves; when it returns true the game stops as
/// [GameOutcome.cancelled] and is not rated. [onMove] receives the position
/// after every move, for live progress.
Future<BenchGame> playBenchGame({
  required int index,
  required String whiteId,
  required String blackId,
  required String whiteLabel,
  required String blackLabel,
  required MoveRequester whiteMove,
  required MoveRequester blackMove,
  required Opening opening,
  required int plyCap,
  int? depth,
  Duration? moveTime,
  bool warmUp = false,
  bool Function()? cancelled,
  void Function(String fen, String san, bool whiteToMove)? onMove,
}) async {
  final board = chess.Chess();
  final startFen = opening.rootFen;
  final played = <String>[];

  if (opening.fen != null && !board.load(opening.fen!)) {
    return _unplayable(
      index: index,
      whiteId: whiteId,
      blackId: blackId,
      whiteLabel: whiteLabel,
      blackLabel: blackLabel,
      opening: opening,
      startFen: startFen,
      detail: 'The opening FEN could not be loaded: ${opening.fen}',
      warmUp: warmUp,
    );
  }

  for (final move in opening.moves) {
    if (!applyUciMove(board, move)) {
      return _unplayable(
        index: index,
        whiteId: whiteId,
        blackId: blackId,
        whiteLabel: whiteLabel,
        blackLabel: blackLabel,
        opening: opening,
        startFen: startFen,
        detail: 'The opening line is not legal at move "$move".',
        warmUp: warmUp,
      );
    }
    played.add(move);
  }

  var white = SideTelemetry.none;
  var black = SideTelemetry.none;
  final positionCounts = <String, int>{};
  _countPosition(positionCounts, board.fen);

  var outcome = GameOutcome.adjudicated;
  var forfeitReason = ForfeitReason.none;
  String? forfeitedBy;
  String? detail;
  final stopwatch = Stopwatch()..start();
  var plies = played.length;

  while (true) {
    if (cancelled?.call() ?? false) {
      outcome = GameOutcome.cancelled;
      detail = 'Stopped by the user.';
      break;
    }
    if (board.game_over) {
      final terminal = _terminalOutcome(board);
      outcome = terminal;
      detail = terminal == GameOutcome.draw ? _drawReason(board, positionCounts) : null;
      break;
    }
    if (plies >= plyCap) {
      outcome = GameOutcome.adjudicated;
      detail = 'Adjudicated at the $plyCap-ply limit.';
      break;
    }

    final isWhite = _whiteToMove(board.fen);
    final requester = isWhite ? whiteMove : blackMove;
    final position = _positionCommand(opening, played);

    EngineMove move;
    try {
      move = await requester(position, depth, moveTime);
    } on EngineFailure catch (failure) {
      outcome = GameOutcome.forfeit;
      forfeitReason = failure.reason;
      forfeitedBy = isWhite ? whiteId : blackId;
      detail = failure.message;
      break;
    } catch (error) {
      final failure = classifyEngineFailure(error);
      outcome = GameOutcome.forfeit;
      forfeitReason = failure.reason;
      forfeitedBy = isWhite ? whiteId : blackId;
      detail = failure.message;
      break;
    }

    final uci = move.uci.trim().toLowerCase();
    if (uci.isEmpty || uci == '(none)' || uci == '0000') {
      // A UCI engine that answers `bestmove (none)` in a position that is not
      // over has failed the protocol, not resigned.
      outcome = GameOutcome.forfeit;
      forfeitReason = ForfeitReason.noMoveReturned;
      forfeitedBy = isWhite ? whiteId : blackId;
      detail = 'Engine answered with no move.';
      break;
    }
    if (!applyUciMove(board, uci)) {
      outcome = GameOutcome.forfeit;
      forfeitReason = ForfeitReason.illegalMove;
      forfeitedBy = isWhite ? whiteId : blackId;
      detail = 'Illegal move "$uci" in ${board.fen}';
      break;
    }

    played.add(uci);
    plies++;
    if (isWhite) {
      white = white.plusMove(move.millis,
          nodes: move.nodes, depth: move.depth, npsSample: move.nps);
    } else {
      black = black.plusMove(move.millis,
          nodes: move.nodes, depth: move.depth, npsSample: move.nps);
    }
    _countPosition(positionCounts, board.fen);
    onMove?.call(board.fen, _lastSan(board, uci), !isWhite);
  }

  stopwatch.stop();
  return BenchGame(
    index: index,
    whiteId: whiteId,
    blackId: blackId,
    whiteLabel: whiteLabel,
    blackLabel: blackLabel,
    openingId: opening.id,
    openingName: opening.name,
    startFen: opening.fen == null ? '' : startFen,
    moves: played,
    movetext: _movetext(board),
    outcome: outcome,
    forfeitReason: forfeitReason,
    forfeitedBy: forfeitedBy,
    detail: detail,
    white: white,
    black: black,
    durationMillis: stopwatch.elapsedMilliseconds,
    warmUp: warmUp,
  );
}

BenchGame _unplayable({
  required int index,
  required String whiteId,
  required String blackId,
  required String whiteLabel,
  required String blackLabel,
  required Opening opening,
  required String startFen,
  required String detail,
  required bool warmUp,
}) =>
    BenchGame(
      index: index,
      whiteId: whiteId,
      blackId: blackId,
      whiteLabel: whiteLabel,
      blackLabel: blackLabel,
      openingId: opening.id,
      openingName: opening.name,
      startFen: opening.fen == null ? '' : startFen,
      moves: const [],
      movetext: '',
      outcome: GameOutcome.aborted,
      detail: detail,
      warmUp: warmUp,
    );

/// Plays a UCI move on [board]; false when the move is not legal.
bool applyUciMove(chess.Chess board, String uci) {
  final clean = uci.trim().toLowerCase();
  if (clean.length < 4) return false;
  final from = clean.substring(0, 2);
  final to = clean.substring(2, 4);
  final promotion = clean.length > 4 ? clean.substring(4, 5) : null;
  try {
    final ok = board.move({
      'from': from,
      'to': to,
      if (promotion != null) 'promotion': promotion,
    });
    return ok == true;
  } catch (_) {
    // The board library rejects some malformed input by throwing; an engine
    // that sent it has still made an illegal move.
    return false;
  }
}

String _positionCommand(Opening opening, List<String> played) {
  final prefix = opening.positionPrefix;
  if (played.isEmpty) return prefix;
  return '$prefix moves ${played.join(' ')}';
}

bool _whiteToMove(String fen) {
  final fields = fen.split(' ');
  return fields.length < 2 || fields[1] != 'b';
}

GameOutcome _terminalOutcome(chess.Chess board) {
  if (board.in_checkmate) {
    // The side to move has been mated.
    return _whiteToMove(board.fen) ? GameOutcome.blackWin : GameOutcome.whiteWin;
  }
  return GameOutcome.draw;
}

String _drawReason(chess.Chess board, Map<String, int> positionCounts) {
  if (positionCounts.values.any((count) => count >= 3)) {
    return 'Draw by threefold repetition.';
  }
  final fields = board.fen.split(' ');
  final halfmove = fields.length > 4 ? int.tryParse(fields[4]) ?? 0 : 0;
  if (halfmove >= 100) return 'Draw by the fifty-move rule.';
  return 'Draw (stalemate or insufficient material).';
}

void _countPosition(Map<String, int> counts, String fen) {
  final key = _positionKey(fen);
  counts[key] = (counts[key] ?? 0) + 1;
}

String _positionKey(String fen) {
  final fields = fen.split(' ');
  if (fields.length < 4) return fen;
  return fields.take(4).join(' ');
}

String _lastSan(chess.Chess board, String fallback) {
  try {
    final text = board.pgn().trim();
    if (text.isEmpty) return fallback;
    final tokens = text.split(RegExp(r'\s+'));
    return tokens.isEmpty ? fallback : tokens.last;
  } catch (_) {
    return fallback;
  }
}

/// The SAN movetext for a game.
///
/// [board] has had every legal move applied, so its PGN is the movetext; a
/// forfeit stops the board at the offender's last legal move, which is what a
/// PGN of a forfeited game should contain.
String _movetext(chess.Chess board) {
  try {
    return board.pgn().trim();
  } catch (_) {
    return '';
  }
}
