import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'chess_engine.dart';
import 'engine_initialization.dart';
import 'uci_position.dart';
import 'uci_search_coordinator.dart';

@JS('cachedFetch')
external JSPromise<JSObject> _cachedFetch(JSString url, JSString cacheName);

/// Available Stockfish versions for web (all GPL-3.0, downloaded at runtime).
enum StockfishVersion {
  sf10('Stockfish 10', 'https://cdn.jsdelivr.net/npm/stockfish.js@10.0.2/stockfish.js', 2800, '~1MB'),
  sf18asm('Stockfish 18 (NNUE)', 'https://huggingface.co/cstr/stockfish-js-wasm/resolve/main/stockfish-18-asm.js', 3400, '~10MB');

  final String label;
  final String url;
  final int elo;
  final String size;

  /// The Stockfish release this build is, as a version string.
  String get versionNumber => switch (this) {
        StockfishVersion.sf10 => '10',
        StockfishVersion.sf18asm => '18',
      };

  const StockfishVersion(this.label, this.url, this.elo, this.size);
}

/// Stockfish engine running as a Web Worker via stockfish.js (WASM/JS).
///
/// Uses nmrugg/stockfish.js compiled Stockfish which communicates
/// via postMessage (UCI protocol over Web Worker messages).
/// GPL-3.0 licensed — downloaded at runtime, never bundled in app binary.
class StockfishEngine
    with UciSearchCoordinator
    implements ChessEngine, EngineRuntimeReport, DownloadAwareEngine {
  final StockfishVersion sfVersion;
  web.Worker? _worker;
  String? _blobUrl;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  late final EngineInitCoordinator _init = EngineInitCoordinator(_stateNotifier);
  final _evalController = StreamController<EvalInfo>.broadcast();
  final Duration handshakeTimeout;
  final Duration readinessTimeout;
  String _detectedName = '';
  Completer<void>? _uciOk;
  Completer<void>? _readyOk;

  // Pre-compiled regex for parsing UCI output
  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r'multipv (\d+)');

  StockfishEngine({
    StockfishVersion? sfVersion,
    String? variantId,
    String? executablePath,
    this.handshakeTimeout = const Duration(seconds: 15),
    this.readinessTimeout = const Duration(seconds: 15),
  }) : sfVersion = sfVersion ?? _versionFromId(variantId);

  static StockfishVersion _versionFromId(String? id) {
    return switch (id) {
      'sf10' => StockfishVersion.sf10,
      'sf18asm' || 'sf18lite' => StockfishVersion.sf18asm,
      _ => StockfishVersion.sf10,
    };
  }

  @override
  String get name => 'Stockfish';
  @override
  String get version => sfVersion.label;
  @override
  String get license => 'GPL-3.0';
  @override
  int get estimatedElo => sfVersion.elo;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // stockfish.js runs in a Web Worker — its search does not block the UI
  // thread and it answers `stop`, so pondering is safe.
  @override
  bool get canPonder => true;

  @override
  void sendUci(String command) => _send(command);

  static bool get isAvailable => kIsWeb;

  @override
  EngineInitializationException? get initializationError => _init.lastFailure;
  @override
  String get effectiveBackend => 'javascript-worker';
  @override
  String? get fallbackReason => null;
  @override
  String? get requestedVersion => sfVersion.versionNumber;
  @override
  String? get detectedVersion => _detectedName.isEmpty
      ? null
      : (RegExp(r'(\d+(?:\.\d+)*)').firstMatch(_detectedName)?.group(1) ??
          _detectedName);

  /// The browser cache is opaque from Dart, so the requirement is always
  /// reported; a cached copy simply makes the "download" instant.
  @override
  Future<EngineDownloadRequirement?> pendingDownload() async =>
      EngineDownloadRequirement(
        description: '${sfVersion.label} (stockfish.js, ${sfVersion.size}; '
            'cached by the browser after the first load)',
        source: Uri.parse(sfVersion.url),
        license: 'GPL-3.0',
      );

  /// Starts the Web Worker and completes only once it has answered `uciok`
  /// and `readyok`; otherwise throws a structured
  /// [EngineInitializationException]. dev3 and earlier caught every error,
  /// set `error` and returned normally, matched any line *containing*
  /// "uciok", and reported ready before `readyok` arrived.
  @override
  Future<void> initialize() => _init.run(
        engine: name,
        version: version,
        requestedVersion: sfVersion.versionNumber,
        backend: effectiveBackend,
        body: _start,
        cleanup: _terminateWorker,
      );

  Future<void> _start(EngineInitScope scope) async {
    _terminateWorker();
    debugPrint('[StockfishWeb] Loading ${sfVersion.label} from CDN...');
    scope.stage = EngineInitStage.download;
    scope.runtimePath = sfVersion.url;
    // Fetch JS source (cached), create blob URL for same-origin Worker loading
    final jsResponse =
        await _cachedFetch(sfVersion.url.toJS, 'crispchess-engines'.toJS).toDart;
    final jsBlob = await (jsResponse as web.Response).blob().toDart;
    scope.checkCancelled();

    scope.stage = EngineInitStage.loadBackend;
    final blobUrl = web.URL.createObjectURL(jsBlob);
    _blobUrl = blobUrl;
    final worker = web.Worker(blobUrl.toJS);
    _worker = worker;
    debugPrint('[StockfishWeb] Worker created from blob');

    // `ignore` marks an early error as handled until it is awaited below.
    _uciOk = Completer<void>()..future.ignore();
    worker.onmessage = ((web.MessageEvent event) {
      final data = event.data;
      if (data == null) return;
      final line = data.toString();
      _handleOutput(line);
    }).toJS;
    // A script that fails to load or throws reports here; without a handler
    // the handshake simply timed out with no cause.
    worker.onerror = ((web.Event event) {
      // ErrorEvent.message when present; extension types cannot be
      // runtime-checked, so read the property instead of an `is` test.
      final message =
          event.getProperty<JSAny?>('message'.toJS)?.dartify()?.toString() ??
              event.type;
      _failPending(EngineStartupFailure(
          EngineFailureKind.backendInitializationFailed,
          'the Stockfish Web Worker reported an error',
          cause: StateError('Worker error: $message')));
    }).toJS;

    scope.stage = EngineInitStage.handshake;
    _send('uci');
    await _uciOk!.future.timeout(handshakeTimeout);
    scope.detectedVersion = detectedVersion;
    scope.checkCancelled();

    scope.stage = EngineInitStage.readiness;
    _readyOk = Completer<void>()..future.ignore();
    _send('isready');
    await _readyOk!.future.timeout(readinessTimeout);
    debugPrint('[StockfishWeb] ${sfVersion.label} ready ($_detectedName)');
  }

  void _failPending(Object failure) {
    for (final pending in [_uciOk, _readyOk]) {
      if (pending != null && !pending.isCompleted) pending.completeError(failure);
    }
    _uciOk = null;
    _readyOk = null;
  }

  void _terminateWorker() {
    _worker?.terminate();
    _worker = null;
    final blobUrl = _blobUrl;
    _blobUrl = null;
    if (blobUrl != null) web.URL.revokeObjectURL(blobUrl);
  }

  void _send(String command) {
    debugPrint('[StockfishWeb] >> $command');
    _worker?.postMessage(command.toJS);
  }

  void _handleOutput(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    // Handshake replies are whole lines: `uciok` must not be matched inside,
    // say, an option name or an `info string`.
    if (trimmed.startsWith('id name ')) {
      _detectedName = trimmed.substring(8).trim();
      return;
    }
    if (trimmed == 'uciok') {
      final pending = _uciOk;
      _uciOk = null;
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }
    if (trimmed == 'readyok') {
      final pending = _readyOk;
      _readyOk = null;
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }

    // Parse evaluation info
    if (trimmed.startsWith('info') && trimmed.contains('depth')) {
      final cpMatch = _cpRegex.firstMatch(trimmed);
      final mateMatch = _mateRegex.firstMatch(trimmed);
      final depthMatch = _depthRegex.firstMatch(trimmed);
      final pvMatch = _pvRegex.firstMatch(trimmed);
      final mpvMatch = _multipvRegex.firstMatch(trimmed);

      if (depthMatch != null && (cpMatch != null || mateMatch != null)) {
        final double sideToMoveScore;
        if (cpMatch != null) {
          sideToMoveScore = int.parse(cpMatch.group(1)!) / 100.0;
        } else {
          // A forced mate carries no `cp` score and used to be dropped, so the
          // bar froze on mating positions.
          final mateIn = int.parse(mateMatch!.group(1)!);
          sideToMoveScore = mateIn > 0 ? 999.0 : -999.0;
        }
        final pv = pvMatch?.group(1);
        _evalController.add(EvalInfo(
          // UCI reports from the side to move; the app consumes White's.
          score: searchWhiteToMove ? sideToMoveScore : -sideToMoveScore,
          depth: int.parse(depthMatch.group(1)!),
          bestMove: pv?.split(' ').first,
          pv: pv,
          pvIndex: mpvMatch != null ? int.parse(mpvMatch.group(1)!) : 1,
        ));
      }
    }

    // Parse bestmove
    if (trimmed.startsWith('bestmove')) {
      final parts = trimmed.split(' ');
      finishSearch(
          parts.length >= 2 && parts[1] != '(none)' ? parts[1] : null);
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) async {
    if (_worker == null) throw StateError('Engine not initialized');
    _stateNotifier.value = EngineState.thinking;

    // Apply skill level
    if (skillLevel != null) {
      _send('setoption name Skill Level value $skillLevel');
    }

    // Search by time, not by a fixed depth. `Skill Level` caps Stockfish's
    // *strength*, not its search time, so `go depth N` cost whatever depth N
    // costs in the current position — cheap in the opening, seconds by the
    // middlegame, and worse every move. A movetime budget is flat across the
    // whole game.
    final go = uciGoCommand(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    final cap = uciSearchTimeout(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);

    final move = await startSearch(
            positionCommand,
            go,
            awaitMove: true,
            // Belongs to the search, not the engine: `info` lines from the
            // search being stopped are still arriving when this one starts.
            whiteToMove: positionCommandIsWhiteToMove(positionCommand))
        .timeout(cap, onTimeout: () {
      abandonSearch();
      return null;
    });
    if (move == null) throw TimeoutException('Search timed out');
    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false, int multiPv = 1}) {
    if (_worker == null) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;

    _send('setoption name Skill Level value 20');
    _send('setoption name MultiPV value $multiPv');
    startSearch(positionCommand,
        infinite ? 'go infinite' : 'go depth ${depth ?? 20}',
        awaitMove: false,
        whiteToMove: positionCommandIsWhiteToMove(positionCommand));

    return _evalController.stream;
  }

  @override
  void stop() {
    if (isSearching) _send('stop');
    // Only a live search goes back to `ready`: a failed or disposed engine
    // must not be reported as usable.
    if (_stateNotifier.value == EngineState.thinking) {
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  void setOption(String name, String value) {
    _send('setoption name $name value $value');
  }

  @override
  void dispose() {
    if (_init.disposed) return;
    _init.markDisposed();
    _failPending(StateError('Stockfish was disposed during initialization'));
    resetSearches();
    _terminateWorker();
    if (!_evalController.isClosed) _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }
}
