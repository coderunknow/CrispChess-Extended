import 'dart:async';
import '../l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import '../engines/chess_engine.dart';
import '../engines/engine_registry.dart';
import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../services/engine_profile_store.dart';
import '../services/engine_match_service.dart';
import '../bench/elo.dart';
import '../chess/chess_game.dart';
import '../widgets/chess_board.dart';
import 'engine_lab_screen.dart';

/// Screen for running engine vs engine matches.
class EngineMatchScreen extends StatefulWidget {
  const EngineMatchScreen({super.key});

  @override
  State<EngineMatchScreen> createState() => _EngineMatchScreenState();
}

class _EngineMatchScreenState extends State<EngineMatchScreen> {
  String _engine1Name = builtInEngineId('Built-in');
  String _engine2Name = builtInEngineId('Frozenight');
  int _numGames = 2;
  int _depth = 8;
  bool _running = false;
  bool _tournamentMode = false;
  EngineMatchService? _match;
  TournamentService? _tournament;
  StreamSubscription<MatchEvent>? _sub;

  /// Selected engines for tournament mode (ids, see `engine_registry.dart`).
  final Set<String> _tournamentEngines = {
    builtInEngineId('Built-in'),
    builtInEngineId('Frozenight'),
    builtInEngineId('Maia3 Dart'),
  };

  final EngineProfileStore _profileStore = EngineProfileStore();
  List<EngineProfile> _profiles = const [];

  /// Engines this screen created and must therefore dispose.
  ///
  /// Neither [EngineMatchService] nor [TournamentService] owns its engines —
  /// the tournament reuses them across pairings — so nothing disposed them at
  /// all, and every match left its engine processes running.
  final List<ChessEngine> _ownedEngines = [];

  final List<GameResult> _results = [];
  String _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
  String _status = 'Configure and start';
  int _currentGame = 0;
  int _currentMoveCount = 0;

  /// Built-in engines offered by the match screen, from the shared list in
  /// `engine_registry.dart` so the Engine Lab benchmarks exactly these.
  static final _builtInNames = builtInMatchEngines.where((name) => name != 'Lynx' || lynxAvailable).toList();

  /// Everything selectable here: the built-ins above plus user-added engines.
  List<({String id, String label})> get _engineChoices =>
      matchEngineChoices(_builtInNames, _profiles);

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    List<EngineProfile> profiles;
    try {
      profiles = await _profileStore.load();
    } catch (e) {
      debugPrint('[EngineMatch] could not load engine profiles: $e');
      return;
    }
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  /// Builds an engine by id, reporting a removed/incompatible one as an error
  /// instead of silently substituting the built-in engine.
  ChessEngine? _buildEngine(String id) {
    try {
      return createEngineForId(id, profiles: _profiles);
    } on EngineUnavailableException catch (e) {
      debugPrint('[EngineMatch] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${engineLabelForId(id, _profiles)}: ${e.reason}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _match?.stop();
    _match?.dispose();
    _tournament?.stop();
    _tournament?.dispose();
    _disposeOwnedEngines();
    super.dispose();
  }

  void _disposeOwnedEngines() {
    for (final engine in _ownedEngines) {
      try {
        engine.dispose();
      } catch (e) {
        debugPrint('[EngineMatch] dispose failed: $e');
      }
    }
    _ownedEngines.clear();
  }

  Future<void> _startMatch() async {
    if (_engine1Name == _engine2Name) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.selectTwoDifferent ?? 'Select two different engines'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _running = true;
      _results.clear();
      _status = 'Initializing engines...';
    });

    // A previous match's engines are done with; leaving them alive would keep
    // their processes (and, for custom engines, their binaries) running.
    _match?.stop();
    _match?.dispose();
    _match = null;
    _sub?.cancel();
    _disposeOwnedEngines();

    final e1 = _buildEngine(_engine1Name);
    final e2 = _buildEngine(_engine2Name);
    if (e1 == null || e2 == null) {
      if (e1 != null) e1.dispose();
      if (e2 != null) e2.dispose();
      setState(() {
        _running = false;
        _status = 'Engine unavailable';
      });
      return;
    }
    _ownedEngines.addAll([e1, e2]);

    _match = EngineMatchService(
      engine1: e1,
      engine2: e2,
      engine1Id: _engine1Name,
      engine2Id: _engine2Name,
      config: MatchConfig(numGames: _numGames, depthPerMove: _depth),
    );

    _sub = _match!.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case MatchGameStarted(:final gameNumber, :final white, :final black):
          setState(() {
            _currentGame = gameNumber;
            _currentMoveCount = 0;
            _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            _status = 'Game $gameNumber/$_numGames: $white vs $black';
          });
        case MatchMovePlayed(:final fen, :final move):
          setState(() {
            _currentFen = fen;
            _currentMoveCount++;
            _status = 'Game $_currentGame: move $_currentMoveCount ($move)';
          });
        case TournamentEnginesUnavailable(:final reasons):
          setState(() {
            _status = reasons.isEmpty
                ? 'Some engines could not be started'
                : 'Engines unavailable: ${reasons.join('; ')}';
          });
        case MatchGameFinished(:final result):
          setState(() {
            _results.add(result);
            _status = 'Game ${result.white} vs ${result.black}: ${result.result} (${result.moves} moves)';
          });
        case MatchFinished(:final results):
          final scores = EngineMatchService.scores(results);
          final skipped = EngineMatchService.unclassified(results);
          setState(() {
            _running = false;
            _status = 'Match complete! '
                '${scores.entries.map((e) => '${_labelForId(e.key)}: ${e.value}').join(' — ')}'
                '${skipped.isEmpty ? '' : ' · not rated: '
                    '${skipped.entries.map((e) => '${e.value} ${e.key}').join(', ')}'}';
          });
        case TournamentRoundStart():
          break; // Handled in tournament mode
      }
    });

    try {
      await _match!.run();
    } catch (e) {
      debugPrint('[EngineMatch] match failed: $e');
      if (mounted) {
        setState(() {
          _running = false;
          _status = 'Match failed: $e';
        });
      }
    }
  }

  Future<void> _startTournament() async {
    if (_tournamentEngines.length < 3) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.selectAtLeast3 ?? 'Select at least 3 engines'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() {
      _running = true;
      _results.clear();
      _status = 'Initializing tournament...';
    });

    _tournament?.stop();
    _tournament?.dispose();
    _tournament = null;
    _sub?.cancel();
    _disposeOwnedEngines();

    final engines = <ChessEngine>[];
    final engineIds = <String>[];
    for (final id in _tournamentEngines) {
      final engine = _buildEngine(id);
      if (engine != null) {
        engines.add(engine);
        engineIds.add(id);
      }
    }
    _ownedEngines.addAll(engines);
    if (engines.length < 3) {
      for (final engine in engines) {
        engine.dispose();
      }
      setState(() {
        _running = false;
        _status = 'Not enough engines could be started';
      });
      return;
    }
    _tournament = TournamentService(
      engines: engines,
      engineIds: engineIds,
      depthPerMove: _depth,
      gamesPerPairing: _numGames,
    );

    _sub = _tournament!.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case TournamentRoundStart(:final round, :final totalRounds, :final white, :final black):
          setState(() {
            _currentGame = round;
            _currentMoveCount = 0;
            _currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
            _status = 'Round $round/$totalRounds: $white vs $black';
          });
        case MatchMovePlayed(:final fen):
          setState(() {
            _currentFen = fen;
            _currentMoveCount++;
          });
        case TournamentEnginesUnavailable(:final reasons):
          setState(() {
            _status = reasons.isEmpty
                ? 'Some engines could not be started'
                : 'Engines unavailable: ${reasons.join('; ')}';
          });
        case MatchGameFinished(:final result):
          setState(() => _results.add(result));
        case MatchFinished(:final results):
          final standings = TournamentService.standings(results);
          final skipped = EngineMatchService.unclassified(results);
          setState(() {
            _running = false;
            _status = standings.isEmpty
                ? 'Tournament complete — no rated games.'
                : 'Tournament complete! Winner: '
                    '${_labelForId(standings.first.key)} '
                    '(${standings.first.value} points)'
                    '${skipped.isEmpty ? '' : ' · not rated: '
                        '${skipped.entries.map((e) => '${e.value} ${e.key}').join(', ')}'}';
          });
        default:
          break;
      }
    });

    try {
      await _tournament!.run();
    } catch (e) {
      debugPrint('[EngineMatch] tournament failed: $e');
      if (mounted) {
        setState(() {
          _running = false;
          _status = 'Tournament failed: $e';
        });
      }
    }
  }

  void _stopMatch() {
    _match?.stop();
    _tournament?.stop();
    setState(() {
      _running = false;
      _status = AppLocalizations.of(context)?.stopped ?? 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scores = EngineMatchService.scores(_results);

    return Scaffold(
      appBar: AppBar(
        title: Text(l?.engineVsEngine ?? 'Engine vs Engine'),
        actions: [
          IconButton(
            tooltip: l?.engineLab ?? 'Engine Lab',
            icon: const Icon(Icons.science_outlined),
            onPressed: _running
                ? null
                : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EngineLabScreen()),
                    ),
          ),
          if (_running)
            IconButton(
              icon: const Icon(Icons.stop, color: Colors.red),
              onPressed: _stopMatch,
            ),
        ],
      ),
      body: Column(
        children: [
          // Board display
          Expanded(
            flex: 3,
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ChessBoard(
                  board: _parseBoardFromFen(_currentFen),
                  whiteToMove: _currentFen.contains(' w '),
                  squareToAlgebraic: _squareToAlgebraic,
                ),
              ),
            ),
          ),

          // Status
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_status, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),

          // Config (when not running)
          if (!_running) ...[
            // Mode toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l?.match ?? 'Match'), icon: const Icon(Icons.sports_esports, size: 16)),
                  ButtonSegment(value: true, label: Text(l?.tournament ?? 'Tournament'), icon: const Icon(Icons.emoji_events, size: 16)),
                ],
                selected: {_tournamentMode},
                onSelectionChanged: (s) => setState(() => _tournamentMode = s.first),
              ),
            ),

            if (!_tournamentMode) ...[
              // Match mode: select two engines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _engineDropdown('White', _engine1Name, (v) => setState(() => _engine1Name = v))),
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(l?.vs ?? 'vs')),
                    Expanded(child: _engineDropdown('Black', _engine2Name, (v) => setState(() => _engine2Name = v))),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text('${l?.games ?? 'Games'}: ', style: const TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      value: _numGames,
                      underline: const SizedBox.shrink(),
                      items: [2, 4, 6, 10, 20].map((n) =>
                        DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                      onChanged: (v) => setState(() => _numGames = v!),
                    ),
                    const SizedBox(width: 16),
                    Text('${l?.depth ?? 'Depth'}: ', style: const TextStyle(fontSize: 13)),
                    DropdownButton<int>(
                      value: _depth,
                      underline: const SizedBox.shrink(),
                      items: [4, 6, 8, 10, 12, 15].map((n) =>
                        DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                      onChanged: (v) => setState(() => _depth = v!),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Tournament mode: select 3+ engines
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l?.selectEngines('${_tournamentEngines.length}') ?? 'Select engines (${_tournamentEngines.length} selected, min 3):',
                      style: const TextStyle(fontSize: 12)),
                    Wrap(
                      spacing: 6,
                      children: _engineChoices.map((choice) => FilterChip(
                        label: Text(choice.label,
                            style: const TextStyle(fontSize: 12)),
                        selected: _tournamentEngines.contains(choice.id),
                        onSelected: (v) => setState(() {
                          if (v) {
                            _tournamentEngines.add(choice.id);
                          } else {
                            _tournamentEngines.remove(choice.id);
                          }
                        }),
                      )).toList(),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Games per pairing, colours alternating.
                        Text('${l?.games ?? 'Games'}: ', style: const TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _numGames,
                          underline: const SizedBox.shrink(),
                          items: [2, 4, 6, 10, 20].map((n) =>
                            DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                          onChanged: (v) => setState(() => _numGames = v!),
                        ),
                        const SizedBox(width: 16),
                        Text('${l?.depth ?? 'Depth'}: ', style: const TextStyle(fontSize: 13)),
                        DropdownButton<int>(
                          value: _depth,
                          underline: const SizedBox.shrink(),
                          items: [4, 6, 8, 10, 12].map((n) =>
                            DropdownMenuItem(value: n, child: Text('$n'))).toList(),
                          onChanged: (v) => setState(() => _depth = v!),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],

          // Results table
          if (_results.isNotEmpty)
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  // Ratings fitted to all games so far
                  if (_results.isNotEmpty) _ratingsTable(),
                  // Score summary
                  if (scores.isNotEmpty && !_tournamentMode)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: scores.entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Chip(
                            label: Text('${_labelForId(e.key)}: ${e.value}',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        )).toList(),
                      ),
                    ),
                  // Game list
                  Expanded(
                    child: ListView.builder(
                      itemCount: _results.length,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemBuilder: (context, index) {
                        final r = _results[index];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: r.outcome == GameOutcome.whiteWin
                                ? Colors.green
                                : r.outcome == GameOutcome.blackWin
                                    ? Colors.red
                                    : r.outcome == GameOutcome.draw
                                        ? Colors.grey
                                        : Colors.orange,
                            child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                          ),
                          title: Text('${r.white} vs ${r.black}', style: const TextStyle(fontSize: 12)),
                          subtitle: Text(
                              '${r.result} — ${r.moves} moves'
                              '${r.detail == null ? '' : ' · ${r.detail}'}',
                              style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: _running
          ? null
          : FloatingActionButton.extended(
              onPressed: _tournamentMode ? _startTournament : _startMatch,
              icon: const Icon(Icons.play_arrow),
              label: Text(_tournamentMode ? (l?.startTournament ?? 'Start Tournament') : (l?.startMatch ?? 'Start Match')),
            ),
    );
  }

  /// Display label for an engine id, used by every summary line because scores
  /// and standings are keyed by id.
  String _labelForId(String id) => engineLabelForId(id, _profiles);

  Widget _engineDropdown(
      String label, String value, ValueChanged<String> onChanged) {
    final choices = _engineChoices;
    // A selected engine whose profile was deleted while this screen was open
    // is no longer one of the items, and DropdownButton asserts on that.
    final safeValue =
        choices.any((c) => c.id == value) ? value : choices.first.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          items: _engineChoices.map((choice) =>
            DropdownMenuItem(
                value: choice.id,
                child: Text(choice.label,
                    style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) => onChanged(v!),
        ),
      ],
    );
  }

  String _squareToAlgebraic(int row, int col) {
    return '${String.fromCharCode(97 + col)}${8 - row}';
  }

  List<List<ChessPiece?>> _parseBoardFromFen(String fen) {
    final result = List.generate(8, (_) => List<ChessPiece?>.filled(8, null));
    final parts = fen.split(' ');
    final rows = parts[0].split('/');
    for (int r = 0; r < 8 && r < rows.length; r++) {
      int c = 0;
      for (var char in rows[r].split('')) {
        final empty = int.tryParse(char);
        if (empty != null) { c += empty; continue; }
        final color = char == char.toUpperCase() ? PieceColor.white : PieceColor.black;
        final type = _charToType(char.toLowerCase());
        if (c < 8) result[r][c] = ChessPiece(type, color);
        c++;
      }
    }
    return result;
  }

  PieceType _charToType(String c) {
    return switch (c) {
      'p' => PieceType.pawn, 'n' => PieceType.knight, 'b' => PieceType.bishop,
      'r' => PieceType.rook, 'q' => PieceType.queen, 'k' => PieceType.king,
      _ => PieceType.pawn,
    };
  }

  /// Ratings fitted jointly to every finished game (Bradley–Terry), centred
  /// on 1500, with one standard error — a small match mostly measures noise,
  /// and the error bar says so.
  Widget _ratingsTable() {
    // Rated games only, keyed by engine id: a forfeit, an aborted game or a
    // ply-cap adjudication has no score to fit, and two engines that share a
    // display name are not one player.
    final rated = [for (final r in _results) if (r.isRated) r];
    if (rated.isEmpty) return const SizedBox.shrink();
    // The same fit, interval and quality grade the Engine Lab uses: a rating
    // shown here and a rating shown there must not be two different numbers.
    final fit = fitElo(
      games: [
        for (final r in rated)
          (white: r.whiteId, black: r.blackId, score: r.whiteScore ?? 0.5)
      ],
      labels: {
        for (final r in rated) ...{
          r.whiteId: _labelForId(r.whiteId),
          r.blackId: _labelForId(r.blackId),
        },
      },
    );
    final ratings = fit.ratings;
    final l = AppLocalizations.of(context);
    // With exactly two engines — the ordinary case — say whether the
    // difference is bigger than its own uncertainty instead of leaving the
    // reader to compare two numbers that overlap.
    final comparison = ratings.length == 2
        ? fit.compare(ratings.first.engineId, ratings.last.engineId)
        : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Table(
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(2.4),
              2: FlexColumnWidth(2),
              3: FlexColumnWidth(1.4),
            },
            children: [
              TableRow(children: [
                for (final h in [
                  l?.engine ?? 'Engine',
                  l?.rating ?? 'Rating',
                  '+ / = / −',
                  '%',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(h,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
              ]),
              for (final p in ratings)
                TableRow(children: [
                  Text(p.label, style: const TextStyle(fontSize: 12)),
                  Text(
                      p.stdErr.isFinite
                          ? '${p.rating.round()} ± ${(kZ95 * p.stdErr).round()}'
                          : '${p.rating.round()}',
                      style: const TextStyle(fontSize: 12)),
                  Text('${p.wins} / ${p.draws} / ${p.losses}',
                      style: const TextStyle(fontSize: 12)),
                  Text('${p.scorePercent.round()}',
                      style: const TextStyle(fontSize: 12)),
                ]),
            ],
          ),
          if (comparison != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${comparison.verdict} '
                '(±${(kZ95 * comparison.stdErr).toStringAsFixed(0)} Elo)',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final warning in fit.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(warning,
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}
