/// The engine initialization contract.
///
/// Every [ChessEngine.initialize] follows the same rules (see
/// `docs/audit/2026-11-02-engine-initialization-dev4.md`):
///
///  * it completes normally **only** when the engine is genuinely ready;
///  * a failure propagates as an exception that keeps the original cause and
///    stack trace — no initializer may catch its own failure, set
///    [EngineState.error] and return normally;
///  * resources allocated by a failed attempt are released before the
///    exception leaves;
///  * concurrent calls join the attempt already running instead of starting a
///    second process, download or worker;
///  * a [ChessEngine.dispose] during initialization wins: late asynchronous work
///    can never put a disposed engine back into `ready`;
///  * cancellation (disposal) is reported as [EngineFailureKind.cancelled], not
///    as an engine fault.
///
/// [EngineInitCoordinator] implements the bookkeeping once so each adapter only
/// supplies its actual startup steps. [EngineInitializationException] is the
/// structured diagnostic every consumer — gameplay, Match, the Engine Lab, the
/// Stability Probe and Preflight — can display, copy and export.
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, ValueNotifier, defaultTargetPlatform, kIsWeb;

import 'chess_engine.dart';

/// Stable, machine-readable failure categories.
///
/// The ids ([name]) are persisted in benchmark reports; do not rename them.
enum EngineFailureKind {
  unsupportedPlatform,
  runtimeMissing,
  binaryMissing,
  permissionDenied,
  processLaunchFailed,
  dependencyMissing,
  downloadRequired,
  downloadFailed,
  handshakeFailed,
  handshakeTimeout,
  readinessFailed,
  readinessTimeout,
  processExited,
  backendInitializationFailed,
  protocolError,
  cleanupFailed,
  cancelled,
  unknown;

  String get id => name;

  static EngineFailureKind? fromId(String? id) {
    if (id == null) return null;
    for (final kind in values) {
      if (kind.name == id) return kind;
    }
    return null;
  }

  /// One sentence a player can act on. Technical detail stays in the
  /// diagnostic; this is what a summary line says.
  String get explanation => switch (this) {
        EngineFailureKind.unsupportedPlatform => 'this engine cannot run on this platform',
        EngineFailureKind.runtimeMissing => 'the engine runtime is not installed on this device',
        EngineFailureKind.binaryMissing => 'the engine executable was not found',
        EngineFailureKind.permissionDenied => 'the engine executable is not allowed to run',
        EngineFailureKind.processLaunchFailed => 'the engine process could not be started',
        EngineFailureKind.dependencyMissing =>
          'a library the engine needs is missing or failed to load',
        EngineFailureKind.downloadRequired =>
          'the engine must be downloaded before it can be used',
        EngineFailureKind.downloadFailed => 'downloading the engine failed',
        EngineFailureKind.handshakeFailed => 'the engine did not complete the UCI handshake',
        EngineFailureKind.handshakeTimeout => 'the engine did not answer "uci" in time',
        EngineFailureKind.readinessFailed => 'the engine did not confirm it was ready',
        EngineFailureKind.readinessTimeout => 'the engine did not answer "isready" in time',
        EngineFailureKind.processExited => 'the engine process exited during startup',
        EngineFailureKind.backendInitializationFailed => 'the engine backend failed to load',
        EngineFailureKind.protocolError => 'the engine sent an invalid protocol response',
        EngineFailureKind.cleanupFailed => 'the engine could not be shut down cleanly',
        EngineFailureKind.cancelled => 'startup was cancelled before it finished',
        EngineFailureKind.unknown => 'the engine failed to start',
      };
}

/// Stable initialization stage ids. Strings rather than an enum because the
/// dev3 FFI stages (`load-library`, `check-abi`, `resolve-symbols`,
/// `native-create`) are already persisted and asserted on.
abstract final class EngineInitStage {
  static const idle = 'idle';
  static const resolveRuntime = 'resolve-runtime';
  static const download = 'download';
  static const loadLibrary = 'load-library';
  static const loadBackend = 'load-backend';
  static const launchProcess = 'launch-process';
  static const handshake = 'wait-uciok';
  static const configure = 'configure';
  static const readiness = 'wait-readyok';
  static const warmUp = 'warm-up';
  static const verifyReady = 'verify-ready';
  static const initialize = 'initialize';
}

/// Thrown by an initializer step to name the failure category explicitly.
///
/// [cause] is the original error when there is one; the coordinator unwraps it
/// so `EngineInitializationException.cause` is the real exception, not this
/// wrapper.
class EngineStartupFailure implements Exception {
  final EngineFailureKind kind;
  final String message;
  final Object? cause;
  final StackTrace? causeStack;

  const EngineStartupFailure(this.kind, this.message,
      {this.cause, this.causeStack});

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

/// The platform this build runs on, as a report word.
String enginePlatformLabel() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.linux => 'linux',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.windows => 'windows',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

/// Category for an error that did not name one, from where it happened and
/// what it was. Type checks use the runtime type name because this file must
/// also compile for the web, where `dart:io` does not exist.
EngineFailureKind classifyEngineFailure(String stage, Object cause) {
  if (cause is EngineStartupFailure) return cause.kind;
  if (cause is EngineInitializationException) return cause.kind;
  if (cause is EngineProcessDiedException) return EngineFailureKind.processExited;
  if (cause is UnsupportedError) {
    return stage == EngineInitStage.loadBackend ||
            stage == EngineInitStage.loadLibrary
        ? EngineFailureKind.backendInitializationFailed
        : EngineFailureKind.unsupportedPlatform;
  }
  final type = cause.runtimeType.toString();
  final text = cause.toString();
  final timeout = cause is TimeoutException;
  switch (stage) {
    case EngineInitStage.resolveRuntime:
      return type.contains('FileSystemException') ||
              type.contains('PathNotFoundException')
          ? EngineFailureKind.binaryMissing
          : EngineFailureKind.runtimeMissing;
    case EngineInitStage.download:
      return EngineFailureKind.downloadFailed;
    case EngineInitStage.loadLibrary:
      return EngineFailureKind.dependencyMissing;
    case EngineInitStage.launchProcess:
      if (type.contains('FileSystemException') ||
          type.contains('PathNotFoundException')) {
        return EngineFailureKind.binaryMissing;
      }
      if (_looksLikePermission(text)) return EngineFailureKind.permissionDenied;
      return EngineFailureKind.processLaunchFailed;
    case EngineInitStage.handshake:
      return timeout
          ? EngineFailureKind.handshakeTimeout
          : EngineFailureKind.handshakeFailed;
    case EngineInitStage.readiness:
    case EngineInitStage.configure:
      return timeout
          ? EngineFailureKind.readinessTimeout
          : EngineFailureKind.readinessFailed;
    case EngineInitStage.loadBackend:
    case EngineInitStage.warmUp:
    case 'check-abi':
    case 'resolve-symbols':
    case 'native-create':
      return EngineFailureKind.backendInitializationFailed;
    case EngineInitStage.verifyReady:
      return EngineFailureKind.readinessFailed;
  }
  if (timeout) return EngineFailureKind.readinessTimeout;
  return EngineFailureKind.unknown;
}

bool _looksLikePermission(String text) {
  final lower = text.toLowerCase();
  return lower.contains('permission denied') ||
      lower.contains('errno = 13') ||
      lower.contains('error code: 5') ||
      lower.contains('access is denied');
}

final RegExp _personalPath = RegExp(
  r'(?:/home/|/Users/|/data/user/\d+/|/var/mobile/Containers/Data/Application/|[A-Za-z]:\\Users\\)[^/\\\s"]+',
);

/// Replaces user-specific path prefixes (home directories, app containers)
/// with `~`, so an exported report does not carry a username.
String redactPersonalPaths(String text) => text.replaceAll(_personalPath, '~');

/// The last path component, for a public report.
String redactPath(String path) {
  final cut = path.lastIndexOf(RegExp(r'[/\\]'));
  return cut < 0 ? path : '…/${path.substring(cut + 1)}';
}

/// A startup failure that retains the original cause instead of reducing it to
/// "Bad state". UIs can display/copy [toString] (local, detailed) or
/// [toJson]/[summary] (redacted for reports); callers can inspect the fields.
class EngineInitializationException implements Exception {
  /// User-facing engine name.
  final String engine;

  /// The version the app advertised for the engine (kept for compatibility:
  /// dev3 reports call it `version`). See [requestedVersion]/[detectedVersion].
  final String version;
  final String stage;
  final String platform;

  /// The original error. Never a wrapper when the original is known.
  final Object cause;
  final StackTrace? causeStack;

  /// FFI library path (dev3 field name).
  final String? libraryPath;
  final String? symbol;
  final int? nativeCode;
  final int? elapsedMicros;

  /// Stable engine id (`builtin:Stockfish`, `custom:<profile>`), when known.
  final String? engineId;
  final String? requestedVersion;

  /// What the engine/runtime reported about itself before failing.
  final String? detectedVersion;

  /// `native-process`, `ffi`, `wasm`, `javascript-webkit`, `dart`, …
  final String? backend;
  final EngineFailureKind kind;

  /// Exit code of a process that died during startup.
  final int? exitCode;

  /// The last stderr lines of that process.
  final List<String> stderrTail;

  /// Executable / runtime artifact path for a process or download backend.
  final String? runtimePath;

  /// A short explanation added by the adapter (an [EngineStartupFailure]
  /// message), separate from the original cause.
  final String? detail;

  /// Whether an earlier backend failed and this failure is the last one tried.
  final String? fallbackReason;

  EngineInitializationException({
    required this.engine,
    required this.version,
    required this.stage,
    required this.platform,
    required this.cause,
    this.causeStack,
    this.libraryPath,
    this.symbol,
    this.nativeCode,
    this.elapsedMicros,
    this.engineId,
    this.requestedVersion,
    this.detectedVersion,
    this.backend,
    EngineFailureKind? kind,
    this.exitCode,
    this.stderrTail = const [],
    this.runtimePath,
    this.detail,
    this.fallbackReason,
  }) : kind = kind ?? classifyEngineFailure(stage, cause);

  /// Returns [error] unchanged when it is already structured; otherwise wraps
  /// it, classifying it by [stage].
  static EngineInitializationException wrap(
    Object error,
    StackTrace? stack, {
    required String engine,
    required String version,
    String stage = EngineInitStage.initialize,
    String? platform,
    String? engineId,
    String? backend,
  }) {
    if (error is EngineInitializationException) return error;
    final startup = error is EngineStartupFailure ? error : null;
    final cause = startup?.cause ?? error;
    return EngineInitializationException(
      engine: engine,
      version: version,
      stage: stage,
      platform: platform ?? enginePlatformLabel(),
      cause: cause,
      causeStack: startup?.causeStack ?? stack,
      engineId: engineId,
      backend: backend,
      kind: startup?.kind,
      detail: startup?.message,
      exitCode: cause is EngineProcessDiedException ? cause.exitCode : null,
      stderrTail:
          cause is EngineProcessDiedException ? cause.stderrTail : const [],
    );
  }

  /// Same failure with the engine id attached (the id is known to the Lab,
  /// not to the adapter).
  EngineInitializationException withEngineId(String id) =>
      engineId == id ? this : EngineInitializationException(
            engine: engine,
            version: version,
            stage: stage,
            platform: platform,
            cause: cause,
            causeStack: causeStack,
            libraryPath: libraryPath,
            symbol: symbol,
            nativeCode: nativeCode,
            elapsedMicros: elapsedMicros,
            engineId: id,
            requestedVersion: requestedVersion,
            detectedVersion: detectedVersion,
            backend: backend,
            kind: kind,
            exitCode: exitCode,
            stderrTail: stderrTail,
            runtimePath: runtimePath,
            detail: detail,
            fallbackReason: fallbackReason,
          );

  String get _label {
    final v = detectedVersion ?? requestedVersion ?? version;
    return v.isEmpty ? engine : '$engine $v';
  }

  /// One redacted line for a report or a status row.
  String get summary {
    final what = detail == null || detail!.isEmpty
        ? kind.explanation
        : '${kind.explanation} — $detail';
    final code = exitCode == null ? '' : ' (exit code $exitCode)';
    final causeText = cause is EngineStartupFailure
        ? ''
        : ': ${_firstLine(redactPersonalPaths(cause.toString()))}';
    return '$_label could not start: $what$code '
        '[${kind.id} at $stage]$causeText';
  }

  /// Structured diagnostic. [redact] (the default) removes personal paths and
  /// shortens executable/library paths to their file name, which is what any
  /// stored or exported report uses. `redact: false` is for the local
  /// "copy full details" action only.
  Map<String, Object?> toJson({bool redact = true}) {
    String text(String value) => redact ? redactPersonalPaths(value) : value;
    String path(String value) => redact ? redactPath(value) : value;
    return {
      'engine': engine,
      'version': version,
      if (engineId != null) 'engineId': engineId,
      if (requestedVersion != null) 'requestedVersion': requestedVersion,
      if (detectedVersion != null) 'detectedVersion': detectedVersion,
      'platform': platform,
      if (backend != null) 'backend': backend,
      'stage': stage,
      'kind': kind.id,
      'causeType': cause.runtimeType.toString(),
      'cause': text(cause.toString()),
      if (detail != null) 'detail': text(detail!),
      if (exitCode != null) 'exitCode': exitCode,
      if (stderrTail.isNotEmpty)
        'stderrTail': [for (final line in stderrTail) text(line)],
      if (runtimePath != null) 'runtimePath': path(runtimePath!),
      if (libraryPath != null) 'libraryPath': path(libraryPath!),
      if (symbol != null) 'symbol': symbol,
      if (nativeCode != null) 'nativeCode': nativeCode,
      if (elapsedMicros != null) 'elapsedMicros': elapsedMicros,
      if (fallbackReason != null) 'fallbackReason': text(fallbackReason!),
      if (causeStack != null) 'causeStack': text(_trimStack(causeStack!)),
      'redacted': redact,
    };
  }

  /// Multi-line text for the "copy diagnostics" action.
  String toDiagnosticText({bool redact = true}) {
    final json = toJson(redact: redact);
    final out = StringBuffer(redact ? summary : toString())..writeln();
    for (final entry in json.entries) {
      if (entry.key == 'causeStack') continue;
      final value = entry.value;
      if (value is List) {
        out.writeln('${entry.key}:');
        for (final line in value) {
          out.writeln('  $line');
        }
      } else {
        out.writeln('${entry.key}: $value');
      }
    }
    final stack = json['causeStack'];
    if (stack != null) {
      out
        ..writeln('causeStack:')
        ..writeln(stack);
    }
    return out.toString();
  }

  @override
  String toString() {
    final details = [
      'engine=$engine $version',
      'platform=$platform',
      'stage=$stage',
      'kind=${kind.id}',
      if (backend != null) 'backend=$backend',
      if (detectedVersion != null) 'detectedVersion=$detectedVersion',
      if (libraryPath != null) 'library=$libraryPath',
      if (runtimePath != null) 'runtime=$runtimePath',
      if (symbol != null) 'symbol=$symbol',
      if (nativeCode != null) 'nativeCode=$nativeCode',
      if (exitCode != null) 'exitCode=$exitCode',
      if (elapsedMicros != null) 'elapsedMicros=$elapsedMicros',
    ];
    var message = '${details.join('; ')}\n';
    if (detail != null && cause is! EngineStartupFailure) message += '$detail: ';
    message += '$cause';
    if (stderrTail.isNotEmpty) {
      message += '\nstderr: ${stderrTail.join('\n        ')}';
    }
    if (stage == EngineInitStage.loadLibrary && nativeCode == 126) {
      message += '\nThe library or one of its dependencies is missing. '
          'Use a complete release archive; do not substitute another engine.';
    }
    return message;
  }
}

String _firstLine(String text) {
  final cut = text.indexOf('\n');
  final line = cut < 0 ? text : text.substring(0, cut);
  return line.length <= 240 ? line : '${line.substring(0, 240)}…';
}

String _trimStack(StackTrace stack) {
  final lines = stack.toString().split('\n');
  return lines.take(24).join('\n');
}

/// What an engine can say about how it actually started.
///
/// Optional: the Lab, Preflight and Stability Probe use it when present and
/// say "unknown" otherwise. An engine that falls back from one backend to
/// another reports the backend that is actually running here, never the one
/// that failed.
abstract interface class EngineRuntimeReport {
  /// The last startup failure of this instance, or null.
  EngineInitializationException? get initializationError;

  /// The backend that is actually running (after any fallback).
  String get effectiveBackend;

  /// Why a fallback happened, or null when the first choice is running.
  String? get fallbackReason;

  /// The version the app intended to run (e.g. `16` for the built-in
  /// Stockfish). Null when the app has no expectation (custom engines).
  String? get requestedVersion;

  /// The version the running engine reported about itself, or null when it
  /// has not started or does not report one.
  String? get detectedVersion;
}

/// An artifact an engine needs before it can start.
class EngineDownloadRequirement {
  /// What will be downloaded, in words ("Lynx 1.11.0 for linux-x64").
  final String description;

  /// Where it comes from.
  final Uri source;

  /// Size, only when it is actually known (a declared release size or a
  /// Content-Length). Never estimated.
  final int? bytes;

  /// License of the downloaded artifact, when it differs from the app's.
  final String? license;

  const EngineDownloadRequirement({
    required this.description,
    required this.source,
    this.bytes,
    this.license,
  });

  Map<String, Object?> toJson() => {
        'description': description,
        'source': source.toString(),
        if (bytes != null) 'bytes': bytes,
        if (license != null) 'license': license,
      };
}

/// An engine that starts an executable found on this device at run time
/// rather than one built into the app (the native Stockfish adapter). Its
/// build-based identity cannot tell two such executables apart, so a Preflight
/// result is also bound to [runtimeDigest].
abstract interface class RuntimeDigestSource {
  /// A digest of the executable the engine would start now — SHA-256 over its
  /// location and its contents, so the path itself is not revealed — or null
  /// when none is found. Must not start the engine.
  Future<String?> runtimeDigest();
}

/// An engine that may download something during [ChessEngine.initialize].
///
/// [pendingDownload] must not download anything itself: it is how Preflight
/// asks first instead of starting an unexpected transfer.
abstract interface class DownloadAwareEngine {
  /// Null when nothing has to be downloaded before the engine can start.
  Future<EngineDownloadRequirement?> pendingDownload();
}

/// Mutable context an initializer reports into while it runs.
class EngineInitScope {
  EngineInitScope._(this._coordinator, this._generation);

  final EngineInitCoordinator _coordinator;
  final int _generation;

  /// The step now running. Set before each step so a failure names it.
  String stage = EngineInitStage.resolveRuntime;
  String? runtimePath;
  String? detectedVersion;
  String? backend;
  String? fallbackReason;
  int? exitCode;
  int? nativeCode;
  List<String> stderrTail = const [];

  /// Whether the engine was disposed (or a newer attempt started) since this
  /// attempt began. Long-running steps check this between awaits.
  bool get cancelled =>
      _coordinator._disposed || _generation != _coordinator._generation;

  /// Throws [EngineFailureKind.cancelled] when [cancelled].
  void checkCancelled() {
    if (cancelled) {
      throw const EngineStartupFailure(EngineFailureKind.cancelled,
          'the engine was disposed during initialization');
    }
  }
}

/// Shared implementation of the initialization contract for one engine
/// instance. Adapters keep their own state notifier and pass it in.
class EngineInitCoordinator {
  EngineInitCoordinator(this._state);

  final ValueNotifier<EngineState> _state;
  Future<void>? _pending;
  bool _disposed = false;
  // Set only by a successful attempt and cleared when a new one begins. The
  // shared state alone is not proof of a start: a `stop()` after a failed
  // start could otherwise turn `error` into `ready` and skip initialization.
  bool _succeeded = false;
  int _generation = 0;
  EngineInitializationException? _lastFailure;
  String _effectiveBackend = '';
  String? _fallbackReason;
  String? _detectedVersion;

  bool get disposed => _disposed;
  bool get isInitializing => _pending != null;
  EngineInitializationException? get lastFailure => _lastFailure;
  String get effectiveBackend => _effectiveBackend;
  String? get fallbackReason => _fallbackReason;
  String? get detectedVersion => _detectedVersion;

  /// Runs [body] under the contract. Repeated calls while an attempt is in
  /// flight return that attempt; a call on a ready engine returns at once; a
  /// call after a failure starts a fresh attempt (unless [retryable] is
  /// false, in which case the recorded failure is returned again).
  Future<void> run({
    required String engine,
    required String version,
    required String backend,
    String? requestedVersion,
    required Future<void> Function(EngineInitScope scope) body,
    FutureOr<void> Function()? cleanup,
    bool retryable = true,
  }) {
    if (_disposed) {
      return Future.error(EngineInitializationException(
        engine: engine,
        version: version,
        stage: EngineInitStage.verifyReady,
        platform: enginePlatformLabel(),
        cause: StateError('$engine is disposed'),
        kind: EngineFailureKind.cancelled,
        backend: backend,
        requestedVersion: requestedVersion,
      ));
    }
    final current = _state.value;
    if (_succeeded &&
        (current == EngineState.ready || current == EngineState.thinking)) {
      return Future<void>.value();
    }
    final pending = _pending;
    if (pending != null) return pending;
    final failure = _lastFailure;
    if (!retryable && failure != null) return Future.error(failure);
    final attempt = _attempt(
      engine: engine,
      version: version,
      backend: backend,
      requestedVersion: requestedVersion,
      body: body,
      cleanup: cleanup,
    );
    _pending = attempt;
    attempt.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (identical(_pending, attempt)) _pending = null;
    });
    return attempt;
  }

  Future<void> _attempt({
    required String engine,
    required String version,
    required String backend,
    String? requestedVersion,
    required Future<void> Function(EngineInitScope scope) body,
    FutureOr<void> Function()? cleanup,
  }) async {
    final generation = ++_generation;
    final scope = EngineInitScope._(this, generation)..backend = backend;
    final watch = Stopwatch()..start();
    _lastFailure = null;
    _succeeded = false;
    _setState(EngineState.initializing);
    try {
      await body(scope);
      scope.stage = EngineInitStage.verifyReady;
      scope.checkCancelled();
      _effectiveBackend = scope.backend ?? backend;
      _fallbackReason = scope.fallbackReason;
      _detectedVersion = scope.detectedVersion;
      _succeeded = true;
      _setState(EngineState.ready);
    } catch (error, stack) {
      String? cleanupProblem;
      if (cleanup != null) {
        try {
          await cleanup();
        } catch (cleanupError) {
          cleanupProblem = 'cleanup after the failed start also failed: '
              '$cleanupError';
        }
      }
      final startup = error is EngineStartupFailure ? error : null;
      final structured = error is EngineInitializationException ? error : null;
      final cause = structured?.cause ?? startup?.cause ?? error;
      final died = cause is EngineProcessDiedException ? cause : null;
      final cancelled = scope.cancelled;
      final details = <String>[
        if (startup != null) startup.message,
        if (structured?.detail != null) structured!.detail!,
        if (cleanupProblem != null) cleanupProblem,
      ];
      final failure = EngineInitializationException(
        engine: engine,
        version: version,
        stage: structured?.stage ?? scope.stage,
        platform: enginePlatformLabel(),
        cause: cause,
        causeStack: structured?.causeStack ?? startup?.causeStack ?? stack,
        libraryPath: structured?.libraryPath,
        symbol: structured?.symbol,
        nativeCode: structured?.nativeCode ?? scope.nativeCode,
        elapsedMicros: watch.elapsedMicroseconds,
        requestedVersion: requestedVersion,
        detectedVersion: scope.detectedVersion ?? structured?.detectedVersion,
        backend: scope.backend ?? backend,
        kind: cancelled
            ? EngineFailureKind.cancelled
            : (structured?.kind ??
                startup?.kind ??
                classifyEngineFailure(scope.stage, cause)),
        exitCode: died?.exitCode ?? scope.exitCode ?? structured?.exitCode,
        stderrTail: died != null && died.stderrTail.isNotEmpty
            ? died.stderrTail
            : (scope.stderrTail.isNotEmpty
                ? scope.stderrTail
                : (structured?.stderrTail ?? const [])),
        runtimePath: scope.runtimePath ?? structured?.runtimePath,
        detail: details.isEmpty ? null : details.join('; '),
        fallbackReason: scope.fallbackReason ?? structured?.fallbackReason,
      );
      if (generation == _generation) {
        _lastFailure = failure;
        if (!_disposed) _setState(EngineState.error);
      }
      throw failure;
    }
  }

  /// Records that the engine is gone. An attempt still running will fail with
  /// [EngineFailureKind.cancelled] at its next check and can no longer set
  /// `ready`.
  void markDisposed() {
    _disposed = true;
    _generation++;
  }

  void _setState(EngineState value) {
    if (_disposed) return;
    _state.value = value;
  }
}

/// Normal return is only successful when the engine is actually ready.
///
/// Kept as a defensive check for engines outside this repository; every
/// adapter here throws on failure, so reaching the throw means an adapter
/// broke the contract — and the error says so, with the adapter's own
/// recorded failure when it has one.
void requireEngineReady(ChessEngine engine, {required String platform}) {
  if (engine.state != EngineState.ready) {
    final recorded =
        engine is EngineRuntimeReport ? (engine as EngineRuntimeReport).initializationError : null;
    if (recorded != null) throw recorded;
    throw EngineInitializationException(
      engine: engine.name,
      version: engine.version,
      stage: EngineInitStage.verifyReady,
      platform: platform,
      kind: EngineFailureKind.readinessFailed,
      detail: 'initialize() returned normally but the engine is not ready '
          '(contract violation)',
      cause: StateError('initialize returned with state ${engine.state.name}'),
    );
  }
}

/// The structured form of a startup failure observed by a consumer.
///
/// Prefers, in order: the exception itself when structured; the adapter's own
/// recorded failure for the same cause (custom UCI engines keep throwing their
/// original exception types and record the structured diagnostic alongside);
/// a wrap classified as [EngineInitStage.initialize].
EngineInitializationException engineFailureOf(
  ChessEngine engine,
  Object error,
  StackTrace? stack, {
  String? engineId,
}) {
  EngineInitializationException result;
  if (error is EngineInitializationException) {
    result = error;
  } else {
    final recorded = engine is EngineRuntimeReport
        ? (engine as EngineRuntimeReport).initializationError
        : null;
    if (recorded != null &&
        (identical(recorded.cause, error) || identical(recorded, error))) {
      result = recorded;
    } else {
      result = EngineInitializationException.wrap(
        error,
        stack,
        engine: engine.name,
        version: engine.version,
        backend: engine is EngineRuntimeReport
            ? (engine as EngineRuntimeReport).effectiveBackend
            : null,
      );
    }
  }
  return engineId == null ? result : result.withEngineId(engineId);
}

int? windowsLoaderCode(Object error) {
  final match = RegExp(r'error code:\s*(\d+)').firstMatch(error.toString());
  return match == null ? null : int.tryParse(match.group(1)!);
}
