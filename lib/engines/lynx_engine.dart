/// Lynx chess engine — MIT-licensed, ~3350 ELO, classical HCE.
///
/// Downloaded at runtime from GitHub Releases as a self-contained
/// native binary. No .NET runtime required.
///
/// Source: https://github.com/lynx-chess/Lynx
/// License: MIT
/// Supports: UCI protocol, Chess960, multithreading, pondering

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'download_io.dart' show hashFile;
import 'engine_storage.dart' show EngineStorage, EngineStorageError;
import 'engine_artifacts.dart';
import 'engine_initialization.dart';
import 'uci_position.dart';
import 'uci_process_lifecycle.dart';
import 'uci_search_coordinator.dart';

/// GitHub release download URLs for Lynx v1.11.0 (self-contained binaries).
const _lynxVersion = '1.11.0';
const _lynxBaseUrl =
    'https://github.com/lynx-chess/Lynx/releases/download/v$_lynxVersion';

/// Platform → download URL + binary name mapping.
({String url, String binary}) _platformAsset() {
  if (Platform.isMacOS) {
    final arch = Platform.version.contains('arm64') ||
            Platform.operatingSystemVersion.contains('arm64')
        ? 'osx-arm64'
        : 'osx-x64';
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-$arch.zip',
      binary: 'Lynx.Cli',
    );
  }
  if (Platform.isLinux) {
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-linux-x64.zip',
      binary: 'Lynx.Cli',
    );
  }
  if (Platform.isWindows) {
    return (
      url: '$_lynxBaseUrl/Lynx-$_lynxVersion-win-x64.zip',
      binary: 'Lynx.Cli.exe',
    );
  }
  throw UnsupportedError('Lynx not available on this platform');
}

/// Lynx chess engine — downloads and runs as a native UCI process.
class LynxEngine
    with UciSearchCoordinator, UciProcessLifecycle
    implements
        ChessEngine,
        SearchDrainableEngine,
        EngineRuntimeReport,
        DownloadAwareEngine {
  /// Accepted for API parity with the web build, which offers a choice of WASM
  /// bundles. There is nothing to choose on native: it runs one downloaded
  /// binary.
  LynxEngine({String? variantId});

  Process? _process;
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);

  StreamSubscription? _stdoutSub;
  final _evalController = StreamController<EvalInfo>.broadcast();
  String _detectedVersion = _lynxVersion;

  static final _cpRegex = RegExp(r'score cp (-?\d+)');
  static final _mateRegex = RegExp(r'score mate (-?\d+)');
  static final _depthRegex = RegExp(r'depth (\d+)');
  static final _pvRegex = RegExp(r' pv (.+)');
  static final _multipvRegex = RegExp(r'multipv (\d+)');
  static final _idNameRegex = RegExp(r'id name Lynx\s+(.+)');

  @override
  String get name => 'Lynx';
  @override
  String get version => _detectedVersion;
  @override
  String get license => 'MIT';
  @override
  int get estimatedElo => 3350;
  @override
  EngineState get state => _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier => _stateNotifier;

  // Lynx runs as its own process and honours `stop`, so it can ponder.
  @override
  bool get canPonder => true;

  @override
  void sendUci(String command) {
    try {
      _process?.stdin.writeln(command);
    } catch (e) {
      // The process is gone; the exit watcher reports how it ended.
      debugPrint('[Lynx] write failed: $e');
    }
  }

  static bool get isAvailable =>
      !kIsWeb &&
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  String get processLabel => 'Lynx';

  @override
  void onProcessLost() {
    final pending = [_uciOk, _readyOk];
    _uciOk = null;
    _readyOk = null;
    if (pending.any((c) => c != null && !c.isCompleted)) {
      // Died during startup: fail the step with the exit code and stderr.
      unawaited(processDeathReport().then((died) {
        for (final c in pending) {
          if (c != null && !c.isCompleted) c.completeError(died);
        }
      }));
    }
    if (!disposingProcess && !_init.isInitializing) {
      _stateNotifier.value = EngineState.error;
    }
    resetSearches();
  }

  late final EngineInitCoordinator _init = EngineInitCoordinator(_stateNotifier);
  Completer<void>? _uciOk;
  Completer<void>? _readyOk;
  String _idName = '';

  /// How long Lynx may take to answer `uci` and `isready`. The first start
  /// after a download includes the .NET single-file extraction.
  Duration handshakeTimeout = const Duration(seconds: 15);
  Duration readinessTimeout = const Duration(seconds: 15);

  @override
  EngineInitializationException? get initializationError => _init.lastFailure;
  @override
  String get effectiveBackend => 'native-process';
  @override
  String? get fallbackReason => null;
  @override
  String? get requestedVersion => _lynxVersion;
  @override
  String? get detectedVersion => _idName.isEmpty ? null : _detectedVersion;

  @override
  Future<EngineDownloadRequirement?> pendingDownload() async {
    if (await isDownloaded()) return null;
    final ({String url, String binary}) asset;
    try {
      asset = _platformAsset();
    } on UnsupportedError {
      return null;
    }
    return EngineDownloadRequirement(
      description: 'Lynx $_lynxVersion self-contained binary (GitHub release)',
      source: Uri.parse(asset.url),
      license: 'MIT',
    );
  }

  /// Starts Lynx and completes only once it has answered `uciok` and
  /// `readyok`; otherwise throws a structured [EngineInitializationException].
  ///
  /// Downloads the binary first when it is missing (the user picked Lynx);
  /// Engine Preflight asks before that happens via [pendingDownload].
  /// dev3 and earlier caught every error and returned normally, treated
  /// stdout closing as a handshake, and never waited for `readyok`.
  @override
  Future<void> initialize() => _init.run(
        engine: name,
        version: _lynxVersion,
        requestedVersion: _lynxVersion,
        backend: effectiveBackend,
        body: _start,
        cleanup: _closeProcess,
      );

  Future<void> _start(EngineInitScope scope) async {
    _closeProcess();
    scope.stage = EngineInitStage.resolveRuntime;
    final asset = _platformAsset();
    if (!await isDownloaded()) {
      scope.stage = EngineInitStage.download;
      await _download(asset);
    }
    scope.checkCancelled();
    final managed = File('${(await _engineDir()).path}/${asset.binary}');
    final binaryPath = managed.existsSync()
        ? managed.path
        : File('${_legacyDir.path}/${asset.binary}').path;
    scope.runtimePath = binaryPath;

    scope.stage = EngineInitStage.launchProcess;
    debugPrint('[Lynx] Starting: $binaryPath');
    final process = await Process.start(binaryPath, []);
    _process = process;
    watchProcess(process);
    if (scope.cancelled) {
      _closeProcess();
      scope.checkCancelled();
    }

    _uciOk = Completer<void>()..future.ignore();
    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: () {
      // stdout closing is the first sign of death, usually ahead of the exit
      // code: fail a pending handshake now instead of at its timeout.
      releaseOnLoss();
    }, onError: (Object e) {
      debugPrint('[Lynx] stdout error: $e');
      releaseOnLoss();
    });

    // stderr belongs to the lifecycle watch now — it prints each line the
    // same way and keeps the last few for a death report. A second listener
    // here threw "Stream has already been listened to" and left the engine
    // in EngineState.error, which the round robin quietly skips.

    scope.stage = EngineInitStage.handshake;
    process.stdin.writeln('uci');
    await _awaitReply(_uciOk!, handshakeTimeout, scope);
    scope.detectedVersion = detectedVersion;

    // Lynx reserves MoveOverhead milliseconds of every move against losing
    // on time, and honours it for `go movetime` too: a 300ms budget came
    // back in 251ms over a round robin, which is the default 50 subtracted.
    // Nothing here plays to a clock — each move is given its own budget and
    // there is no flag to fall — so most of that reserve is thinking time
    // handed back for nothing. Ten leaves a margin for the pipe without
    // giving up a sixth of the search.
    scope.stage = EngineInitStage.configure;
    process.stdin.writeln('setoption name MoveOverhead value 10');

    scope.stage = EngineInitStage.readiness;
    _readyOk = Completer<void>()..future.ignore();
    process.stdin.writeln('isready');
    await _awaitReply(_readyOk!, readinessTimeout, scope);
    debugPrint('[Lynx] Ready (v$_detectedVersion, ~$estimatedElo ELO)');
  }

  /// Waits for `uciok`/`readyok`, failing with the process's own death report
  /// (exit code, stderr) when it exits first.
  Future<void> _awaitReply(
      Completer<void> reply, Duration timeout, EngineInitScope scope) async {
    try {
      await reply.future.timeout(timeout);
    } on EngineProcessDiedException catch (died) {
      scope.exitCode = died.exitCode;
      scope.stderrTail = died.stderrTail;
      rethrow;
    }
  }

  void _closeProcess() {
    final process = _process;
    _uciOk = null;
    _readyOk = null;
    if (process == null) return;
    beginProcessDispose();
    try {
      process.stdin.writeln('quit');
    } catch (_) {}
    _stdoutSub?.cancel();
    _stdoutSub = null;
    stopWatchingProcess();
    process.kill();
    _process = null;
  }

  void _handleLine(String line) {
    final t = line.trim();

    // Parse "id name Lynx 1.11.0-dev-2e4b458f" → version with commit hash
    if (t.startsWith('id name ')) _idName = t.substring(8).trim();
    if (t.startsWith('id name Lynx')) {
      final m = _idNameRegex.firstMatch(t);
      if (m != null) _detectedVersion = m.group(1)!.replaceAll('-dev', '');
    }
    if (t == 'uciok' || t == 'readyok') {
      final pending = t == 'uciok' ? _uciOk : _readyOk;
      if (t == 'uciok') {
        _uciOk = null;
      } else {
        _readyOk = null;
      }
      if (pending != null && !pending.isCompleted) pending.complete();
      return;
    }

    if (t.startsWith('info') && t.contains('depth')) {
      final cp = _cpRegex.firstMatch(t);
      final mate = _mateRegex.firstMatch(t);
      final d = _depthRegex.firstMatch(t);
      final pvMatch = _pvRegex.firstMatch(t);
      final mpv = _multipvRegex.firstMatch(t);

      if (d != null && (cp != null || mate != null)) {
        final double score;
        if (mate != null) {
          final mateIn = int.parse(mate.group(1)!);
          score = mateIn > 0 ? 100.0 : -100.0; // Large score for mate
        } else {
          score = int.parse(cp!.group(1)!) / 100.0;
        }
        final pv = pvMatch?.group(1);
        _evalController.add(EvalInfo(
          // UCI reports from the side to move; the app consumes White's.
          score: searchWhiteToMove ? score : -score,
          depth: int.parse(d.group(1)!),
          bestMove: pv?.split(' ').first,
          pv: pv,
          pvIndex: mpv != null ? int.parse(mpv.group(1)!) : 1,
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
    if (_process == null) throw StateError('Not initialized');
    _stateNotifier.value = EngineState.thinking;

    // Lynx has no Skill Level option, so strength used to be dialled with a
    // fixed depth — up to `go depth 15`. A given depth costs an order of
    // magnitude more once the position opens up (measured: 0.7s at the start
    // vs 5s by move 5 for the same depth), which is exactly the "it gets
    // slower every turn" symptom. Search by time instead and let the depth
    // fall where it may.
    final go = uciGoCommand(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    final cap = uciSearchTimeout(
        depth: depth, moveTime: moveTime, skillLevel: skillLevel);

    if (processGone) throw await processDeathReport();

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
    if (move == null) {
      // A null answer means one of two very different things, and reporting
      // both as a timeout is what let a crashed engine pass for a slow one.
      if (processGone) throw await processDeathReport();
      throw TimeoutException(
          'No bestmove within ${cap.inMilliseconds}ms', cap);
    }
    return move;
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand, {int? depth, bool infinite = false}) {
    if (_process == null || processGone) {
      // Silently returning an empty stream here is how a dead engine looked
      // like a quiet one: the eval bar simply stopped updating.
      if (processGone) debugPrint('[$processLabel] analysis skipped: process gone');
      return const Stream.empty();
    }
    _stateNotifier.value = EngineState.thinking;
    // Bound the depth search by the clock too. A fixed depth costs whatever
    // that depth costs in the position in front of it — the thing that was
    // taken out of `bestMove` because it turned into seconds per move by the
    // middlegame — and nothing here ever stopped it: analysis has no timeout,
    // so a strong engine asked for depth 20 sits at full CPU until the next
    // move happens to interrupt it. On a phone that is the battery.
    //
    // `infinite` is left alone: it is unbounded on purpose and ends at `stop`.
    startSearch(
        positionCommand,
        infinite
            ? 'go infinite'
            : 'go depth ${depth ?? 20} movetime ${kFixedDepthTimeCap.inMilliseconds}',
        awaitMove: false,
        whiteToMove: positionCommandIsWhiteToMove(positionCommand));
    return _evalController.stream;
  }

  @override
  void stop() {
    // The `bestmove` this triggers still belongs to the running search; the
    // coordinator consumes it so it can't answer the next request.
    if (isSearching) sendUci('stop');
    // Only a live search goes back to `ready`. Reporting it unconditionally
    // turned a disposed engine back into a usable one — and the Engine Lab
    // reuses one process for a whole benchmark, so it has to be able to trust
    // this state.
    if (_stateNotifier.value == EngineState.thinking) {
      _stateNotifier.value = EngineState.ready;
    }
  }

  /// Waits for a stopped search's `bestmove` before the connection is reused.
  @override
  Future<void> drainSearch({Duration timeout = const Duration(seconds: 5)}) =>
      quiesceSearch(timeout: timeout);

  @override
  void setOption(String name, String value) {
    _process?.stdin.writeln('setoption name $name value $value');
  }

  @override
  void dispose() {
    if (_init.disposed) return;
    _init.markDisposed();
    beginProcessDispose();
    final cancelled = StateError('Lynx was disposed during initialization');
    for (final c in [_uciOk, _readyOk]) {
      if (c != null && !c.isCompleted) c.completeError(cancelled);
    }
    resetSearches();
    _closeProcess();
    if (!_evalController.isClosed) _evalController.close();
    _stateNotifier.value = EngineState.disposed;
  }

  // --- Download management ---

  /// Install directory from the single user-selectable engine storage root.
  /// On Android executables must stay app-private, which the storage location
  /// reports; the loader follows it instead of assuming a writable shared path.
  static Future<Directory> _engineDir() async {
    final location = await EngineStorage().location();
    return Directory('${location.executableRoot}/lynx/$_lynxVersion/bin');
  }

  /// Pre-dev5 install location, still read so an existing binary keeps working
  /// after the storage root moved to one managed location.
  static Directory get _legacyDir {
    final home = Platform.environment['HOME'] ??
        Platform.environment['APPDATA'] ?? '/tmp';
    return Directory('$home/.crispchess/engines/lynx');
  }

  /// Check if Lynx binary exists locally.
  static Future<bool> isDownloaded() async {
    try {
      final dir = await _engineDir();
      final asset = _platformAsset();
      if (File('${dir.path}/${asset.binary}').existsSync()) return true;
      return File('${_legacyDir.path}/${asset.binary}').existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Downloads and extracts the platform's Lynx binary into the engine
  /// directory. Throws on any failure and leaves no partial file behind: a
  /// non-200 response, a truncated body, a failed extraction or a binary that
  /// is not where the archive should have put it are all errors. (dev3 and
  /// earlier wrote whatever came back — an HTML error page included — and
  /// ignored the unzip and chmod exit codes.)
  Future<void> _download(({String url, String binary}) asset) async {
    final dir = await _engineDir();
    final binaryFile = File('${dir.path}/${asset.binary}');
    debugPrint('[Lynx] Downloading from ${asset.url}...');
    await dir.create(recursive: true);
    // Expand-Archive (Windows) accepts only a `.zip` extension.
    final zipFile = File('${dir.path}/lynx.part.zip');
    final client = HttpClient(); // follows GitHub's redirect chain itself
    try {
      final request = await client.getUrl(Uri.parse(asset.url));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}',
            uri: Uri.parse(asset.url));
      }
      final expected = response.contentLength;
      await response.pipe(zipFile.openWrite());
      final received = zipFile.lengthSync();
      if (received == 0 || (expected > 0 && received != expected)) {
        throw HttpException(
            'download truncated ($received of $expected bytes)',
            uri: Uri.parse(asset.url));
      }

      final published = kLynxPublishedSha256[asset.url];
      if (published != null) {
        final actual = await hashFile(zipFile.path);
        if (actual != published) {
          throw const EngineStorageError(
              'The downloaded Lynx archive did not match the checksum '
              'published with the release; nothing was installed.');
        }
      }
      // Extract into a staging directory and only move the verified binary
      // into place, so a half-extracted archive never becomes "installed".
      final staging = Directory('${dir.path}/.staging-${DateTime.now().microsecondsSinceEpoch}');
      await staging.create(recursive: true);
      debugPrint('[Lynx] Extracting...');
      final ProcessResult unzip = Platform.isWindows
          ? await Process.run('powershell', [
              '-NoProfile',
              '-command',
              'Expand-Archive', '-Path', zipFile.path, '-DestinationPath',
              staging.path, '-Force',
            ])
          : await Process.run('unzip', ['-o', zipFile.path, '-d', staging.path]);
      if (unzip.exitCode != 0) {
        throw ProcessException(Platform.isWindows ? 'powershell' : 'unzip',
            const [], 'extracting Lynx failed: ${unzip.stderr}', unzip.exitCode);
      }
      final staged = File('${staging.path}/${asset.binary}');
      if (!staged.existsSync()) {
        throw FileSystemException(
            'the Lynx archive did not contain ${asset.binary}', staged.path);
      }
      await staged.copy(binaryFile.path);
      await staging.delete(recursive: true);
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', ['+x', binaryFile.path]);
        if (chmod.exitCode != 0) {
          throw ProcessException('chmod', ['+x', binaryFile.path],
              '${chmod.stderr}', chmod.exitCode);
        }
      }
      // Strip archive metadata: extraction can carry exec bits or extended
      // attributes that make a later atomic replacement fail.
      debugPrint('[Lynx] Ready at ${redactPath(binaryFile.path)}');
    } catch (_) {
      // A half-extracted binary would pass isDownloaded() next time.
      try {
        if (binaryFile.existsSync()) binaryFile.deleteSync();
      } catch (_) {}
      rethrow;
    } finally {
      client.close();
      try {
        if (zipFile.existsSync()) zipFile.deleteSync();
      } catch (_) {}
    }
  }

  /// Delete downloaded engine files.
  static Future<void> deleteDownload() async {
    final dir = await _engineDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}
