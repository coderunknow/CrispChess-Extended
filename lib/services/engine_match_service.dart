import 'dart:async';

import '../bench/benchmark_plan.dart' show TournamentFormat;
import '../bench/game_player.dart';
import '../bench/game_record.dart';
import '../engines/chess_engine.dart';
import '../bench/opening_suite.dart' show Opening;
import '../engines/search_telemetry.dart';

export '../bench/game_record.dart' show GameOutcome, ForfeitReason;

/// Result of a single game in an engine match.
///
/// Two things are deliberately *not* here any more:
///
///  * the display name as identity. [whiteId]/[blackId] are the stable ids the
///    rest of the app keys engines by; [white]/[black] remain for display
///    because every caller prints them, but nothing aggregates by them any
///    more. Two profiles called "Stockfish" used to merge their scores.
///  * "the game ended without checkmate, so it was a draw". A game now carries
///    an explicit [GameOutcome]: win, loss, draw, forfeit, adjudicated, aborted
///    or cancelled. An engine that threw, timed out or played an illegal move
///    forfeits; a game stopped at the ply cap is adjudicated, not drawn.
class GameResult {
  final String whiteId;
  final String blackId;

  /// Display names.
  final String white;
  final String black;

  final GameOutcome outcome;
  final ForfeitReason forfeitReason;
  final String? forfeitedBy;
  final String? detail;
  final int moves;

  /// The movetext (SAN), without headers.
  final String pgn;

  const GameResult({
    required this.whiteId,
    required this.blackId,
    required this.white,
    required this.black,
    required this.outcome,
    this.forfeitReason = ForfeitReason.none,
    this.forfeitedBy,
    this.detail,
    required this.moves,
    required this.pgn,
  });

  /// A readable result tag, e.g. `1-0`, `1/2-1/2`, `1-0 (forfeit)`.
  String get result {
    if (outcome == GameOutcome.forfeit) {
      if (forfeitedBy == whiteId) return '0-1 (forfeit)';
      if (forfeitedBy == blackId) return '1-0 (forfeit)';
      return '* (forfeit)';
    }
    return outcome.pgnResult;
  }

  /// The result tag a PGN needs.
  String get pgnResult => outcome.pgnResult;

  /// Points for White, or null when the game produced no rating-eligible
  /// result (adjusting for which side forfeited).
  double? get whiteScore {
    if (outcome == GameOutcome.forfeit) {
      if (forfeitedBy == null) return null;
      return forfeitedBy == whiteId ? 0 : 1;
    }
    return outcome.whiteScore;
  }

  double? get blackScore {
    final white = whiteScore;
    return white == null ? null : 1 - white;
  }

  /// Whether this game belongs in a rating.
  bool get isRated => outcome.isRatingEligible;

  /// A PGN document with headers.
  String pgnDocument({String event = 'CrispChess engine match'}) {
    final body = pgn.trim();
    final result = pgnResult;
    final movetext =
        body.isEmpty ? result : (body.endsWith(result) ? body : '$body $result');
    return [
      '[Event "$event"]',
      '[Site "CrispChess"]',
      '[White "$white"]',
      '[Black "$black"]',
      '[Result "$result"]',
      if (outcome == GameOutcome.forfeit)
        '[Termination "forfeit (${forfeitReason.id})"]',
      '',
      movetext,
      '',
    ].join('\n');
  }
}

/// Match configuration.
class MatchConfig {
  final int numGames;

  /// Fixed search depth, or null to search by time.
  ///
  /// Only one budget is ever sent. A UCI engine given both `go depth 8` and a
  /// 100 ms `movetime` searches to depth 8 and ignores the clock
  /// ([uciGoCommand] sends `depth` when it is present), so a caller that asks
  /// for a time control used to get a depth control with the time control's
  /// name on it — and every rating measured that way described a different
  /// budget from the one the report recorded.
  final int? depthPerMove;
  final Duration? moveTime;
  final bool alternateColors;

  /// Plies before a game is adjudicated (and reported as such, not as a draw).
  final int plyCap;

  /// Opening the games start from. Null starts from the initial position.
  final Opening? opening;

  const MatchConfig({
    this.numGames = 2,
    this.depthPerMove = 10,
    this.moveTime,
    this.alternateColors = true,
    this.plyCap = 240,
    this.opening,
  });

  /// A configuration that searches for [moveTime] per move.
  ///
  /// The depth is cleared, not merely deprioritised: an engine that is asked
  /// for both runs on the depth.
  factory MatchConfig.timed({
    int numGames = 2,
    required Duration moveTime,
    bool alternateColors = true,
    int plyCap = 240,
    Opening? opening,
  }) =>
      MatchConfig(
        numGames: numGames,
        depthPerMove: null,
        moveTime: moveTime,
        alternateColors: alternateColors,
        plyCap: plyCap,
        opening: opening,
      );

  /// The depth to ask for, given the configured time control.
  int? get effectiveDepth => moveTime != null ? null : depthPerMove;
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
  final String move; // SAN
  final String fen;
  final bool whiteToMove;
  MatchMovePlayed(this.gameNumber, this.move, this.fen, this.whiteToMove);
}

class MatchGameFinished extends MatchEvent {
  final GameResult result;
  MatchGameFinished(this.result);
}

/// Engines that could not be started before the games began.
///
/// Reported rather than thrown: a tournament in which one engine cannot start
/// still produces forfeits that say which engine failed and why, which is more
/// useful than a stack trace and no results.
class TournamentEnginesUnavailable extends MatchEvent {
  final List<String> reasons;

  TournamentEnginesUnavailable(this.reasons);
}

class MatchFinished extends MatchEvent {
  final List<GameResult> results;
  MatchFinished(this.results);
}

/// How a game is played by the match and tournament wrappers.
///
/// Both use the same loop as the Engine Lab (`bench/game_player.dart`), so the
/// app plays legal-move checks, forfeit classification and ply-cap adjudication
/// exactly once.
GameResult _toGameResult(BenchGame game) => GameResult(
      whiteId: game.whiteId,
      blackId: game.blackId,
      white: game.whiteLabel,
      black: game.blackLabel,
      outcome: game.outcome,
      forfeitReason: game.forfeitReason,
      forfeitedBy: game.forfeitedBy,
      detail: game.detail,
      moves: game.plies,
      pgn: game.movetext,
    );

/// Runs engine vs engine matches.
class EngineMatchService {
  final ChessEngine engine1;
  final ChessEngine engine2;

  /// Stable ids for the two engines. Defaulting to the display name keeps the
  /// old constructor working, but a caller that has ids should pass them: a
  /// name is not an identity.
  final String engine1Id;
  final String engine2Id;
  final MatchConfig config;
  final _eventController = StreamController<MatchEvent>.broadcast();

  bool _stopped = false;
  final List<GameResult> results = [];

  Stream<MatchEvent> get events => _eventController.stream;

  EngineMatchService({
    required this.engine1,
    required this.engine2,
    this.config = const MatchConfig(),
    String? engine1Id,
    String? engine2Id,
  })  : engine1Id = engine1Id ?? engine1.name,
        engine2Id = engine2Id ?? engine2.name;

  /// Run the match. Returns all game results.
  ///
  /// A failed initialisation is a recorded outcome, not an exception: a match
  /// between an engine that starts and one that does not has one forfeit per
  /// game, and the screen can say which engine failed and why. Cancellation is
  /// checked *before* each handshake, so stopping during a slow start does not
  /// start the next process.
  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();
    _initFailures.clear();

    await _initializeIfNeeded(engine1, engine1Id);
    if (!_stopped) await _initializeIfNeeded(engine2, engine2Id);

    for (int i = 0; i < config.numGames && !_stopped; i++) {
      final swapped = config.alternateColors && i.isOdd;
      final white = swapped ? engine2 : engine1;
      final black = swapped ? engine1 : engine2;
      final whiteId = swapped ? engine2Id : engine1Id;
      final blackId = swapped ? engine1Id : engine2Id;

      _eventController.add(MatchGameStarted(i + 1, white.name, black.name));

      final result = await _playGame(white, black, whiteId, blackId, i + 1);
      if (result != null) {
        results.add(result);
        _eventController.add(MatchGameFinished(result));
      }
    }

    _eventController.add(MatchFinished(results));
    return results;
  }

  final Map<String, Object> _initFailures = {};

  /// Starts one engine if it has not started, remembering the failure instead
  /// of letting it end the match.
  Future<void> _initializeIfNeeded(ChessEngine engine, String engineId) async {
    if (engine.state == EngineState.idle) {
      try {
        await engine.initialize();
        if (engine.state != EngineState.ready) {
          _initFailures[engineId] =
              StateError('initialisation ended in ${engine.state.name}');
        }
      } catch (error) {
        _initFailures[engineId] = error;
      }
      return;
    }
    if (engine.state == EngineState.error || engine.state == EngineState.disposed) {
      _initFailures[engineId] =
          StateError('the engine is ${engine.state.name}');
    }
  }

  Future<GameResult?> _playGame(
    ChessEngine white,
    ChessEngine black,
    String whiteId,
    String blackId,
    int gameNum,
  ) async {
    final whiteFailure = _initFailures[whiteId];
    final blackFailure = _initFailures[blackId];
    if (whiteFailure != null || blackFailure != null) {
      // Both dead is an aborted game; one dead is a forfeit for that side.
      final bothFailed = whiteFailure != null && blackFailure != null;
      final forfeitedBy = bothFailed
          ? null
          : (whiteFailure != null ? whiteId : blackId);
      return GameResult(
        whiteId: whiteId,
        blackId: blackId,
        white: white.name,
        black: black.name,
        outcome: bothFailed ? GameOutcome.aborted : GameOutcome.forfeit,
        forfeitReason:
            bothFailed ? ForfeitReason.none : ForfeitReason.handshakeFailure,
        forfeitedBy: forfeitedBy,
        detail: bothFailed
            ? 'Neither engine could start. White: $whiteFailure; '
                'Black: $blackFailure'
            : 'One engine could not start: ${whiteFailure ?? blackFailure}',
        moves: 0,
        pgn: '',
      );
    }
    final game = await playBenchGame(
      index: gameNum,
      whiteId: whiteId,
      blackId: blackId,
      whiteLabel: white.name,
      blackLabel: black.name,
      whiteMove: _requesterFor(white),
      blackMove: _requesterFor(black),
      opening: config.opening ??
          const Opening(id: 'startpos', name: 'Starting position', category: 'start'),
      plyCap: config.plyCap,
      depth: config.effectiveDepth,
      moveTime: config.moveTime,
      cancelled: () => _stopped,
      onMove: (fen, san, whiteToMove) {
        _eventController.add(MatchMovePlayed(gameNum, san, fen, whiteToMove));
      },
    );
    if (_stopped && game.outcome == GameOutcome.cancelled) return null;
    return _toGameResult(game);
  }

  /// Wraps one engine as a [MoveRequester], keeping its own node/depth
  /// counters when it publishes them and measuring wall clock regardless.
  MoveRequester _requesterFor(ChessEngine engine) {
    final telemetry =
        engine is SearchTelemetry ? engine as SearchTelemetry : null;
    final depth = config.effectiveDepth;
    return measuredRequester(
      (position) => engine.bestMove(
        position,
        depth: depth,
        moveTime: config.moveTime,
      ),
      statsOf: telemetry == null ? null : () => telemetry.lastSearchStatistics,
    );
  }

  void stop() {
    _stopped = true;
    engine1.stop();
    engine2.stop();
  }

  void dispose() {
    _stopped = true;
    _eventController.close();
  }

  /// Points per engine id, counting only games that produced a result.
  ///
  /// Keyed by id, not by display name: two custom profiles called "Stockfish"
  /// must not share a total.
  static Map<String, double> scores(List<GameResult> results) {
    final scores = <String, double>{};
    for (final r in results) {
      final white = r.whiteScore;
      final black = r.blackScore;
      if (white != null) {
        scores[r.whiteId] = (scores[r.whiteId] ?? 0) + white;
      }
      if (black != null) {
        scores[r.blackId] = (scores[r.blackId] ?? 0) + black;
      }
    }
    return scores;
  }

  /// Rated games per engine id.
  static Map<String, int> gamesPlayed(List<GameResult> results) {
    final games = <String, int>{};
    for (final r in results) {
      if (!r.isRated) continue;
      games[r.whiteId] = (games[r.whiteId] ?? 0) + 1;
      games[r.blackId] = (games[r.blackId] ?? 0) + 1;
    }
    return games;
  }

  /// Games that ended without a rated result, by reason.
  static Map<String, int> unclassified(List<GameResult> results) {
    final counts = <String, int>{};
    for (final r in results) {
      if (r.isRated) continue;
      counts[r.outcome.id] = (counts[r.outcome.id] ?? 0) + 1;
    }
    return counts;
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

/// Runs a round-robin tournament between 3+ engines.
///
/// Each pair plays [gamesPerPairing] games, alternating colours.
class TournamentService {
  final List<ChessEngine> engines;

  /// Stable ids, parallel to [engines]. Defaults to the display names.
  final List<String> engineIds;

  final int depthPerMove;
  final int gamesPerPairing;
  final Duration? moveTime;
  final int plyCap;
  final bool gauntlet;
  final String? referenceEngineId;
  final _eventController = StreamController<MatchEvent>.broadcast();
  bool _stopped = false;
  final List<GameResult> results = [];

  Stream<MatchEvent> get events => _eventController.stream;

  TournamentService({
    required this.engines,
    this.depthPerMove = 8,
    this.gamesPerPairing = 2,
    this.moveTime,
    this.plyCap = 240,
    this.gauntlet = false,
    this.referenceEngineId,
    List<String>? engineIds,
  }) : engineIds = engineIds ?? [for (final engine in engines) engine.name];

  String _idOf(int index) =>
      index >= 0 && index < engineIds.length ? engineIds[index] : '${engines[index].name}';

  /// Generate all pairings for the format.
  List<(int, int)> get _pairings {
    final pairs = <(int, int)>[];
    if (gauntlet) {
      // Read once into a local: a public field is not promoted, and
      // `indexOf` needs the non-null value.
      final wanted = referenceEngineId;
      final reference = wanted == null ? -1 : engineIds.indexOf(wanted);
      if (reference < 0) {
        // Without a reference there is no gauntlet to play. Refusing is better
        // than silently running a round robin the caller did not ask for.
        return pairs;
      }
      for (var i = 0; i < engines.length; i++) {
        if (i == reference) continue;
        pairs.add((reference, i));
      }
      return pairs;
    }
    for (int i = 0; i < engines.length; i++) {
      for (int j = i + 1; j < engines.length; j++) {
        pairs.add((i, j));
      }
    }
    return pairs;
  }

  int get totalGames => _pairings.length * gamesPerPairing;

  /// Run the tournament.
  Future<List<GameResult>> run() async {
    _stopped = false;
    results.clear();

    // Start the engines, but stop starting them the moment the run is
    // cancelled: a slow handshake (a model load, a WASM instantiation) must not
    // keep launching processes after the user asked the tournament to stop.
    final failures = <String>[];
    for (var i = 0; i < engines.length; i++) {
      if (_stopped) break;
      final engine = engines[i];
      if (engine.state != EngineState.idle) continue;
      try {
        await engine.initialize();
        if (engine.state != EngineState.ready) {
          failures.add('${_idOf(i)}: initialisation ended in '
              '${engine.state.name}');
        }
      } catch (error) {
        failures.add('${_idOf(i)}: $error');
      }
    }
    if (failures.isNotEmpty) {
      _eventController.add(TournamentEnginesUnavailable(failures));
    }

    final pairings = _pairings;
    int round = 0;

    for (final (i, j) in pairings) {
      for (var g = 0; g < gamesPerPairing && !_stopped; g++) {
        final (w, b) = g.isEven ? (i, j) : (j, i);
        round++;
        _eventController.add(TournamentRoundStart(
            round, totalGames, engines[w].name, engines[b].name));
        final match = EngineMatchService(
          engine1: engines[w],
          engine2: engines[b],
          engine1Id: _idOf(w),
          engine2Id: _idOf(b),
          config: MatchConfig(
            numGames: 1,
            depthPerMove: depthPerMove,
            alternateColors: false,
            moveTime: moveTime,
            plyCap: plyCap,
          ),
        );
        // A sub-match's own MatchFinished is not forwarded: the tournament
        // emits one at the end, and passing every pair's through would tell
        // the screen the tournament was over after the first pairing.
        final sub = match.events
            .where((event) => event is! MatchFinished)
            .listen(_eventController.add);
        results.addAll(await match.run());
        await sub.cancel();
        match.dispose();
      }
      if (_stopped) break;
    }

    _eventController.add(MatchFinished(results));
    return results;
  }

  void stop() {
    _stopped = true;
    for (final e in engines) {
      e.stop();
    }
  }

  void dispose() {
    _stopped = true;
    _eventController.close();
  }

  /// Standings by score, keyed by engine id.
  static List<MapEntry<String, double>> standings(List<GameResult> results) {
    final scores = EngineMatchService.scores(results);
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }
}

/// Human-readable name of a tournament format.
String tournamentFormatLabel(TournamentFormat format) => switch (format) {
      TournamentFormat.roundRobin => 'Round robin',
      TournamentFormat.gauntlet => 'Gauntlet',
    };
