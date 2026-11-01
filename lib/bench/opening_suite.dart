/// Opening suites for engine benchmarks.
///
/// Every benchmark pairing plays the same opening twice — once with each engine
/// as White — so the comparison measures engines rather than book luck. The
/// lines below were written for this project from standard opening theory;
/// opening move sequences are facts about the game, and no third-party
/// compilation was copied. Suites can also be supplied as JSON by the user
/// (see [parseOpeningSuite]).
library;

import 'dart:math' as math;
import 'package:chess/chess.dart' as chess;

/// One starting position, optionally preceded by moves.
class Opening {
  /// Stable id inside its suite.
  final String id;

  /// Human name ("Sicilian, Najdorf").
  final String name;

  /// Opening family, for category statistics.
  final String category;

  /// FEN to start from; null means the normal starting position.
  final String? fen;

  /// UCI moves played from [fen] (or the start) before the engines take over.
  final List<String> moves;

  const Opening({
    required this.id,
    required this.name,
    required this.category,
    this.fen,
    this.moves = const [],
  });

  bool get isStartPosition => (fen == null) && moves.isEmpty;

  /// The UCI `position` prefix, so a game's command can be built without
  /// replaying the opening in the app's own board.
  String get positionPrefix => fen == null ? 'position startpos' : 'position fen $fen';

  /// Root FEN for the board the engines play on.
  static const String startFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  String get rootFen => fen ?? startFen;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        if (fen != null) 'fen': fen,
        if (moves.isNotEmpty) 'moves': moves,
      };

  factory Opening.fromJson(Map<String, dynamic> json) {
    final moves = <String>[];
    final rawMoves = json['moves'];
    if (rawMoves is List) {
      for (final move in rawMoves) {
        if (move is String && move.trim().isNotEmpty) moves.add(move.trim());
      }
    }
    final fen = json['fen'];
    return Opening(
      id: (json['id'] as String?) ?? 'opening',
      name: (json['name'] as String?) ?? 'Opening',
      category: (json['category'] as String?) ?? 'unknown',
      fen: fen is String && fen.trim().isNotEmpty ? fen.trim() : null,
      moves: moves,
    );
  }

  @override
  String toString() => 'Opening($id, ${moves.length} moves)';
}

/// A named list of openings.
class OpeningSuite {
  final String id;
  final String name;
  final String description;

  /// Which licences apply to the positions. Ours is CC0: the lines are not
  /// copied from a compilation.
  final String license;
  final String source;
  final List<Opening> openings;

  const OpeningSuite({
    required this.id,
    required this.name,
    required this.description,
    this.license = 'CC0-1.0 (project original)',
    this.source = 'CrispChess',
    required this.openings,
  });

  int get length => openings.length;

  bool get isEmpty => openings.isEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'license': license,
        'source': source,
        'openings': [for (final o in openings) o.toJson()],
      };

  factory OpeningSuite.fromJson(Map<String, dynamic> json) {
    final openings = <Opening>[];
    final raw = json['openings'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          openings.add(Opening.fromJson(Map<String, dynamic>.from(entry)));
        }
      }
    }
    return OpeningSuite(
      id: (json['id'] as String?) ?? 'custom',
      name: (json['name'] as String?) ?? 'Custom suite',
      description: (json['description'] as String?) ?? '',
      license: (json['license'] as String?) ?? 'unknown',
      source: (json['source'] as String?) ?? 'user',
      openings: openings,
    );
  }

  /// The opening for one game of one pairing.
  ///
  /// Deterministic: the same (suite, seed, pairing, game) always yields the
  /// same position, which is what makes a run reproducible. Games 0 and 1 of a
  /// pairing share an opening — they are the two colours of the same game —
  /// and only then does the position change.
  /// The opening for one game.
  ///
  /// [gameIndex] is the 0-based ordinal *within the pairing*: games 0 and 1 are
  /// the colour-swapped pair and must share an opening, games 2 and 3 the next
  /// one. [seed] is the seed of the repetition the game belongs to, so a
  /// repeated run samples different openings. The result depends only on these
  /// inputs — not on how many games have been played — so a schedule can be
  /// rebuilt exactly.
  Opening openingFor({
    required int seed,
    required int pairingIndex,
    required int gameIndex,
  }) {
    if (openings.isEmpty) {
      return const Opening(
          id: 'startpos', name: 'Starting position', category: 'start');
    }
    final pairedGame = gameIndex ~/ 2;
    // A cheap stable mix rather than Random: the result depends only on the
    // inputs, not on how many games were played before this one.
    final mixed = (seed ^ (pairingIndex * 0x9E3779B1)) & 0x7fffffff;
    // A stride sharing a factor with the suite length cycles through only a
    // subset (notably suites of length 7/14). Choose the nearest odd coprime.
    var stride = 7;
    while (BigInt.from(stride).gcd(BigInt.from(openings.length)) != BigInt.one) { stride += 2; }
    final offset = (mixed + pairedGame * stride) % openings.length;
    return openings[offset];
  }

  /// Validate before scheduling, not after an engine has been blamed for an
  /// illegal opening. Returns one actionable error per invalid entry.
  List<String> validationErrors() {
    final errors = <String>[];
    final ids = <String>{};
    for (final opening in openings) {
      if (opening.id.isEmpty || !ids.add(opening.id)) {
        errors.add('Opening ids must be nonempty and unique: ${opening.id}');
      }
      final board = chess.Chess();
      if (opening.fen != null && !board.load(opening.fen!)) {
        errors.add('${opening.id}: invalid FEN');
        continue;
      }
      for (var i = 0; i < opening.moves.length; i++) {
        final uci = opening.moves[i];
        final ok = uci.length >= 4 && board.move({'from': uci.substring(0, 2),
          'to': uci.substring(2, 4),
          if (uci.length > 4) 'promotion': uci.substring(4, 5)});
        if (ok != true) {
          errors.add('${opening.id}: illegal move ${i + 1} ($uci)');
          break;
        }
      }
    }
    return errors;
  }
}

/// Only the starting position. The classic "no book" benchmark.
const OpeningSuite kStartPositionSuite = OpeningSuite(
  id: 'startpos',
  name: 'Starting position',
  description: 'Every game begins from the initial position.',
  openings: [
    Opening(id: 'startpos', name: 'Starting position', category: 'start'),
  ],
);

/// Eight mainstream openings, matched pairs.
///
/// Shared with [kDiverseSuite], which extends it.
const List<Opening> kBalancedOpenings = [
  Opening(
    id: 'ruy-lopez',
    name: 'Ruy Lopez',
    category: 'Open',
    moves: ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1b5'],
  ),
  Opening(
    id: 'italian',
    name: 'Italian Game',
    category: 'Open',
    moves: ['e2e4', 'e7e5', 'g1f3', 'b8c6', 'f1c4', 'f8c5'],
  ),
  Opening(
    id: 'sicilian-najdorf',
    name: 'Sicilian, Najdorf',
    category: 'Half-open',
    moves: [
      'e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', //
      'f3d4', 'g8f6', 'b1c3', 'a7a6',
    ],
  ),
  Opening(
    id: 'french',
    name: 'French Defence',
    category: 'Half-open',
    moves: ['e2e4', 'e7e6', 'd2d4', 'd7d5', 'b1c3', 'g8f6'],
  ),
  Opening(
    id: 'caro-kann',
    name: 'Caro-Kann',
    category: 'Half-open',
    moves: ['e2e4', 'c7c6', 'd2d4', 'd7d5', 'b1c3', 'd5e4', 'c3e4'],
  ),
  Opening(
    id: 'qgd',
    name: "Queen's Gambit Declined",
    category: 'Closed',
    moves: ['d2d4', 'd7d5', 'c2c4', 'e7e6', 'b1c3', 'g8f6'],
  ),
  Opening(
    id: 'kings-indian',
    name: "King's Indian Defence",
    category: 'Closed',
    moves: ['d2d4', 'g8f6', 'c2c4', 'g7g6', 'b1c3', 'f8g7', 'e2e4', 'd7d6'],
  ),
  Opening(
    id: 'english',
    name: 'English Opening',
    category: 'Flank',
    moves: ['c2c4', 'e7e5', 'b1c3', 'g8f6', 'g2g3'],
  ),
];

/// The eight balanced openings as a suite.
const OpeningSuite kBalancedSuite = OpeningSuite(
  id: 'balanced-8',
  name: 'Balanced (8 openings)',
  description:
      'Eight well-known, balanced openings covering open, half-open and closed '
      'structures. Small enough for a quick run, varied enough that a result '
      'does not depend on one line.',
  openings: kBalancedOpenings,
);

/// A wider selection, for runs long enough to average out one line.
const OpeningSuite kDiverseSuite = OpeningSuite(
  id: 'diverse-16',
  name: 'Diverse (16 openings)',
  description:
      'Sixteen lines across open, half-open, closed and flank structures, for '
      'runs long enough to average out a single opening.',
  openings: [
    ...kBalancedOpenings,
    Opening(
      id: 'slav',
      name: 'Slav Defence',
      category: 'Closed',
      moves: ['d2d4', 'd7d5', 'c2c4', 'c7c6', 'g1f3', 'g8f6'],
    ),
    Opening(
      id: 'nimzo-indian',
      name: 'Nimzo-Indian',
      category: 'Closed',
      moves: ['d2d4', 'g8f6', 'c2c4', 'e7e6', 'b1c3', 'f8b4'],
    ),
    Opening(
      id: 'queens-indian',
      name: "Queen's Indian",
      category: 'Closed',
      moves: ['d2d4', 'g8f6', 'c2c4', 'e7e6', 'g1f3', 'b7b6'],
    ),
    Opening(
      id: 'dutch',
      name: 'Dutch Defence',
      category: 'Closed',
      moves: ['d2d4', 'f7f5', 'g2g3', 'g8f6'],
    ),
    Opening(
      id: 'reti',
      name: 'Réti Opening',
      category: 'Flank',
      moves: ['g1f3', 'd7d5', 'c2c4', 'e7e6'],
    ),
    Opening(
      id: 'trompowsky',
      name: 'Trompowsky Attack',
      category: 'Closed',
      moves: ['d2d4', 'g8f6', 'c1g5'],
    ),
    Opening(
      id: 'vienna',
      name: 'Vienna Game',
      category: 'Open',
      moves: ['e2e4', 'e7e5', 'b1c3', 'g8f6', 'f1c4'],
    ),
    Opening(
      id: 'dragon',
      name: 'Sicilian, Dragon',
      category: 'Half-open',
      moves: [
        'e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', //
        'f3d4', 'g8f6', 'b1c3', 'g7g6',
      ],
    ),
  ],
);

/// Suites that ship with the app, by id.
const Map<String, OpeningSuite> kBuiltInOpeningSuites = {
  'startpos': kStartPositionSuite,
  'balanced-8': kBalancedSuite,
  'diverse-16': kDiverseSuite,
};

/// Looks up a built-in suite, falling back to the balanced one.
OpeningSuite openingSuiteById(String id, {Map<String, OpeningSuite>? extra}) {
  final custom = extra?[id];
  if (custom != null) return custom;
  return kBuiltInOpeningSuites[id] ?? kBalancedSuite;
}

/// Every suite available for selection, including user-supplied ones.
List<OpeningSuite> availableOpeningSuites({Map<String, OpeningSuite>? extra}) {
  final suites = <String, OpeningSuite>{
    ...kBuiltInOpeningSuites,
    if (extra != null) ...extra,
  };
  return suites.values.toList();
}

/// Parses a user-supplied suite document.
///
/// Throws [FormatException] with a message that names the problem, because the
/// UI shows it: "1 invalid move" is not actionable, "opening 3 (dutch): move
/// e2e5 is not legal" is.
OpeningSuite parseOpeningSuite(Map<String, dynamic> json) {
  final suite = OpeningSuite.fromJson(json);
  if (suite.openings.isEmpty) {
    throw const FormatException('The suite contains no openings.');
  }
  for (final opening in suite.openings) {
    if (opening.fen != null && !_looksLikeFen(opening.fen!)) {
      throw FormatException(
          'Opening "${opening.name}" has an invalid FEN: ${opening.fen}');
    }
    for (final move in opening.moves) {
      if (!RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(move)) {
        throw FormatException(
            'Opening "${opening.name}" has an invalid UCI move: $move');
      }
    }
  }
  return suite;
}

bool _looksLikeFen(String fen) {
  final fields = fen.trim().split(RegExp(r'\s+'));
  if (fields.length < 4) return false;
  final ranks = fields[0].split('/');
  if (ranks.length != 8) return false;
  for (final rank in ranks) {
    var squares = 0;
    for (final rune in rank.runes) {
      final char = String.fromCharCode(rune);
      if (int.tryParse(char) != null) {
        squares += int.parse(char);
      } else if ('pnbrqkPNBRQK'.contains(char)) {
        squares += 1;
      } else {
        return false;
      }
    }
    if (squares != 8) return false;
  }
  return fields[1] == 'w' || fields[1] == 'b';
}

/// How many distinct openings a run needs before every pairing can use each
/// one twice: purely informational for the workload note.
int distinctOpeningsUsed(OpeningSuite suite, int games) =>
    math.min(suite.length, (games / 2).ceil());
