// Downloadable Stockfish engine for iOS.
//
// Pattern: same as downloading a GGUF model for an LLM app.
// 1. App code (MIT) acts as the "runtime/interpreter"
// 2. stockfish.js (GPL) is downloaded as "data" at runtime
// 3. Executed in a Web Worker inside WebKit (StockfishJSBridge.swift), not
//    linked into the app
//
// Desktop/Android use the native process engine (stockfish_engine.dart); the
// web build uses stockfish_web_engine.dart.
//
// Legal basis: The app binary contains no GPL code. The GPL-licensed
// stockfish.js is downloaded separately by user choice, like a browser
// downloading and running a GPL web application.
//
// Initialization follows the shared contract (engine_initialization.dart):
// it either completes with the engine ready or throws a structured
// EngineInitializationException naming the failed step (download, loading the
// WebKit harness, `uciok`, `readyok`). dev3 and earlier caught every error,
// logged it and returned normally.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'chess_engine.dart';
import 'engine_initialization.dart';
import 'uci_position.dart';
import 'uci_search_coordinator.dart';

/// The stockfish.js build this engine downloads (GPL-3.0, never bundled).
///
/// This is **Stockfish 10** compiled to JavaScript (`stockfish.js@10.0.2`).
/// dev3 and earlier labelled it "16 (downloaded)", which was not true of the
/// artifact; the label now reports what the runtime says about itself.
const String kStockfishJsPackageVersion = '10.0.2';
const String kStockfishJsRequestedVersion = '10';
const _stockfishJsUrl =
    'https://cdn.jsdelivr.net/npm/stockfish.js@$kStockfishJsPackageVersion/stockfish.js';

/// Status of the Stockfish download
enum DownloadStatus { notDownloaded, downloading, ready, error }

/// Stockfish engine that downloads stockfish.js on first use and runs it in
/// WebKit through the `crispchess/stockfish` bridge (iOS only; the web build
/// uses StockfishWebEngine, desktop/Android the native process engine).
class StockfishDownloadableEngine
    with UciSearchCoordinator
    implements ChessEngine, EngineRuntimeReport, DownloadAwareEngine {
  StockfishDownloadableEngine({
    MethodChannel? channel,
    Future<Directory> Function()? engineDirectory,
    this.handshakeTimeout = const Duration(seconds: 20),
    this.readinessTimeout = const Duration(seconds: 10),
  })  : _channel = channel ?? const MethodChannel('crispchess/stockfish'),
        _engineDirectory = engineDirectory ?? _defaultEngineDir;

  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  late final EngineInitCoordinator _init = EngineInitCoordinator(_stateNotifier);
  final _downloadStatus = ValueNotifier<DownloadStatus>(DownloadStatus.notDownloaded);

  final MethodChannel _channel;
  final Future<Directory> Function() _engineDirectory;
  final Duration handshakeTimeout;
  final Duration readinessTimeout;

  final _evalController = StreamController<EvalInfo>.broadcast();
  bool _initialized = false;
  String _detectedName = '';

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r'pv (\S+)');

  @override
  String get name => 'Stockfish';
  @override
  String get version =>
      detectedVersion ?? '$kStockfishJsRequestedVersion (stockfish.js)';
  @override
  String get license => 'GPL-3.0 (not linked)';
  @override
  int get estimatedElo => 3200;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  ValueNotifier<DownloadStatus> get downloadStatus => _downloadStatus;

  // stockfish.js runs in a Web Worker inside WebKit, off the UI thread, and
  // answers `stop`, so pondering does not block the app.
  @override
  bool get canPonder => true;

  @override
  void sendUci(String command) => _send(command);

  // iOS only: runs stockfish.js inside WebKit via the crispchess/stockfish
  // bridge. Web uses StockfishWebEngine; desktop/Android use the native
  // process-based StockfishEngine.
  static bool get isAvailable => !kIsWeb && Platform.isIOS;

  @override
  EngineInitializationException? get initializationError => _init.lastFailure;
  @override
  String get effectiveBackend => 'javascript-webkit';
  @override
  String? get fallbackReason => null;
  @override
  String? get requestedVersion => kStockfishJsRequestedVersion;
  @override
  String? get detectedVersion => _detectedName.isEmpty
      ? null
      : (RegExp(r'(\d+(?:\.\d+)*)').firstMatch(_detectedName)?.group(1) ??
          _detectedName);

  Completer<void>? _uciOkCompleter;
  Completer<void>? _readyOkCompleter;

  /// Check if stockfish.js is already downloaded/available.
  Future<bool> isDownloaded() async {
    try {
      final dir = await _engineDirectory();
      final file = File('${dir.path}/stockfish.js');
      if (!file.existsSync() || file.lengthSync() == 0) return false;
      // A sidecar written only after a verified, complete download distinguishes
      // an installed file from a truncated one left by an older build.
      final meta = File('${file.path}.json');
      if (!meta.existsSync()) return true; // pre-dev5 install: still runnable
      try {
        final data = jsonDecode(meta.readAsStringSync()) as Map;
        final expected = data['bytes'] as num?;
        return expected == null || expected.toInt() == file.lengthSync();
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  @override
  Future<EngineDownloadRequirement?> pendingDownload() async {
    if (await isDownloaded()) return null;
    return EngineDownloadRequirement(
      description: 'stockfish.js $kStockfishJsPackageVersion (Stockfish '
          '$kStockfishJsRequestedVersion compiled to JavaScript)',
      source: Uri.parse(_stockfishJsUrl),
      license: 'GPL-3.0',
    );
  }

  /// Downloads stockfish.js to local storage. Throws when the download fails;
  /// a partial or error response never replaces a usable file.
  Future<void> download({void Function(double)? onProgress}) async {
    _downloadStatus.value = DownloadStatus.downloading;
    final client = HttpClient();
    File? part;
    try {
      final dir = await _engineDirectory();
      await dir.create(recursive: true);
      final targetFile = File('${dir.path}/stockfish.js');
      part = File('${targetFile.path}.part');

      // Download from CDN (GPL-3.0, never bundled with app)
      debugPrint('[Stockfish] Downloading from $_stockfishJsUrl...');
      final request = await client.getUrl(Uri.parse(_stockfishJsUrl));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}',
            uri: Uri.parse(_stockfishJsUrl));
      }
      final total = response.contentLength;
      var received = 0;
      final sink = part.openWrite();
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
      if (received == 0 || (total > 0 && received != total)) {
        throw HttpException('download truncated ($received of $total bytes)',
            uri: Uri.parse(_stockfishJsUrl));
      }
      await part.rename(targetFile.path);
      debugPrint('[Stockfish] Downloaded to ${targetFile.path}');
      _downloadStatus.value = DownloadStatus.ready;
    } catch (e) {
      debugPrint('[Stockfish] Download failed: $e');
      _downloadStatus.value = DownloadStatus.error;
      rethrow;
    } finally {
      client.close();
      try {
        if (part != null && part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
  }

  @override
  Future<void> initialize() => _init.run(
        engine: name,
        version: version,
        requestedVersion: kStockfishJsRequestedVersion,
        backend: effectiveBackend,
        body: _start,
        cleanup: _teardown,
      );

  Future<void> _start(EngineInitScope scope) async {
    // Ensure engine is downloaded (CDN — never bundled with the app binary).
    scope.stage = EngineInitStage.download;
    if (!await isDownloaded()) {
      await download();
    } else {
      _downloadStatus.value = DownloadStatus.ready;
    }
    scope.checkCancelled();

    scope.stage = EngineInitStage.loadBackend;
    final dir = await _engineDirectory();
    final jsPath = '${dir.path}/stockfish.js';
    scope.runtimePath = jsPath;

    // Receive UCI output from the WebKit-hosted engine.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onOutput') {
        _handleOutput(call.arguments as String);
      }
    });

    // `ignore` marks an early error as handled until the await below. The
    // locals keep the completers after _handleOutput or dispose() clears the
    // fields: the bridge's onOutput call is not ordered with the reply to
    // send/initialize, so `uciok` can arrive before `_send` returns.
    final uciOk = Completer<void>()..future.ignore();
    _uciOkCompleter = uciOk;
    // Load stockfish.js into the WebView; completes once the harness is ready.
    await _channel.invokeMethod('initialize', {'path': jsPath});
    _initialized = true;
    scope.checkCancelled();

    // UCI handshake — wait for the engine's actual replies rather than a
    // fixed delay (the Web Worker may still be compiling stockfish.js).
    scope.stage = EngineInitStage.handshake;
    await _send('uci');
    await uciOk.future.timeout(handshakeTimeout);
    scope.detectedVersion = detectedVersion;
    scope.checkCancelled();

    scope.stage = EngineInitStage.readiness;
    final readyOk = Completer<void>()..future.ignore();
    _readyOkCompleter = readyOk;
    await _send('isready');
    await readyOk.future.timeout(readinessTimeout);
    debugPrint('[Stockfish] Initialized via WebKit JS runtime ($_detectedName)');
  }

  Future<void> _teardown() async {
    final wasInitialized = _initialized;
    _initialized = false;
    _uciOkCompleter = null;
    _readyOkCompleter = null;
    if (!wasInitialized) return;
    try {
      await _channel.invokeMethod('dispose');
    } catch (e) {
      debugPrint('[Stockfish] dispose after failed start: $e');
    }
  }

  Future<void> _send(String command) async {
    if (!_initialized) return;
    await _channel.invokeMethod('send', {'command': command});
  }

  void _handleOutput(String line) {
    final t = line.trim();
    if (t.isEmpty) return;

    if (t.startsWith('id name ')) {
      _detectedName = t.substring(8).trim();
      return;
    }
    if (t == 'uciok') {
      final pending = _uciOkCompleter;
      _uciOkCompleter = null;
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }
    if (t == 'readyok') {
      final pending = _readyOkCompleter;
      _readyOkCompleter = null;
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }
    // The WebKit harness reports a failed Worker or script this way
    // (StockfishJSBridge.swift). During startup it is the failure itself,
    // not something to wait out until the handshake timeout.
    if (t.startsWith('info string worker_error') ||
        t.startsWith('info string harness_error')) {
      final failure = EngineStartupFailure(
          EngineFailureKind.backendInitializationFailed,
          'the WebKit Stockfish worker reported an error',
          cause: StateError(t.substring('info string '.length)));
      for (final pending in [_uciOkCompleter, _readyOkCompleter]) {
        if (pending != null && !pending.isCompleted) {
          pending.completeError(failure);
        }
      }
      _uciOkCompleter = null;
      _readyOkCompleter = null;
      if (_init.isInitializing) return;
    }

    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final mate = _mateRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pv = _pvRegex.firstMatch(t);
      if (d != null && (cp != null || mate != null)) {
        final double sideToMoveScore;
        if (cp != null) {
          sideToMoveScore = int.parse(cp.group(1)!) / 100.0;
        } else {
          final mateIn = int.parse(mate!.group(1)!);
          sideToMoveScore = mateIn > 0 ? 999.0 : -999.0;
        }
        _evalController.add(EvalInfo(
          // UCI reports from the side to move; the app consumes White's.
          score: searchWhiteToMove ? sideToMoveScore : -sideToMoveScore,
          depth: int.parse(d.group(1)!),
          bestMove: pv?.group(1),
        ));
      }
    }

    if (t.startsWith('bestmove')) {
      final parts = t.split(' ');
      finishSearch(
          parts.length >= 2 && parts[1] != '(none)' ? parts[1] : null);
      _stateNotifier.value = EngineState.ready;
    }
  }

  @override
  Future<String> bestMove(String positionCommand, {
    int? depth, Duration? moveTime, int? skillLevel,
  }) async {
    if (!_initialized) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    if (skillLevel != null) {
      await _send('setoption name Skill Level value $skillLevel');
    }
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
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (!_initialized) return const Stream.empty();
    _stateNotifier.value = EngineState.thinking;
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
    final cancelled = StateError('Stockfish was disposed during initialization');
    for (final pending in [_uciOkCompleter, _readyOkCompleter]) {
      if (pending != null && !pending.isCompleted) pending.completeError(cancelled);
    }
    _uciOkCompleter = null;
    _readyOkCompleter = null;
    resetSearches();
    if (_initialized) {
      unawaited(_send('quit').catchError((Object _) {}));
      _channel.invokeMethod('dispose').catchError((Object e) {
        debugPrint('[Stockfish] dispose: $e');
      });
    }
    _initialized = false;
    if (!_evalController.isClosed) _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }

  /// Delete downloaded engine files.
  Future<void> deleteDownload() async {
    final dir = await _engineDirectory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _downloadStatus.value = DownloadStatus.notDownloaded;
  }

  static Future<Directory> _defaultEngineDir() async {
    // App support dir — sandbox-correct on iOS (path_provider), unlike $HOME.
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/engines');
  }
}
