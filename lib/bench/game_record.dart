/// One benchmark game: how it ended, what it cost, and the numbers it produced.
///
/// The distinction this file exists for is the one the previous match code did
/// not make: a game that ended without checkmate is *not* necessarily a draw.
/// An engine that threw, timed out, returned an illegal move or crashed lost
/// the game by forfeit; a game stopped at the ply cap was adjudicated and is
/// not a result at all; a game stopped by the user was cancelled. Feeding any
/// of those into a rating fit as a draw biases every rating toward 1500.
library;

import 'dart:math' as math;

/// How a game ended.
enum GameOutcome {
  /// Checkmate against Black.
  whiteWin,

  /// Checkmate against White.
  blackWin,

  /// A real, terminal draw (stalemate, insufficient material, 50-move rule,
  /// threefold repetition).
  draw,

  /// Stopped at the ply cap. Not a result: excluded from the rating fit unless
  /// the configuration says otherwise.
  adjudicated,

  /// One side broke the rules or died. The other side wins, but this is a
  /// reliability result rather than a strength result, so it is reported
  /// separately and kept out of the fit.
  forfeit,

  /// Could not be played (engine unavailable, benchmark stopped between games).
  aborted,

  /// Stopped by the user.
  cancelled;

  String get id => name;

  bool get isDecisive => this == whiteWin || this == blackWin;

  /// Whether this game counts toward a relative rating.
  bool get isRatingEligible =>
      this == whiteWin || this == blackWin || this == draw;

  /// The game is over in the rules sense (a result exists).
  bool get isTerminal => this == whiteWin || this == blackWin || this == draw;

  /// Score for White, 1 / 0.5 / 0, or null when there is no result.
  double? get whiteScore => switch (this) {
        GameOutcome.whiteWin => 1,
        GameOutcome.blackWin => 0,
        GameOutcome.draw => 0.5,
        GameOutcome.forfeit => null,
        _ => null,
      };

  /// The `[Result]` tag a PGN needs; `*` for a game that has no result.
  String get pgnResult => switch (this) {
        GameOutcome.whiteWin => '1-0',
        GameOutcome.blackWin => '0-1',
        GameOutcome.draw => '1/2-1/2',
        _ => '*',
      };

  static GameOutcome fromId(String? id) {
    for (final value in GameOutcome.values) {
      if (value.id == id) return value;
    }
    return GameOutcome.aborted;
  }
}

/// Why a game was forfeited.
enum ForfeitReason {
  none,
  illegalMove,
  timeOut,
  engineError,
  engineCrash,
  handshakeFailure,
  noMoveReturned,
  protocolError;

  String get id => name;

  static ForfeitReason fromId(String? id) {
    for (final value in ForfeitReason.values) {
      if (value.id == id) return value;
    }
    return ForfeitReason.engineError;
  }
}

/// Per-move measurements for one side of one game.
class SideTelemetry {
  /// Wall-clock milliseconds per move, in the order they were played.
  final List<int> moveMillis;

  /// Sum of the engine's own reported node counts, when it reports them.
  final int? totalNodes;

  /// Highest depth the engine reported.
  final int? maxDepth;

  /// Last nodes-per-second sample the engine reported.
  final int? nps;

  const SideTelemetry({
    this.moveMillis = const [],
    this.totalNodes,
    this.maxDepth,
    this.nps,
  });

  static const SideTelemetry none = SideTelemetry();

  int get moves => moveMillis.length;

  int get totalMillis => moveMillis.fold(0, (a, b) => a + b);

  double get meanMillis => moves == 0 ? 0 : totalMillis / moves;

  /// Nearest-rank percentile, so p95 of 20 samples is a sample and not an
  /// interpolation between two.
  int percentile(double p) {
    if (moveMillis.isEmpty) return 0;
    final sorted = [...moveMillis]..sort();
    final index =
        ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1).toInt();
    return sorted[index];
  }

  int get maxMillis => moveMillis.isEmpty
      ? 0
      : moveMillis.reduce((a, b) => a > b ? a : b);

  int get minMillis => moveMillis.isEmpty
      ? 0
      : moveMillis.reduce((a, b) => a < b ? a : b);

  SideTelemetry plusMove(int millis,
          {int? nodes, int? depth, int? npsSample}) =>
      SideTelemetry(
        moveMillis: [...moveMillis, millis],
        totalNodes: nodes == null ? totalNodes : (totalNodes ?? 0) + nodes,
        maxDepth:
            depth == null ? maxDepth : math.max(depth, maxDepth ?? depth),
        nps: npsSample ?? nps,
      );

  Map<String, dynamic> toJson() => {
        'moveMs': moveMillis,
        if (totalNodes != null) 'nodes': totalNodes,
        if (maxDepth != null) 'depth': maxDepth,
        if (nps != null) 'nps': nps,
      };

  factory SideTelemetry.fromJson(Map<String, dynamic> json) {
    final millis = <int>[];
    final raw = json['moveMs'];
    if (raw is List) {
      for (final value in raw) {
        if (value is num) millis.add(value.toInt());
      }
    }
    int? intOf(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return null;
    }

    return SideTelemetry(
      moveMillis: millis,
      totalNodes: intOf('nodes'),
      maxDepth: intOf('depth'),
      nps: intOf('nps'),
    );
  }
}

/// A stored game.
class BenchGame {
  /// Position in the run, 1-based, in the order games were played.
  final int index;
  final String whiteId;
  final String blackId;
  final String whiteLabel;
  final String blackLabel;
  final String openingId;
  final String openingName;

  /// FEN the game started from; the standard start position when empty.
  final String startFen;

  /// UCI moves played in the game (both sides).
  final List<String> moves;

  /// SAN movetext, as the board library renders it.
  final String movetext;

  final GameOutcome outcome;
  final ForfeitReason forfeitReason;

  /// Which engine forfeited, if any.
  final String? forfeitedBy;

  /// Free-text detail: the exception, the illegal move, the adjudication rule.
  final String? detail;

  final SideTelemetry white;
  final SideTelemetry black;

  /// Wall-clock duration of the game.
  final int durationMillis;

  /// Whether this game was a warm-up (played but not recorded in the fit).
  final bool warmUp;

  const BenchGame({
    required this.index,
    required this.whiteId,
    required this.blackId,
    required this.whiteLabel,
    required this.blackLabel,
    required this.openingId,
    required this.openingName,
    required this.startFen,
    required this.moves,
    required this.movetext,
    required this.outcome,
    this.forfeitReason = ForfeitReason.none,
    this.forfeitedBy,
    this.detail,
    this.white = SideTelemetry.none,
    this.black = SideTelemetry.none,
    this.durationMillis = 0,
    this.warmUp = false,
  });

  int get plies => moves.length;

  /// Score for [engineId] in this game, or null when the game has no result
  /// for it (aborted, adjudicated, or it forfeited).
  double? scoreFor(String engineId) {
    final isWhite = engineId == whiteId;
    final isBlack = engineId == blackId;
    if (!isWhite && !isBlack) return null;
    if (outcome == GameOutcome.forfeit) {
      if (forfeitedBy == null) return null;
      if (forfeitedBy == engineId) return 0;
      return 1;
    }
    final whiteScore = outcome.whiteScore;
    if (whiteScore == null) return null;
    return isWhite ? whiteScore : 1 - whiteScore;
  }

  /// Which side played [engineId].
  SideTelemetry telemetryFor(String engineId) =>
      engineId == whiteId ? white : black;

  /// A PGN document with headers.
  String pgnDocument({String event = 'CrispChess Engine Lab'}) {
    String escape(String value) => value.replaceAll('"', "'");
    final date = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final body = movetext.trim();
    final result = outcome.pgnResult;
    final withResult = body.isEmpty
        ? result
        : (body.endsWith(result) ? body : '$body $result');
    return [
      '[Event "${escape(event)}"]',
      '[Site "CrispChess"]',
      '[Date "${date.year}.${two(date.month)}.${two(date.day)}"]',
      '[Round "$index"]',
      '[White "${escape(whiteLabel)}"]',
      '[Black "${escape(blackLabel)}"]',
      '[Result "$result"]',
      '[Opening "${escape(openingName)}"]',
      '[Termination "${_terminationTag()}"]',
      '[Annotator "CrispChess benchmark"]',
      if (startFen.isNotEmpty) '[FEN "$startFen"]',
      if (startFen.isNotEmpty) '[SetUp "1"]',
      '',
      withResult,
      '',
    ].join('\n');
  }

  String _terminationTag() => switch (outcome) {
        GameOutcome.whiteWin || GameOutcome.blackWin => 'normal',
        GameOutcome.draw => 'normal',
        GameOutcome.forfeit => 'forfeit (${forfeitReason.id})',
        GameOutcome.adjudicated => 'adjudicated (ply cap)',
        GameOutcome.aborted => 'aborted',
        GameOutcome.cancelled => 'cancelled',
      };

  Map<String, dynamic> toJson() => {
        'index': index,
        'white': whiteId,
        'black': blackId,
        'whiteLabel': whiteLabel,
        'blackLabel': blackLabel,
        'opening': openingId,
        'openingName': openingName,
        if (startFen.isNotEmpty) 'startFen': startFen,
        'moves': moves,
        'movetext': movetext,
        'outcome': outcome.id,
        if (forfeitReason != ForfeitReason.none)
          'forfeitReason': forfeitReason.id,
        if (forfeitedBy != null) 'forfeitedBy': forfeitedBy,
        if (detail != null) 'detail': detail,
        'whiteTelemetry': white.toJson(),
        'blackTelemetry': black.toJson(),
        'durationMs': durationMillis,
        if (warmUp) 'warmUp': true,
      };

  factory BenchGame.fromJson(Map<String, dynamic> json) {
    final moves = <String>[];
    final rawMoves = json['moves'];
    if (rawMoves is List) {
      for (final move in rawMoves) {
        if (move is String) moves.add(move);
      }
    }
    Map<String, dynamic> sub(String key) {
      final value = json[key];
      return value is Map ? Map<String, dynamic>.from(value) : const {};
    }

    int intOr(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.toInt();
      return fallback;
    }

    return BenchGame(
      index: intOr('index', 0),
      whiteId: (json['white'] as String?) ?? 'unknown',
      blackId: (json['black'] as String?) ?? 'unknown',
      whiteLabel: (json['whiteLabel'] as String?) ?? 'White',
      blackLabel: (json['blackLabel'] as String?) ?? 'Black',
      openingId: (json['opening'] as String?) ?? 'startpos',
      openingName: (json['openingName'] as String?) ?? 'Opening',
      startFen: (json['startFen'] as String?) ?? '',
      moves: moves,
      movetext: (json['movetext'] as String?) ?? '',
      outcome: GameOutcome.fromId(json['outcome'] as String?),
      forfeitReason: ForfeitReason.fromId(json['forfeitReason'] as String?),
      forfeitedBy: json['forfeitedBy'] as String?,
      detail: json['detail'] as String?,
      white: SideTelemetry.fromJson(sub('whiteTelemetry')),
      black: SideTelemetry.fromJson(sub('blackTelemetry')),
      durationMillis: intOr('durationMs', 0),
      warmUp: json['warmUp'] == true,
    );
  }

  @override
  String toString() =>
      'BenchGame($index, $whiteLabel vs $blackLabel, ${outcome.id} '
      'in ${plies.clamp(0, 999)} plies)';
}

/// Aggregate numbers for one engine across a set of games.
class EngineAggregate {
  final String engineId;
  final String label;
  int wins = 0;
  int draws = 0;
  int losses = 0;
  int forfeitWins = 0;
  int forfeitLosses = 0;
  int aborted = 0;
  int adjudicated = 0;
  int cancelled = 0;
  int whiteGames = 0;
  int blackGames = 0;
  final List<int> moveMillis = [];
  int? totalNodes;
  int? maxDepth;
  int? nps;
  int gamesPlayed = 0;

  EngineAggregate({required this.engineId, required this.label});

  /// Games that produced a rating-eligible result.
  int get ratedGames => wins + draws + losses;

  double get score =>
      ratedGames == 0 ? 0 : (wins + draws / 2) / ratedGames;

  double get scorePercent => score * 100;

  /// Games where something went wrong for this engine.
  int get reliabilityIncidents => forfeitLosses + aborted + cancelled;

  int percentile(double p) {
    if (moveMillis.isEmpty) return 0;
    final sorted = [...moveMillis]..sort();
    final index =
        ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1).toInt();
    return sorted[index];
  }

  int get maxMillis => moveMillis.isEmpty
      ? 0
      : moveMillis.reduce((a, b) => a > b ? a : b);

  double get meanMillis => moveMillis.isEmpty
      ? 0
      : moveMillis.fold(0, (a, b) => a + b) / moveMillis.length;

  /// Adds a game to the aggregate.
  void addGame(BenchGame game, {bool countAdjudicatedAsDraws = false}) {
    final isWhite = game.whiteId == engineId;
    if (!isWhite && game.blackId != engineId) return;
    if (isWhite) {
      whiteGames++;
    } else {
      blackGames++;
    }
    final telemetry = game.telemetryFor(engineId);
    moveMillis.addAll(telemetry.moveMillis);
    if (telemetry.totalNodes != null) {
      totalNodes = (totalNodes ?? 0) + telemetry.totalNodes!;
    }
    if (telemetry.maxDepth != null) {
      maxDepth = math.max(telemetry.maxDepth!, maxDepth ?? 0);
    }
    nps = telemetry.nps ?? nps;

    switch (game.outcome) {
      case GameOutcome.whiteWin:
        gamesPlayed++;
        isWhite ? wins++ : losses++;
      case GameOutcome.blackWin:
        gamesPlayed++;
        isWhite ? losses++ : wins++;
      case GameOutcome.draw:
        gamesPlayed++;
        draws++;
      case GameOutcome.forfeit:
        gamesPlayed++;
        if (game.forfeitedBy == engineId) {
          forfeitLosses++;
        } else {
          forfeitWins++;
        }
      case GameOutcome.adjudicated:
        gamesPlayed++;
        adjudicated++;
        if (countAdjudicatedAsDraws) draws++;
      case GameOutcome.aborted:
        aborted++;
      case GameOutcome.cancelled:
        cancelled++;
    }
  }

  Map<String, dynamic> toJson() => {
        'engineId': engineId,
        'label': label,
        'wins': wins,
        'draws': draws,
        'losses': losses,
        'forfeitWins': forfeitWins,
        'forfeitLosses': forfeitLosses,
        'aborted': aborted,
        'adjudicated': adjudicated,
        'cancelled': cancelled,
        'whiteGames': whiteGames,
        'blackGames': blackGames,
        'ratedGames': ratedGames,
        'scorePercent': scorePercent,
        'moves': moveMillis.length,
        'totalMillis': moveMillis.fold(0, (a, b) => a + b),
        'p50': percentile(0.5),
        'p95': percentile(0.95),
        'p99': percentile(0.99),
        'maxMillis': maxMillis,
        if (totalNodes != null) 'nodes': totalNodes,
        if (maxDepth != null) 'depth': maxDepth,
        if (nps != null) 'nps': nps,
      };
}
