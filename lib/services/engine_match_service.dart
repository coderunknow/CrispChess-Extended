import 'dart:async';

import 'package:chess/chess.dart' as chess;
import 'package:flutter/foundation.dart';

import '../engines/chess_engine.dart';

String _pgnWithResult(chess.Chess game, String result) {
  final body = game.pgn().trim().replaceFirst(RegExp(r'(?:1-0|0-1|1/2-1/2|\*)$'), '').trim();
  return body.isEmpty ? result : '$body $result';
}

/// Why a game ended. Forfeits and interruptions are deliberately not treated
/// as ordinary chess draws and are excluded from strength fitting.
enum GameResultStatus { completed, adjudicatedDraw, forfeit, aborted, cancelled }

/// Result of a single game in an engine match.
///
/// [whiteId]/[blackId] are stable engine identities; [white]/[black] remain
/// readable labels for PGN and UI. Display names are not unique.
class GameResult {
  final String white;
  final String black;
  final String whiteId;
  final String blackId;
  final String result; // "1-0", "0-1", "1/2-1/2"
  final int moves;
  final String pgn;
  final List<int> whiteMoveMillis;
  final List<int> blackMoveMillis;
  final GameResultStatus status;
  final String? failureReason;

  GameResult({
    required this.white,
    required this.black,
    String? whiteId,
    String? blackId,
    required this.result,
    required this.moves,
    required this.pgn,
    this.whiteMoveMillis = const [],
    this.blackMoveMillis = const [],
    this.status = GameResultStatus.completed,
    this.failureReason,
  })  : whiteId = whiteId ?? white,
        blackId = blackId ?? black;

  double get whiteScore => result == '1-0' ? 1.0 : result == '0-1' ? 0.0 : 0.5;
  double get blackScore => 1.0 - whiteScore;
  bool get eligibleForRating =>
      status == GameResultStatus.completed ||
      status == GameResultStatus.adjudicatedDraw;
}

/// Match configuration.
class MatchConfig {
  final int numGames;
  final int? depthPerMove;
  final Duration? moveTime;
  final bool alternateColors;
  final int plyLimit;

  const MatchConfig({
    this.numGames = 2,
    this.depthPerMove = 10,
    this.moveTime,
    this.alternateColors = true,
    this.plyLimit = 200,
  });
}

/// Events emitted during a match.
sealed class MatchEvent {}

class MatchGameStarted extends MatchEvent {
  final int gameNumber;
  final String white;
  final String black;
  MatchGameStarted(this.gameNumber, this.white, this.black);
}

class MatchMovePlayed extends MatchEvent {
  final int gameNumber;
  final String move;
  final String fen;
  final bool whiteToMove;
  MatchMovePlayed(this.gameNumber, this.move, this.fen, this.whiteToMove);
}

class MatchGameFinished extends MatchEvent {
  final GameResult result;
  MatchGameFinished(this.result);
}

class MatchFinished extends MatchEvent {
  final List<GameResult> results;
  MatchFinished(this.results);
}

/// Runs engine vs engine matches.
class EngineMatchService {
  final ChessEngine engine1;
  final ChessEngine engine2;
  final MatchConfig config;
  final String engine1Id;
  final String engine2Id;
  final _eventController = StreamController<MatchEvent>.broadcast();

  bool _stopped = false;
  final List<GameResult> results = [];
  Object? _engine1InitError;
  Object? _engine2InitError;

  Stream<MatchEvent> get events => _eventController.stream;

  void _emit(MatchEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  EngineMatchService({
    required this.engine1,
    required this.engine2,
    this.config = const MatchConfig(),
    String? engine1Id,
    String? engine2Id,
  })  : engine1Id = engine1Id ?? engine1.name,
        engine2Id = engine2Id ?? engine2.name;

  /// Run the match. Initialization failures are retained as explicit forfeits
  /// rather than being silently skipped or converted into draws.
  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();
    _engine1InitError = null;
    _engine2InitError = null;

    if (engine1.state == EngineState.idle) {
      try {
        await engine1.initialize();
        if (engine1.state != EngineState.ready) {
          throw StateError('Initialization ended in ${engine1.state}');
        }
      } catch (e) {
        _engine1InitError = e;
      }
    } else if (engine1.state != EngineState.ready) {
      _engine1InitError = StateError('Engine is ${engine1.state}');
    }
    if (!_stopped) {
      if (engine2.state == EngineState.idle) {
        try {
          await engine2.initialize();
          if (engine2.state != EngineState.ready) {
            throw StateError('Initialization ended in ${engine2.state}');
          }
        } catch (e) {
          _engine2InitError = e;
        }
      } else if (engine2.state != EngineState.ready) {
        _engine2InitError = StateError('Engine is ${engine2.state}');
      }
    }

    for (var i = 0; i < config.numGames && !_stopped; i++) {
      final swapped = config.alternateColors && i.isOdd;
      final white = swapped ? engine2 : engine1;
      final black = swapped ? engine1 : engine2;
      final whiteName = white.name;
      final blackName = black.name;
      final whiteId = swapped ? engine2Id : engine1Id;
      final blackId = swapped ? engine1Id : engine2Id;
      final whiteInitError = swapped ? _engine2InitError : _engine1InitError;
      final blackInitError = swapped ? _engine1InitError : _engine2InitError;

      _emit(MatchGameStarted(i + 1, whiteName, blackName));
      final result = await _playGame(
        white,
        black,
        i + 1,
        whiteId: whiteId,
        blackId: blackId,
        whiteInitError: whiteInitError,
        blackInitError: blackInitError,
      );
      results.add(result);
      _emit(MatchGameFinished(result));
    }

    _emit(MatchFinished(List.unmodifiable(results)));
    return List.unmodifiable(results);
  }

  Future<GameResult> _playGame(
    ChessEngine white,
    ChessEngine black,
    int gameNum, {
    required String whiteId,
    required String blackId,
    Object? whiteInitError,
    Object? blackInitError,
  }) async {
    final game = chess.Chess();
    var moveCount = 0;
    final whiteMoveMillis = <int>[];
    final blackMoveMillis = <int>[];
    final maxPlies = config.plyLimit.clamp(1, 1000);

    GameResult failed({required bool whiteFailed, required String reason}) =>
        GameResult(
          white: white.name,
          black: black.name,
          whiteId: whiteId,
          blackId: blackId,
          result: whiteFailed ? '0-1' : '1-0',
          moves: moveCount,
          pgn: _pgnWithResult(game, whiteFailed ? '0-1' : '1-0'),
          whiteMoveMillis: List.unmodifiable(whiteMoveMillis),
          blackMoveMillis: List.unmodifiable(blackMoveMillis),
          status: GameResultStatus.forfeit,
          failureReason: reason,
        );
    GameResult cancelled() => GameResult(
          white: white.name,
          black: black.name,
          whiteId: whiteId,
          blackId: blackId,
          result: '1/2-1/2',
          moves: moveCount,
          pgn: _pgnWithResult(game, '1/2-1/2'),
          whiteMoveMillis: List.unmodifiable(whiteMoveMillis),
          blackMoveMillis: List.unmodifiable(blackMoveMillis),
          status: GameResultStatus.cancelled,
          failureReason: 'Match cancelled by user',
        );

    if (whiteInitError != null && blackInitError != null) {
      return GameResult(
        white: white.name,
        black: black.name,
        whiteId: whiteId,
        blackId: blackId,
        result: '1/2-1/2',
        moves: 0,
        pgn: _pgnWithResult(game, '1/2-1/2'),
        status: GameResultStatus.aborted,
        failureReason: 'Both engines failed to initialize: '
            'White: $whiteInitError; Black: $blackInitError',
      );
    }
    if (whiteInitError != null) {
      return failed(whiteFailed: true, reason: 'White initialization failed: $whiteInitError');
    }
    if (blackInitError != null) {
      return failed(whiteFailed: false, reason: 'Black initialization failed: $blackInitError');
    }

    while (!game.game_over && moveCount < maxPlies && !_stopped) {
      final isWhiteTurn = game.turn == chess.Color.WHITE;
      final engine = isWhiteTurn ? white : black;
      final posCmd = game.history.isEmpty
          ? 'position startpos'
          : 'position startpos moves ${game.history.map((h) => '${h.move.fromAlgebraic}${h.move.toAlgebraic}${h.move.promotion?.name ?? ''}').join(' ')}';

      try {
        final stopwatch = Stopwatch()..start();
        final uci = await engine.bestMove(
          posCmd,
          depth: config.depthPerMove,
          moveTime: config.moveTime,
        );
        stopwatch.stop();
        (isWhiteTurn ? whiteMoveMillis : blackMoveMillis)
            .add((stopwatch.elapsedMicroseconds / 1000).round());
        if (!RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(uci)) {
          return failed(whiteFailed: isWhiteTurn, reason: 'Invalid UCI move: "$uci"');
        }
        final ok = game.move({
          'from': uci.substring(0, 2),
          'to': uci.substring(2, 4),
          'promotion': uci.length > 4 ? uci.substring(4, 5) : null,
        });
        if (ok == false) {
          return failed(whiteFailed: isWhiteTurn, reason: 'Illegal move: "$uci"');
        }
        moveCount++;
        final sanList = game.pgn().split(RegExp(r'\s+'));
        final lastSan = sanList.isNotEmpty ? sanList.last : uci;
        _emit(MatchMovePlayed(gameNum, lastSan, game.fen, !isWhiteTurn));
      } catch (e) {
        if (_stopped) return cancelled();
        debugPrint('[Match] Engine error: $e');
        return failed(whiteFailed: isWhiteTurn, reason: 'Engine failed: $e');
      }
    }

    if (_stopped) return cancelled();

    final isCheckmate = game.in_checkmate;
    final result = isCheckmate
        ? (game.turn == chess.Color.WHITE ? '0-1' : '1-0')
        : '1/2-1/2';
    final capped = !game.game_over && moveCount >= maxPlies;
    return GameResult(
      white: white.name,
      black: black.name,
      whiteId: whiteId,
      blackId: blackId,
      result: result,
      moves: moveCount,
      pgn: _pgnWithResult(game, result),
      whiteMoveMillis: List.unmodifiable(whiteMoveMillis),
      blackMoveMillis: List.unmodifiable(blackMoveMillis),
      status: capped ? GameResultStatus.adjudicatedDraw : GameResultStatus.completed,
      failureReason: capped ? 'Ply limit reached; adjudicated draw' : null,
    );
  }

  void stop() {
    _stopped = true;
    for (final engine in [engine1, engine2]) {
      try {
        engine.stop();
      } catch (e) {
        debugPrint('[Match] stop failed for ${engine.name}: $e');
      }
    }
  }

  void dispose() {
    _stopped = true;
    if (!_eventController.isClosed) _eventController.close();
  }

  /// Display-name aggregation retained for older UI callers. New statistics
  /// must use [scoresById] to avoid collisions between same-name profiles.
  static Map<String, double> scores(List<GameResult> results) {
    final scores = <String, double>{};
    for (final r in results.where((r) => r.eligibleForRating)) {
      scores[r.white] = (scores[r.white] ?? 0) + r.whiteScore;
      scores[r.black] = (scores[r.black] ?? 0) + r.blackScore;
    }
    return scores;
  }

  static Map<String, double> scoresById(List<GameResult> results) {
    final scores = <String, double>{};
    for (final r in results.where((r) => r.eligibleForRating)) {
      scores[r.whiteId] = (scores[r.whiteId] ?? 0) + r.whiteScore;
      scores[r.blackId] = (scores[r.blackId] ?? 0) + r.blackScore;
    }
    return scores;
  }
}

/// Round-robin tournament event.
class TournamentRoundStart extends MatchEvent {
  final int round;
  final int totalRounds;
  final String white;
  final String black;
  TournamentRoundStart(this.round, this.totalRounds, this.white, this.black);
}

/// Runs a round-robin tournament between the selected engines.
class TournamentService {
  final List<ChessEngine> engines;
  final List<String> engineIds;
  final int? depthPerMove;
  final int gamesPerPairing;
  final Duration? moveTime;
  final int plyLimit;
  final _eventController = StreamController<MatchEvent>.broadcast();
  bool _stopped = false;
  EngineMatchService? _activeMatch;
  final List<GameResult> results = [];

  Stream<MatchEvent> get events => _eventController.stream;

  void _emit(MatchEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  TournamentService({
    required this.engines,
    List<String>? engineIds,
    this.depthPerMove = 8,
    this.gamesPerPairing = 2,
    this.moveTime,
    this.plyLimit = 200,
  }) : engineIds = engineIds ?? [for (final e in engines) e.name] {
    if (this.engineIds.length != engines.length) {
      throw ArgumentError('engineIds must match engines');
    }
    if (gamesPerPairing < 1) throw ArgumentError.value(gamesPerPairing, 'gamesPerPairing');
  }

  List<(int, int)> get _pairings {
    final pairs = <(int, int)>[];
    for (var i = 0; i < engines.length; i++) {
      for (var j = i + 1; j < engines.length; j++) {
        pairs.add((i, j));
      }
    }
    return pairs;
  }

  int get totalGames => _pairings.length * gamesPerPairing;

  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();
    for (final e in engines) {
      if (_stopped) break;
      if (e.state == EngineState.idle) {
        try {
          await e.initialize();
        } catch (_) {
          // Per-game service records this exact engine as the forfeiting side.
        }
      }
    }

    final pairings = _pairings;
    var round = 0;
    for (final (i, j) in pairings) {
      for (var g = 0; g < gamesPerPairing && !_stopped; g++) {
        final (w, b) = g.isEven ? (i, j) : (j, i);
        round++;
        _emit(TournamentRoundStart(
            round, totalGames, engines[w].name, engines[b].name));
        final match = EngineMatchService(
          engine1: engines[w],
          engine2: engines[b],
          engine1Id: engineIds[w],
          engine2Id: engineIds[b],
          config: MatchConfig(
            numGames: 1,
            depthPerMove: depthPerMove,
            moveTime: moveTime,
            alternateColors: false,
            plyLimit: plyLimit,
          ),
        );
        final sub = match.events.listen((event) {
          // Suppress the one-game match's terminal event; the tournament emits
          // one aggregate MatchFinished only after all pairings have completed.
          if (event is! MatchFinished && !_eventController.isClosed) {
            _eventController.add(event);
          }
        });
        _activeMatch = match;
        try {
          results.addAll(await match.run());
        } finally {
          await sub.cancel();
          for (final engine in [engines[w], engines[b]]) {
            if (engine.state == EngineState.thinking && engine is SearchDrainableEngine) {
              await engine.drainSearch();
            }
          }
          match.dispose();
          _activeMatch = null;
        }
      }
      if (_stopped) break;
    }
    _emit(MatchFinished(List.unmodifiable(results)));
    return List.unmodifiable(results);
  }

  void stop() {
    _stopped = true;
    _activeMatch?.stop();
    for (final e in engines) {
      try {
        e.stop();
      } catch (error) {
        debugPrint('[Tournament] stop failed for ${e.name}: $error');
      }
    }
  }

  void dispose() {
    _stopped = true;
    if (!_eventController.isClosed) _eventController.close();
  }

  static List<MapEntry<String, double>> standings(List<GameResult> results) {
    final scores = EngineMatchService.scores(results);
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  static List<MapEntry<String, double>> standingsById(List<GameResult> results) {
    final scores = EngineMatchService.scoresById(results);
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }
}
