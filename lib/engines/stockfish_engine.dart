// Stockfish engine for native platforms.
//
// Desktop (Windows/macOS/Linux): runs a Stockfish executable that is installed
//   on this computer. The app never bundles GPL Stockfish (see NOTICE.md); the
//   executable is located by [resolveStockfishRuntime] — an explicit path, the
//   CRISPCHESS_STOCKFISH_PATH environment variable, PATH, then the usual
//   package-manager locations that a GUI app does not inherit on its PATH.
// Android: runs `assets/bin/stockfish-android` when a build bundles one. The
//   release builds do not (the asset is not declared in pubspec.yaml), so this
//   is reported as `runtimeMissing` rather than attempted and swallowed.
// iOS: delegates to StockfishDownloadableEngine, which runs stockfish.js
//   (downloaded at runtime) inside WebKit — no subprocess, no GPL in binary.
//
// The process protocol itself — launch, `uci`/`uciok`, `isready`/`readyok`,
// process death, timeouts, teardown, concurrent initialization and disposal —
// is the custom-UCI implementation in generic_uci_engine.dart, which is the
// path user-added engines already exercise. dev3 and earlier had a second,
// weaker copy here that swallowed every startup failure, treated stdout
// closing as a handshake, never awaited `readyok` and reported "ready"
// unconditionally; the Engine Lab then saw only
// "Bad state: initialize returned with state error".

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import 'chess_engine.dart';
import 'engine_initialization.dart';
import 'generic_uci_engine.dart';
import 'search_telemetry.dart';
import 'stockfish_downloadable_engine.dart';
import 'uci_capabilities.dart';

/// The Stockfish version the built-in desktop/Android engine is meant to be.
///
/// A request, not a measurement: the version that runs is whatever the
/// executable reports in `id name`, recorded as [StockfishEngine.detectedVersion]
/// and used for the engine's label and benchmark identity.
const String kStockfishRequestedVersion = '16';

/// Environment variable naming the Stockfish executable explicitly.
const String kStockfishPathEnvironment = 'CRISPCHESS_STOCKFISH_PATH';

/// Where the built-in Stockfish executable was found.
class StockfishRuntime {
  final String path;

  /// `explicit`, `environment`, `path`, `well-known` or `android-asset`.
  final String source;

  const StockfishRuntime(this.path, this.source);
}

/// SHA-256 over the executable's location and its contents' SHA-256, or null
/// when the file cannot be read. A replaced file or a different path (another
/// `CRISPCHESS_STOCKFISH_PATH`, another install on `PATH`) changes it; the path
/// itself cannot be read back from it.
Future<String?> stockfishRuntimeDigest(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final contents = await crypto.sha256.bind(file.openRead()).first;
    return crypto.sha256
        .convert(utf8.encode('${file.absolute.path}\n$contents'))
        .toString();
  } catch (_) {
    return null;
  }
}

/// How to find the executable; replaceable in tests.
typedef StockfishRuntimeResolver = Future<StockfishRuntime> Function();

/// Message shown when no executable can be found, per platform.
String stockfishInstallHint() {
  if (Platform.isAndroid) {
    return 'This build does not bundle a Stockfish executable for Android '
        '(Stockfish is GPL-licensed and kept separate from the app).';
  }
  final how = Platform.isWindows
      ? 'install it with "winget install Stockfish.Stockfish" or download it '
          'from stockfishchess.org'
      : Platform.isMacOS
          ? 'install it with "brew install stockfish"'
          : 'install it with your package manager (e.g. "sudo apt install '
              'stockfish")';
  return 'No Stockfish executable was found on this computer. To use the '
      'built-in Stockfish, $how, or set $kStockfishPathEnvironment to the '
      'executable. A downloaded Stockfish can also be added in the Engine '
      'Manager as a custom UCI engine.';
}

/// Directories on PATH, split the platform's way.
List<String> _pathDirectories(Map<String, String> environment) {
  final raw = environment['PATH'] ?? environment['Path'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  return [
    for (final entry in raw.split(separator))
      if (entry.trim().isNotEmpty) entry.trim().replaceAll('"', '')
  ];
}

/// Locations package managers install to that a GUI app often does not have
/// on its PATH (Finder-launched apps on macOS get a minimal PATH; Debian puts
/// Stockfish in /usr/games; winget links live under LOCALAPPDATA).
List<String> stockfishWellKnownLocations(Map<String, String> environment) {
  if (Platform.isMacOS) {
    return const [
      '/opt/homebrew/bin/stockfish',
      '/usr/local/bin/stockfish',
      '/opt/local/bin/stockfish',
    ];
  }
  if (Platform.isLinux) {
    return const [
      '/usr/games/stockfish',
      '/usr/bin/stockfish',
      '/usr/local/bin/stockfish',
      '/snap/bin/stockfish',
    ];
  }
  if (Platform.isWindows) {
    final local = environment['LOCALAPPDATA'];
    return [
      if (local != null) '$local\\Microsoft\\WinGet\\Links\\stockfish.exe',
    ];
  }
  return const [];
}

bool _isExecutableFile(String path) {
  final stat = FileStat.statSync(path);
  if (stat.type != FileSystemEntityType.file &&
      stat.type != FileSystemEntityType.link) {
    return false;
  }
  if (Platform.isWindows) return true;
  // Any execute bit. The launch itself is the real test; this only keeps a
  // non-executable file on PATH from shadowing a working one later on PATH.
  return stat.mode & 0x49 != 0;
}

/// Finds the Stockfish executable, or throws an [EngineStartupFailure] that
/// says which kind of "not found" it is.
///
/// Explicit choices are authoritative: a wrong [explicitPath] or environment
/// variable is reported as such instead of silently falling back to some other
/// Stockfish found on PATH.
Future<StockfishRuntime> resolveStockfishRuntime({
  String? explicitPath,
  Map<String, String>? environment,
}) async {
  final env = environment ?? Platform.environment;
  final configured = explicitPath ??
      ((env[kStockfishPathEnvironment] ?? '').isNotEmpty
          ? env[kStockfishPathEnvironment]
          : null);
  if (configured != null) {
    final source = explicitPath != null ? 'explicit' : 'environment';
    final type = FileSystemEntity.typeSync(configured);
    if (type == FileSystemEntityType.notFound) {
      throw EngineStartupFailure(
        EngineFailureKind.binaryMissing,
        source == 'explicit'
            ? 'the configured Stockfish executable does not exist'
            : '$kStockfishPathEnvironment names a file that does not exist',
        cause: FileSystemException('Stockfish executable not found', configured),
      );
    }
    if (!_isExecutableFile(configured)) {
      throw EngineStartupFailure(
        EngineFailureKind.permissionDenied,
        'the configured Stockfish file is not an executable file',
        cause: FileSystemException('Not executable', configured),
      );
    }
    return StockfishRuntime(configured, source);
  }

  if (Platform.isAndroid) return _extractAndroidBinary();
  if (Platform.isIOS) {
    throw const EngineStartupFailure(EngineFailureKind.unsupportedPlatform,
        'iOS cannot start a Stockfish process; the WebKit engine is used');
  }

  final names = Platform.isWindows
      ? const ['stockfish.exe', 'stockfish.com']
      : const ['stockfish'];
  for (final directory in _pathDirectories(env)) {
    for (final name in names) {
      final candidate =
          '$directory${Platform.pathSeparator}$name';
      if (_isExecutableFile(candidate)) {
        return StockfishRuntime(candidate, 'path');
      }
    }
  }
  for (final candidate in stockfishWellKnownLocations(env)) {
    if (_isExecutableFile(candidate)) {
      return StockfishRuntime(candidate, 'well-known');
    }
  }
  throw EngineStartupFailure(
    EngineFailureKind.runtimeMissing,
    stockfishInstallHint(),
    cause: const FileSystemException(
        'No Stockfish executable on PATH or in the usual install locations'),
  );
}

/// Extracts a bundled Android binary, when the build has one.
Future<StockfishRuntime> _extractAndroidBinary() async {
  const asset = 'assets/bin/stockfish-android';
  final ByteData bytes;
  try {
    bytes = await rootBundle.load(asset);
  } catch (error, stack) {
    throw EngineStartupFailure(
      EngineFailureKind.runtimeMissing,
      stockfishInstallHint(),
      cause: error,
      causeStack: stack,
    );
  }
  final Directory base;
  try {
    base = await getApplicationSupportDirectory();
  } catch (error, stack) {
    throw EngineStartupFailure(EngineFailureKind.runtimeMissing,
        'no application storage to extract Stockfish into',
        cause: error, causeStack: stack);
  }
  final binary = File('${base.path}/engines/stockfish');
  final data = bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  if (!binary.existsSync() || binary.lengthSync() != data.length) {
    await binary.parent.create(recursive: true);
    final part = File('${binary.path}.part');
    await part.writeAsBytes(data, flush: true);
    await part.rename(binary.path);
  }
  final chmod = await Process.run('chmod', ['700', binary.path]);
  if (chmod.exitCode != 0) {
    throw EngineStartupFailure(EngineFailureKind.permissionDenied,
        'could not mark the extracted Stockfish executable as runnable',
        cause: ProcessException('chmod', ['700', binary.path],
            '${chmod.stderr}', chmod.exitCode));
  }
  return StockfishRuntime(binary.path, 'android-asset');
}

/// The version inside a Stockfish `id name`: `Stockfish 16` → `16`,
/// `Stockfish 16.1` → `16.1`, `Stockfish dev-20231105-1a2b3c` →
/// `dev-20231105-1a2b3c`. Null when the name says nothing more.
String? stockfishVersionFromIdName(String idName) {
  final trimmed = idName.trim();
  final match =
      RegExp(r'^stockfish(?:\.js)?\s+(.+)$', caseSensitive: false).firstMatch(trimmed);
  if (match == null) return null;
  final rest = match.group(1)!.trim();
  // Strip trailing architecture/build tags some packagers append.
  final cleaned = rest
      .replaceFirst(RegExp(r'\s+(?:by\s.*|\(.*\)|64(?:-bit)?|x86[-_]64\S*)$',
          caseSensitive: false), '')
      .trim();
  return cleaned.isEmpty ? null : cleaned;
}

/// Native Stockfish (desktop/Android) — or, on iOS, the WebKit engine.
class StockfishEngine
    implements
        ChessEngine,
        SearchTelemetry,
        UciOptionAware,
        SearchDrainableEngine,
        EngineRuntimeReport,
        DownloadAwareEngine,
        RuntimeDigestSource {
  /// [sfVersion]/[variantId] are accepted for API parity with the web engine.
  /// [executablePath] and [resolver] pin the runtime (tests, and an explicit
  /// configuration); without them the executable is searched for.
  StockfishEngine({
    dynamic sfVersion,
    String? variantId,
    String? executablePath,
    StockfishRuntimeResolver? resolver,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.readinessTimeout = const Duration(seconds: 30),
  })  : _delegate = Platform.isIOS && executablePath == null && resolver == null
            ? StockfishDownloadableEngine()
            : null,
        _resolver = resolver ??
            (() => resolveStockfishRuntime(explicitPath: executablePath));

  /// On iOS, all work is forwarded to the WebKit-backed engine.
  final StockfishDownloadableEngine? _delegate;
  final StockfishRuntimeResolver _resolver;
  final Duration handshakeTimeout;
  final Duration readinessTimeout;

  final _stateNotifier = ValueNotifier<EngineState>(EngineState.idle);
  late final EngineInitCoordinator _init = EngineInitCoordinator(_stateNotifier);

  /// The running UCI connection. Replaced on every initialization attempt, so
  /// a retry after a failure starts from a fresh process.
  GenericUciEngine? _uci;
  VoidCallback? _uciListener;
  StockfishRuntime? _runtime;

  /// Where the executable came from, once it has been found.
  StockfishRuntime? get runtime => _runtime;

  static bool get isAvailable {
    if (kIsWeb) return false;
    // Desktop/Android: native binary. iOS: stockfish.js inside WebKit.
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows ||
        Platform.isAndroid || Platform.isIOS;
  }

  @override
  String get name => 'Stockfish';

  /// The detected version once the engine has spoken, otherwise the request.
  @override
  String get version =>
      _delegate?.version ?? detectedVersion ?? kStockfishRequestedVersion;

  @override
  String get license => 'GPL-3.0 (separate process)';
  @override
  int get estimatedElo => _delegate?.estimatedElo ?? 3600;
  @override
  EngineState get state => _delegate?.state ?? _stateNotifier.value;
  @override
  ValueNotifier<EngineState> get stateNotifier =>
      _delegate?.stateNotifier ?? _stateNotifier;

  // Stockfish searches in its own process (or, on iOS, its own JS worker) and
  // honours `stop`, so background analysis is safe.
  @override
  bool get canPonder => _delegate?.canPonder ?? true;

  // ------------------------------------------------------------ diagnostics

  @override
  EngineInitializationException? get initializationError =>
      _delegate?.initializationError ?? _init.lastFailure;

  @override
  String get effectiveBackend =>
      _delegate?.effectiveBackend ?? 'native-process';

  @override
  String? get fallbackReason => _delegate?.fallbackReason;

  @override
  String? get requestedVersion =>
      _delegate?.requestedVersion ?? kStockfishRequestedVersion;

  @override
  String? get detectedVersion {
    final delegate = _delegate;
    if (delegate != null) return delegate.detectedVersion;
    final uci = _uci;
    if (uci == null || uci.engineIdentifier.isEmpty) return null;
    return stockfishVersionFromIdName(uci.engineIdentifier) ??
        (uci.version.isEmpty ? null : uci.version);
  }

  /// The engine's own `id name`, once it has started.
  String? get detectedName {
    final uci = _uci;
    return uci == null || uci.engineIdentifier.isEmpty
        ? null
        : uci.engineIdentifier;
  }

  @override
  Future<EngineDownloadRequirement?> pendingDownload() async {
    final delegate = _delegate;
    return delegate == null ? null : await delegate.pendingDownload();
  }

  /// Which executable [initialize] would start now, as a digest (see
  /// [stockfishRuntimeDigest]). Null on iOS, where the WebKit engine inside
  /// the app is used, and when no executable is found.
  @override
  Future<String?> runtimeDigest() async {
    if (_delegate != null) return null;
    try {
      final runtime = await _resolver();
      return await stockfishRuntimeDigest(runtime.path);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- startup

  @override
  Future<void> initialize() {
    final delegate = _delegate;
    if (delegate != null) return delegate.initialize();
    return _init.run(
      engine: name,
      version: kStockfishRequestedVersion,
      requestedVersion: kStockfishRequestedVersion,
      backend: 'native-process',
      body: _start,
      cleanup: _releaseConnection,
    );
  }

  Future<void> _start(EngineInitScope scope) async {
    // A retry after a crash or a failed start begins from a fresh process.
    _releaseConnection();
    scope.stage = EngineInitStage.resolveRuntime;
    final runtime = await _resolver();
    _runtime = runtime;
    scope.runtimePath = runtime.path;
    scope.checkCancelled();

    scope.stage = EngineInitStage.launchProcess;
    final uci = GenericUciEngine(
      EngineProfile(id: 'builtin-stockfish', name: 'Stockfish', path: runtime.path),
      handshakeTimeout: handshakeTimeout,
      readinessTimeout: readinessTimeout,
    );
    _uci = uci;
    try {
      await uci.initialize();
    } catch (error) {
      // The connection records which step failed and how (exit code, stderr,
      // timeout); hand that on with the original exception as the cause.
      final recorded = uci.initializationError;
      if (recorded != null) {
        scope.stage = recorded.stage;
        scope.exitCode = recorded.exitCode;
        scope.stderrTail = recorded.stderrTail;
        scope.detectedVersion = detectedVersion;
        throw recorded;
      }
      rethrow;
    }
    scope.checkCancelled();
    scope.stage = EngineInitStage.verifyReady;
    scope.detectedVersion = detectedVersion;
    if (detectedName == null) {
      throw const EngineStartupFailure(EngineFailureKind.protocolError,
          'the executable completed the UCI handshake without an "id name"');
    }
    if (!detectedName!.toLowerCase().contains('stockfish')) {
      // Not fatal — a renamed fork is still a UCI engine — but never pretend
      // it is Stockfish: the label and identity use what it reported.
      debugPrint('[Stockfish] ${runtime.path} reports "$detectedName"');
    }
    // Mirror the connection's later state changes (thinking, ready, a crash
    // turning it to error) now that it is genuinely ready.
    void listener() {
      if (_init.disposed || !identical(_uci, uci)) return;
      final next = uci.state;
      if (next == EngineState.disposed) {
        _stateNotifier.value = EngineState.error;
      } else if (next != EngineState.initializing) {
        _stateNotifier.value = next;
      }
    }

    _uciListener = listener;
    uci.stateNotifier.addListener(listener);
  }

  void _releaseConnection() {
    final uci = _uci;
    _uci = null;
    final listener = _uciListener;
    _uciListener = null;
    if (uci == null) return;
    if (listener != null) uci.stateNotifier.removeListener(listener);
    uci.dispose();
  }

  // ----------------------------------------------------------------- search

  GenericUciEngine _ready() {
    final uci = _uci;
    if (_init.disposed) throw StateError('Engine disposed');
    if (uci == null) throw StateError('Not initialized');
    return uci;
  }

  @override
  Future<String> bestMove(
    String positionCommand, {
    int? depth,
    Duration? moveTime,
    int? skillLevel,
  }) {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.bestMove(positionCommand,
          depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    }
    try {
      return _ready().bestMove(positionCommand,
          depth: depth, moveTime: moveTime, skillLevel: skillLevel);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  @override
  Stream<EvalInfo> analyze(String positionCommand,
      {int? depth, bool infinite = false}) {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.analyze(positionCommand, depth: depth, infinite: infinite);
    }
    final uci = _uci;
    if (uci == null || _init.disposed) return const Stream.empty();
    return uci.analyze(positionCommand, depth: depth, infinite: infinite);
  }

  @override
  void stop() {
    final delegate = _delegate;
    if (delegate != null) return delegate.stop();
    _uci?.stop();
  }

  @override
  void setOption(String name, String value) {
    final delegate = _delegate;
    if (delegate != null) return delegate.setOption(name, value);
    _uci?.setOption(name, value);
  }

  // ------------------------------------------------------------ capabilities

  @override
  SearchStatistics get lastSearchStatistics =>
      _uci?.lastSearchStatistics ?? SearchStatistics.none;

  @override
  void resetSearchStatistics() => _uci?.resetSearchStatistics();

  @override
  List<String> get advertisedOptionNames =>
      _uci?.advertisedOptionNames ?? const <String>[];

  @override
  bool advertisesOption(String name) => _uci?.advertisesOption(name) ?? false;

  @override
  void applyOption(String name, String value) => _uci?.applyOption(name, value);

  @override
  Future<void> synchronizeOptions() async {
    final uci = _uci;
    if (uci == null) {
      throw StateError('Stockfish is not running; options cannot be synchronized');
    }
    await uci.synchronizeOptions();
  }

  @override
  Future<void> drainSearch({Duration timeout = const Duration(seconds: 5)}) async {
    final delegate = _delegate;
    if (delegate != null) return;
    await _uci?.drainSearch(timeout: timeout);
  }

  // ---------------------------------------------------------------- dispose

  @override
  void dispose() {
    final delegate = _delegate;
    if (delegate != null) return delegate.dispose();
    if (_init.disposed && _stateNotifier.value == EngineState.disposed) return;
    _init.markDisposed();
    _releaseConnection();
    _stateNotifier.value = EngineState.disposed;
  }
}
