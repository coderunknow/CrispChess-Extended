/// Executes a [BenchmarkPlan].
///
/// The runner owns the engine lifecycle for the duration of a run — build once,
/// initialise once, apply the configured options once, play every scheduled
/// game, dispose at the end — and turns everything it observes into a
/// [BenchmarkRun]: games, per-move timings, failures, ratings and calibration.
///
/// It never decides that something went well when it did not. An engine that
/// fails to initialise is reported as failed and its games as aborted; an engine
/// that breaks during a game forfeits that game; an engine that keeps breaking
/// is taken out of the run rather than allowed to burn the rest of the schedule.
///
/// Both limits in [BenchmarkConfig] are hard limits. The game cap is spent in
/// the plan (warm-ups included), so the runner cannot exceed it; the wall-clock
/// cap is armed as a timer that stops the engines mid-search, so a run cannot
/// outlive it by the length of one game.
library;

import 'dart:async';

import '../engines/chess_engine.dart';
import '../engines/search_telemetry.dart';
import '../engines/uci_capabilities.dart';
import 'benchmark_config.dart';
import 'benchmark_environment.dart';
import 'benchmark_plan.dart';
import 'benchmark_run.dart';
import 'calibration.dart';
import 'engine_identity.dart';
import 'game_player.dart';
import 'game_record.dart';

/// An engine the runner may build, with the identity it starts from.
class BenchEngineSlot {
  final EngineIdentity identity;
  final ChessEngine Function() build;

  const BenchEngineSlot({required this.identity, required this.build});
}

/// Events the Engine Lab listens to.
sealed class BenchmarkEvent {
  const BenchmarkEvent();
}

/// A game started.
class BenchmarkGameStartedEvent extends BenchmarkEvent {
  final int gameNumber;
  final int totalGames;
  final String whiteLabel;
  final String blackLabel;
  final String openingName;

  const BenchmarkGameStartedEvent({
    required this.gameNumber,
    required this.totalGames,
    required this.whiteLabel,
    required this.blackLabel,
    required this.openingName,
  });
}

/// A move was played, for live progress.
class BenchmarkMoveEvent extends BenchmarkEvent {
  final String fen;
  final String san;
  final bool whiteToMove;
  final int ply;

  const BenchmarkMoveEvent({
    required this.fen,
    required this.san,
    required this.whiteToMove,
    required this.ply,
  });
}

/// A game finished.
class BenchmarkGameFinishedEvent extends BenchmarkEvent {
  final BenchGame game;
  final int gamesCompleted;
  final int totalGames;

  const BenchmarkGameFinishedEvent({
    required this.game,
    required this.gamesCompleted,
    required this.totalGames,
  });
}

/// An engine could not be started, or was taken out of the run.
class BenchmarkEngineFailedEvent extends BenchmarkEvent {
  final String engineId;
  final String label;
  final String reason;

  const BenchmarkEngineFailedEvent({
    required this.engineId,
    required this.label,
    required this.reason,
  });
}

/// The run is over; this is what to store and show.
class BenchmarkFinishedEvent extends BenchmarkEvent {
  final BenchmarkRun run;

  const BenchmarkFinishedEvent(this.run);
}

/// Something worth telling the user while the run continues.
class BenchmarkNoticeEvent extends BenchmarkEvent {
  final String message;

  const BenchmarkNoticeEvent(this.message);
}

class _LiveEngine {
  final BenchEngineSlot slot;
  final ChessEngine engine;

  /// Identity, refined after the handshake (options, self-reported name).
  EngineIdentity identity;
  bool failed = false;
  String? failureReason;
  int initMillis = 0;
  int gamesCompleted = 0;
  int forfeitLosses = 0;
  int consecutiveForfeits = 0;
  final Map<String, String> appliedOptions = {};
  final List<String> warnings = [];

  _LiveEngine(this.slot, this.engine) : identity = slot.identity;

  String get engineId => identity.engineId;

  String get label => identity.label;
}

class BenchmarkRunner {
  final BenchmarkPlan plan;

  /// Builders by engine id. A plan entry without a slot is reported, not
  /// silently dropped.
  final Map<String, BenchEngineSlot> slots;
  final BenchmarkEnvironment environment;

  /// The calibration anchor to apply, if the user declared one.
  final RatingAnchor? anchor;

  /// `manual`, `engine added`, `engine changed`, `quick after version change`.
  final String? trigger;

  /// Called with a partially built run every [partialSaveInterval] games, so a
  /// long benchmark that is closed or killed keeps the games already played.
  final Future<void> Function(BenchmarkRun run)? onProgressSave;
  final int partialSaveInterval;

  /// Configuration warnings from validation, stored with the run so the report
  /// says why a setting was ignored.
  final List<String> validationWarnings;

  final StreamController<BenchmarkEvent> _events =
      StreamController<BenchmarkEvent>.broadcast();
  final List<BenchGame> _games = [];
  final Map<String, _LiveEngine> _live = {};
  final List<String> _warnings = [];

  final DateTime _startedAt = DateTime.now();
  String _stopReason = 'completed';
  bool _cancelled = false;

  /// Set when the configured wall-clock limit expires. It is a separate flag
  /// from [_cancelled] because the report has to be able to say *why* a run
  /// stopped, and because a game cut short by the cap is unfinished, not
  /// cancelled by the user.
  bool _timeCapReached = false;

  /// Fires at the deadline so an in-flight search is stopped instead of being
  /// allowed to run to its own budget after the cap has passed.
  Timer? _deadlineTimer;
  bool _paused = false;
  Completer<void>? _pauseGate;
  int _finished = 0;

  /// Ply within the game in progress, so a move event carries a position in
  /// the game rather than a position in the run.
  int _ply = 0;

  BenchmarkRunner({
    required this.plan,
    required this.slots,
    required this.environment,
    this.anchor,
    this.trigger,
    this.onProgressSave,
    this.partialSaveInterval = 10,
    this.validationWarnings = const [],
  });

  Stream<BenchmarkEvent> get events => _events.stream;

  bool get isPaused => _paused;

  bool get isCancelled => _cancelled;

  Map<String, String> get labels => {
        for (final engine in plan.engines) engine.engineId: engine.label,
      };

  /// Pauses between games. A game in progress is allowed to finish: cutting a
  /// search in half would produce a forfeit that says nothing about the engine.
  void pause() {
    if (_paused || _cancelled) return;
    _paused = true;
    _pauseGate ??= Completer<void>();
  }

  void resume() {
    if (!_paused) return;
    _paused = false;
    final gate = _pauseGate;
    _pauseGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  /// Stops the run. The game in progress ends as cancelled and is not rated.
  void cancel() {
    _cancelled = true;
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    resume();
    for (final live in _live.values) {
      try {
        live.engine.stop();
      } catch (_) {
        // Stopping a dead engine is not an error worth reporting.
      }
    }
  }

  /// Runs the benchmark to completion or until it is stopped.
  Future<BenchmarkRun> run() async {
    final config = plan.config;
    final recorded = plan.recordedGames.length + plan.warmUpGames;
    final clock = Stopwatch()..start();
    _armDeadline(config.maxDuration);

    for (final identity in plan.engines) {
      // Cancellation while the previous engine was starting must not start the
      // next one: a slow handshake (a model load, a WASM instantiation) would
      // otherwise keep the run alive after the user asked it to stop.
      if (_cancelled || _timeCapReached) break;
      final slot = slots[identity.engineId];
      if (slot == null) {
        _warnings.add('No way to build ${identity.label} '
            '(${identity.engineId}); it was left out of the run.');
        continue;
      }
      final live = _LiveEngine(slot, slot.build());
      _live[identity.engineId] = live;
      final init = Stopwatch()..start();
      try {
        await live.engine.initialize();
        init.stop();
        live.initMillis = init.elapsedMilliseconds;
        _applyConfiguration(live, config);
        _refineIdentity(live);
      } catch (error) {
        init.stop();
        live.initMillis = init.elapsedMilliseconds;
        live.failed = true;
        live.failureReason = _describe(error);
        _events.add(BenchmarkEngineFailedEvent(
          engineId: identity.engineId,
          label: identity.label,
          reason: live.failureReason!,
        ));
      }
    }

    for (final planned in plan.games) {
      if (_cancelled) {
        _stopReason = 'cancelled';
        break;
      }
      if (_cancelled) break;
      await _awaitResume();
      if (_cancelled) {
        _stopReason = 'cancelled';
        break;
      }
      if (_deadlinePassed(clock, config.maxDuration)) {
        _stopReason = 'time cap';
        break;
      }
      final white = _live[planned.whiteId];
      final black = _live[planned.blackId];
      if (white == null || black == null) {
        _stopReason = 'engine failure';
        break;
      }
      if (white.failed || black.failed) {
        // Recorded rather than skipped, so the report says "this pairing could
        // not produce a game" instead of quietly leaving it out.
        _recordAborted(planned, white, black);
        continue;
      }
      if (_runningEngines < 2) {
        _stopReason = 'engine failure';
        break;
      }

      final opening = openingForGame(plan, planned);
      _events.add(BenchmarkGameStartedEvent(
        gameNumber: planned.isWarmUp ? 0 : planned.index,
        totalGames: recorded,
        whiteLabel: white.label,
        blackLabel: black.label,
        openingName: opening.name,
      ));

      _ply = 0;
      final game = await playBenchGame(
        index: planned.isWarmUp ? 0 : planned.index,
        whiteId: white.engineId,
        blackId: black.engineId,
        whiteLabel: white.label,
        blackLabel: black.label,
        whiteMove: _requesterFor(white),
        blackMove: _requesterFor(black),
        opening: opening,
        plyCap: config.plyCap,
        depth: config.searchDepth,
        moveTime: config.isTimeBased ? config.timePerMove : null,
        warmUp: planned.isWarmUp,
        cancelled: () => _cancelled,
        stopReason: _gameStop,
        onMove: (fen, san, whiteToMove) {
          if (_cancelled) return;
          _ply++;
          _events.add(BenchmarkMoveEvent(
            fen: fen,
            san: san,
            whiteToMove: whiteToMove,
            ply: _ply,
          ));
        },
      );
      _games.add(game);
      white.gamesCompleted++;
      black.gamesCompleted++;
      _noteOutcome(white, game, white.engineId);
      _noteOutcome(black, game, black.engineId);
      if (game.outcome == GameOutcome.forfeit) {
        // The engine that forfeited may still owe a `bestmove`. Drain both
        // connections before the next game asks either for a move.
        await drainEngine(white.engine);
        await drainEngine(black.engine);
      }

      if (!planned.isWarmUp) _finished++;
      _events.add(BenchmarkGameFinishedEvent(
        game: game,
        gamesCompleted: _finished,
        totalGames: plan.recordedGames.length,
      ));

      if (game.outcome == GameOutcome.cancelled) {
        _stopReason = 'cancelled';
        break;
      }
      if (_timeCapReached) {
        // The game that was cut short is recorded (unrated) and the run ends:
        // the cap is a hard limit, not a target.
        _stopReason = 'time cap';
        break;
      }
      if (!planned.isWarmUp) {
        if (_uncertaintyReached()) {
          _stopReason = 'uncertainty target';
          break;
        }
        if (partialSaveInterval > 0 &&
            _finished % partialSaveInterval == 0 &&
            onProgressSave != null) {
          await _saveProgress();
        }
      }
    }

    clock.stop();
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    // Engines are released before the report is built, but their recorded
    // state (status, forfeits, refined identities) is kept: clearing it here
    // would label every engine "skipped" in the report it just produced.
    await _disposeEngines(keepState: true);
    final run = _buildRun();
    if (onProgressSave != null) {
      try {
        await onProgressSave!(run);
      } catch (error) {
        _warnings.add('The finished run could not be stored: $error');
      }
    }
    if (!_events.isClosed) _events.add(BenchmarkFinishedEvent(run));
    return run;
  }

  /// Releases resources. The stream stays usable for a caller that wants the
  /// final event; call this after `run()` has completed.
  Future<void> dispose() async {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    await _disposeEngines();
    if (!_events.isClosed) await _events.close();
  }

  Future<void> _saveProgress() async {
    try {
      await onProgressSave!(_buildRun(inProgress: true));
    } catch (error) {
      _warnings.add('A partial save failed: $error');
    }
  }

  int get _runningEngines => _live.values.where((live) => !live.failed).length;

  /// Schedules the hard stop, so an engine that is thinking when the budget
  /// runs out is interrupted instead of being waited for.
  void _armDeadline(Duration? limit) {
    _deadlineTimer?.cancel();
    _deadlineTimer = null;
    if (limit == null) return;
    _deadlineTimer = Timer(limit, () {
      if (_cancelled || _timeCapReached) return;
      _timeCapReached = true;
      for (final live in _live.values) {
        try {
          live.engine.stop();
        } catch (_) {
          // A dead engine cannot be stopped, and the game loop is about to end.
        }
      }
      if (!_events.isClosed) {
        _events.add(const BenchmarkNoticeEvent(
            'The wall-clock limit was reached; the run is stopping.'));
      }
    });
  }

  bool _deadlinePassed(Stopwatch clock, Duration? limit) {
    if (limit == null) return false;
    if (_timeCapReached) return true;
    if (clock.elapsed >= limit) {
      _timeCapReached = true;
      return true;
    }
    return false;
  }

  /// What to tell the game loop about why it should stop, if it should.
  GameStop _gameStop() {
    if (_cancelled) return GameStop.cancelled;
    if (_timeCapReached) return GameStop.durationLimit;
    return GameStop.none;
  }

  Future<void> _awaitResume() async {
    while (_paused && !_cancelled) {
      final gate = _pauseGate ??= Completer<void>();
      await gate.future;
    }
  }

  MoveRequester _requesterFor(_LiveEngine live) {
    final engine = live.engine;
    // The cast is deliberate: the conditional's static type is the engine's,
    // and Dart does not narrow it to the optional interface on its own.
    final telemetry =
        engine is SearchTelemetry ? engine as SearchTelemetry : null;
    final config = plan.config;
    return measuredRequester(
      (position) => engine.bestMove(
        position,
        depth: config.searchDepth,
        moveTime: config.isTimeBased ? config.timePerMove : null,
      ),
      statsOf: telemetry == null ? null : () => telemetry.lastSearchStatistics,
    );
  }

  void _applyConfiguration(_LiveEngine live, BenchmarkConfig config) {
    final engine = live.engine;
    final aware = engine is UciOptionAware ? engine as UciOptionAware : null;
    final requested = config.requestedOptions();
    for (final entry in requested.entries) {
      if (aware == null) {
        live.warnings.add('${live.label} has no UCI option interface; '
            '"${entry.key} = ${entry.value}" was not applied.');
        continue;
      }
      if (!aware.advertisesOption(entry.key)) {
        live.warnings.add('${live.label} does not advertise "${entry.key}"; '
            '"${entry.key} = ${entry.value}" was not applied.');
        continue;
      }
      try {
        aware.applyOption(entry.key, entry.value);
        live.appliedOptions[entry.key] = entry.value;
      } catch (error) {
        live.warnings.add('${live.label}: applying "${entry.key}" failed: '
            '$error');
      }
    }
    if (aware == null) {
      return;
    }
    live.identity = live.identity.withConfiguration(live.appliedOptions);
  }

  void _refineIdentity(_LiveEngine live) {
    final engine = live.engine;
    final aware = engine is UciOptionAware ? engine as UciOptionAware : null;
    final options = aware?.advertisedOptionNames ?? const <String>[];
    live.identity = live.identity.withAdvertisedOptions(options);
    if (options.isEmpty) {
      live.warnings.add('${live.label} advertised no UCI options; the report '
          'records that rather than assuming defaults.');
    }
  }

  void _noteOutcome(_LiveEngine live, BenchGame game, String engineId) {
    if (game.outcome == GameOutcome.forfeit && game.forfeitedBy == engineId) {
      live.forfeitLosses++;
      live.consecutiveForfeits++;
      // Three forfeits in a row means the engine is not coming back; letting it
      // forfeit the rest of the schedule would fill the report with noise and
      // take hours.
      if (live.consecutiveForfeits >= 3 && !live.failed) {
        live.failed = true;
        live.failureReason = 'Failed to complete three games in a row '
            '(${game.forfeitReason.id}: ${game.detail ?? 'no detail'}).';
        _events.add(BenchmarkEngineFailedEvent(
          engineId: engineId,
          label: live.label,
          reason: live.failureReason!,
        ));
      }
    } else if (game.outcome.isTerminal) {
      live.consecutiveForfeits = 0;
    }
  }

  void _recordAborted(
      PlannedGame planned, _LiveEngine white, _LiveEngine black) {
    final failedSide = white.failed ? white : black;
    final detail = '${failedSide.label} was unavailable: '
        '${failedSide.failureReason ?? 'engine failure'}';
    final game = BenchGame(
      index: planned.index,
      whiteId: white.engineId,
      blackId: black.engineId,
      whiteLabel: white.label,
      blackLabel: black.label,
      openingId: plan.config.openingSuiteId,
      openingName: openingForGame(plan, planned).name,
      startFen: '',
      moves: const [],
      movetext: '',
      outcome: GameOutcome.aborted,
      detail: detail,
      warmUp: planned.isWarmUp,
    );
    _games.add(game);
    if (!planned.isWarmUp) _finished++;
    _events.add(BenchmarkGameFinishedEvent(
      game: game,
      gamesCompleted: _finished,
      totalGames: plan.recordedGames.length,
    ));
  }

  bool _uncertaintyReached() {
    final config = plan.config;
    if (!config.adaptiveStopping) return false;
    final target = config.targetStdErr;
    if (target == null || target <= 0) return false;
    final rated = [
      for (final game in _games)
        if (!game.warmUp) game
    ];
    if (rated.length < config.minGamesBeforeStopping) return false;
    // A fit per game is wasted work; two games is soon enough to stop on and
    // keeps the cost invisible.
    if (rated.length.isOdd) return false;
    final fit = fitRunRatings(
      games: rated,
      labels: labels,
      config: config,
    );
    if (fit.ratings.length < 2) return false;
    for (final rating in fit.ratings) {
      if (!rating.stdErr.isFinite || rating.stdErr > target) return false;
    }
    _events.add(BenchmarkNoticeEvent(
        'Uncertainty target reached (every rating within ±$target Elo).'));
    return true;
  }

  Future<void> _disposeEngines({bool keepState = false}) async {
    for (final live in _live.values) {
      try {
        live.engine.dispose();
      } catch (error) {
        _warnings.add('${live.label} could not be disposed cleanly: $error');
      }
    }
    if (!keepState) _live.clear();
  }

  BenchmarkRun _buildRun({bool inProgress = false}) {
    final config = plan.config;
    final identities = <EngineIdentity>[];
    final status = <String, EngineRunStatus>{};
    for (final identity in plan.engines) {
      final live = _live[identity.engineId];
      identities.add(live?.identity ?? identity);
      if (live == null) {
        status[identity.engineId] = const EngineRunStatus(
          status: 'skipped',
          reason: 'No way to build this engine on this platform.',
        );
        continue;
      }
      if (live.failed) {
        status[identity.engineId] = EngineRunStatus(
          status: 'failed',
          reason: live.failureReason,
          gamesCompleted: live.gamesCompleted,
        );
      } else if (live.forfeitLosses > 0) {
        status[identity.engineId] = EngineRunStatus(
          status: 'partial',
          reason: '${live.forfeitLosses} forfeited game(s).',
          gamesCompleted: live.gamesCompleted,
        );
      } else {
        status[identity.engineId] = EngineRunStatus(
          status: inProgress ? 'in progress' : 'completed',
          gamesCompleted: live.gamesCompleted,
        );
      }
    }

    final labelMap = {
      for (final identity in identities) identity.engineId: identity.label,
    };
    final ratings = fitRunRatings(
      games: _games,
      labels: labelMap,
      config: config,
    );
    final calibration = calibrateElo(
      fit: ratings,
      anchor: anchor,
      config: config,
      identities: identities,
    );

    final warnings = <String>[
      ..._warnings,
      for (final live in _live.values) ...live.warnings,
      if (inProgress) 'This run was still in progress when it was saved.',
    ];

    return BenchmarkRun(
      id: newRunId(_startedAt),
      startedAt: _startedAt,
      finishedAt: DateTime.now(),
      config: config,
      format: plan.format,
      engines: identities,
      engineStatus: status,
      games: List<BenchGame>.of(_games),
      ratings: ratings,
      calibration: calibration,
      environment: environment,
      stopReason: inProgress ? 'in progress' : _stopReason,
      warnings: warnings,
      validationWarnings: [...validationWarnings, ...plan.warnings],
      trigger: trigger,
    );
  }
}

/// A run id that sorts roughly by time and stays unique.
String newRunId(DateTime startedAt) {
  final stamp = startedAt.millisecondsSinceEpoch.toRadixString(36);
  final noise = startedAt.microsecond.toRadixString(36);
  return 'run-$stamp-$noise';
}

String _describe(Object error) {
  final text = error.toString();
  return text.length <= 400 ? text : '${text.substring(0, 400)}…';
}
