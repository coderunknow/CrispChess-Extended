/// Engine Preflight: does each selected engine actually start, answer, search
/// and shut down here — before a benchmark spends an hour on it?
///
/// A benchmark that discovers a broken engine only when its first game starts
/// has already scheduled games against it; dev3 reported that as
/// "Stockfish 16: failed — Bad state: initialize returned with state error".
/// Preflight runs the same steps a benchmark needs, one engine at a time, and
/// reports each step's outcome with the structured startup diagnostic
/// (`EngineInitializationException.toJson`, redacted) when one fails.
///
/// Rules this file enforces:
///
///  * **No silent downloads.** An engine that would download something first
///    ([DownloadAwareEngine.pendingDownload]) is reported as `notInstalled`
///    unless the caller's consent callback agreed to that download.
///  * **No silent omission.** Every requested engine gets a result, including
///    the ones that cannot run on this platform (`unsupported`).
///  * **Results are bound** to what was checked: the engine identity
///    (fingerprint, version, platform, backend), the benchmark configuration
///    that changes how it starts or searches, and the app build. Any change
///    makes the result stale ([PreflightGate.isStale]); a stale or failed
///    result never admits an engine to a run.
library;

import 'dart:async';
import 'dart:convert' show JsonEncoder;

import 'package:chess/chess.dart' as chess;

import '../engines/chess_engine.dart';
import '../engines/engine_initialization.dart';
import '../engines/uci_capabilities.dart';
import 'benchmark_config.dart';
import 'engine_identity.dart';
import 'game_player.dart' show applyUciMove;

/// Outcome of one step, or of a whole engine.
enum PreflightStatus {
  passed,
  warning,
  failed,
  unsupported,
  notInstalled,
  timedOut,
  cancelled,

  /// Not reached because an earlier step decided the outcome.
  skipped;

  String get id => name;

  static PreflightStatus fromId(String? id) => PreflightStatus.values
      .firstWhere((s) => s.name == id, orElse: () => PreflightStatus.failed);

  /// Whether an engine with this overall status may take part in a run (a
  /// warning only after the user has reviewed it — see [PreflightGate]).
  bool get admits => this == passed || this == warning;
}

/// The checks, in the order they run.
enum PreflightStep {
  platform,
  runtime,
  initialization,
  readiness,
  identity,
  options,
  firstSearch,
  legalMove,
  cleanup;

  String get id => name;

  static PreflightStep? fromId(String? id) {
    for (final step in values) {
      if (step.name == id) return step;
    }
    return null;
  }
}

class PreflightStepResult {
  final PreflightStep step;
  final PreflightStatus status;

  /// A short redacted explanation (what was found, what failed).
  final String? detail;
  final int? millis;

  const PreflightStepResult(this.step, this.status, {this.detail, this.millis});

  Map<String, dynamic> toJson() => {
        'step': step.id,
        'status': status.id,
        if (detail != null) 'detail': detail,
        if (millis != null) 'millis': millis,
      };

  factory PreflightStepResult.fromJson(Map<String, dynamic> json) =>
      PreflightStepResult(
        PreflightStep.fromId(json['step'] as String?) ?? PreflightStep.platform,
        PreflightStatus.fromId(json['status'] as String?),
        detail: json['detail'] as String?,
        millis: json['millis'] is num ? (json['millis'] as num).toInt() : null,
      );
}

/// What a result is valid for. Two bindings with different keys mean the
/// result says nothing about the engine as it would run now.
class PreflightBinding {
  /// [EngineIdentity.identityKey] of the identity the run would record before
  /// starting the engine: engine id, binary/build fingerprint, configuration
  /// digest, platform and backend.
  final String identityKey;

  /// Digest of the benchmark settings that change how an engine starts or
  /// searches (requested options, time/depth/node budget).
  final String configDigest;
  final String appBuild;

  const PreflightBinding({
    required this.identityKey,
    required this.configDigest,
    required this.appBuild,
  });

  factory PreflightBinding.of(
    EngineIdentity identity,
    BenchmarkConfig config, {
    required String appBuild,
  }) =>
      PreflightBinding(
        identityKey: identity.identityKey,
        configDigest: preflightConfigDigest(config),
        appBuild: appBuild,
      );

  String get key => '$identityKey#$configDigest#$appBuild';

  /// Why [current] differs from this binding, or null when it does not.
  String? changeFrom(PreflightBinding current) {
    if (identityKey != current.identityKey) {
      return 'the engine identity changed (binary, version, platform, '
          'backend or configuration)';
    }
    if (configDigest != current.configDigest) {
      return 'the benchmark settings changed';
    }
    if (appBuild != current.appBuild) return 'the app was updated';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'identityKey': identityKey,
        'configDigest': configDigest,
        'appBuild': appBuild,
      };

  factory PreflightBinding.fromJson(Map<String, dynamic> json) =>
      PreflightBinding(
        identityKey: (json['identityKey'] as String?) ?? '',
        configDigest: (json['configDigest'] as String?) ?? '',
        appBuild: (json['appBuild'] as String?) ?? '',
      );
}

/// Digest of the configuration fields a preflight result depends on.
String preflightConfigDigest(BenchmarkConfig config) {
  final options = config.requestedOptions().entries
      .map((e) => '${e.key}=${e.value}')
      .toList()
    ..sort();
  return digestOf([
    'move=${config.timePerMove.inMilliseconds}',
    'depth=${config.searchDepth ?? ''}',
    'nodes=${config.nodeLimit ?? ''}',
    ...options,
  ]);
}

/// The full result for one engine.
class EnginePreflightResult {
  final String engineId;
  final String label;
  final PreflightStatus status;
  final List<PreflightStepResult> steps;

  /// Identity as checked: refined with what the engine reported (detected
  /// version, effective backend, fallback) when it started.
  final EngineIdentity? identity;
  final PreflightBinding? binding;

  /// Redacted structured startup diagnostic when initialization failed.
  final Map<String, dynamic>? diagnostic;

  /// What would have to be downloaded, when [status] is `notInstalled`
  /// because consent was not given.
  final EngineDownloadRequirement? pendingDownload;
  final DateTime checkedAt;

  const EnginePreflightResult({
    required this.engineId,
    required this.label,
    required this.status,
    required this.steps,
    required this.checkedAt,
    this.identity,
    this.binding,
    this.diagnostic,
    this.pendingDownload,
  });

  /// A result for an engine the preflight never reached because it was
  /// cancelled first — reported, not omitted.
  factory EnginePreflightResult.notReached({
    required String engineId,
    required String label,
  }) =>
      EnginePreflightResult(
        engineId: engineId,
        label: label,
        status: PreflightStatus.cancelled,
        steps: [
          for (final step in PreflightStep.values)
            PreflightStepResult(
                step,
                step == PreflightStep.platform
                    ? PreflightStatus.cancelled
                    : PreflightStatus.skipped,
                detail: step == PreflightStep.platform
                    ? 'Preflight was cancelled before this engine was checked'
                    : null),
        ],
        checkedAt: DateTime.now(),
      );

  bool get hasWarnings =>
      steps.any((step) => step.status == PreflightStatus.warning);

  /// The step that decided a non-passing outcome.
  PreflightStepResult? get decisiveStep {
    for (final step in steps) {
      if (step.status != PreflightStatus.passed &&
          step.status != PreflightStatus.warning &&
          step.status != PreflightStatus.skipped) {
        return step;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'engineId': engineId,
        'label': label,
        'status': status.id,
        'checkedAt': checkedAt.toUtc().toIso8601String(),
        'steps': [for (final step in steps) step.toJson()],
        if (identity != null) 'identity': identity!.toJson(),
        if (binding != null) 'binding': binding!.toJson(),
        if (diagnostic != null) 'diagnostic': diagnostic,
        if (pendingDownload != null)
          'pendingDownload': {
            'description': pendingDownload!.description,
            'source': pendingDownload!.source.toString(),
            if (pendingDownload!.license != null)
              'license': pendingDownload!.license,
          },
      };

  /// Text for the "copy diagnostics" action. Redacted: it is meant to be
  /// pasted into an issue.
  String toDiagnosticText() {
    final out = StringBuffer()
      ..writeln('Engine Preflight — $label ($engineId): ${status.id}')
      ..writeln('checked: ${checkedAt.toUtc().toIso8601String()}');
    final id = identity;
    if (id != null) {
      out.writeln('identity: ${id.label} · ${id.platform}/${id.backend} · '
          '${id.fingerprintKind} ${id.shortFingerprint}');
      if (id.fallbackReason != null) {
        out.writeln('fallback: ${id.fallbackReason}');
      }
    }
    for (final step in steps) {
      out.writeln('- ${step.step.id}: ${step.status.id}'
          '${step.millis == null ? '' : ' (${step.millis} ms)'}'
          '${step.detail == null ? '' : ' — ${step.detail}'}');
    }
    final diag = diagnostic;
    if (diag != null) {
      out.writeln('diagnostic:');
      out.writeln(const JsonEncoder.withIndent('  ').convert(diag));
    }
    return out.toString();
  }
}

/// Status for a structured startup failure.
PreflightStatus preflightStatusForKind(EngineFailureKind kind) =>
    switch (kind) {
      EngineFailureKind.unsupportedPlatform => PreflightStatus.unsupported,
      EngineFailureKind.runtimeMissing ||
      EngineFailureKind.binaryMissing ||
      EngineFailureKind.downloadRequired =>
        PreflightStatus.notInstalled,
      EngineFailureKind.handshakeTimeout ||
      EngineFailureKind.readinessTimeout =>
        PreflightStatus.timedOut,
      EngineFailureKind.cancelled => PreflightStatus.cancelled,
      _ => PreflightStatus.failed,
    };

/// Asked before anything is downloaded. Return true to allow it.
typedef PreflightDownloadConsent = Future<bool> Function(
    String engineLabel, EngineDownloadRequirement requirement);

/// Cooperative cancellation for a preflight in progress.
class PreflightCancellation {
  bool _cancelled = false;
  final _signal = Completer<void>();

  bool get isCancelled => _cancelled;
  Future<void> get whenCancelled => _signal.future;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
  }
}

/// Runs the checks for one engine.
class EnginePreflight {
  /// Upper bound for starting an engine, on top of the adapter's own
  /// handshake/readiness timeouts (a first-run model download is slow).
  final Duration initTimeout;

  /// Budget for the first search.
  final Duration moveTime;

  /// How long the first search may take beyond [moveTime].
  final Duration searchGrace;

  /// Position for the first search (a quiet opening with several legal
  /// replies, so a hard-coded "e2e4" cannot pass as legal).
  final String positionFen;

  const EnginePreflight({
    this.initTimeout = const Duration(minutes: 3),
    this.moveTime = const Duration(milliseconds: 200),
    this.searchGrace = const Duration(seconds: 20),
    this.positionFen =
        'r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3',
  });

  /// Checks one engine.
  ///
  /// [available]/[unavailableReason] come from the candidate list: an engine
  /// this platform cannot build is `unsupported` without being constructed.
  /// [build] constructs a fresh, uninitialized engine. [identity] is the
  /// identity the benchmark would record before starting it.
  Future<EnginePreflightResult> check({
    required String engineId,
    required String label,
    required bool available,
    String? unavailableReason,
    required ChessEngine Function() build,
    required EngineIdentity? identity,
    required BenchmarkConfig config,
    required String appBuild,
    required PreflightDownloadConsent consent,
    PreflightCancellation? cancellation,
    void Function(PreflightStepResult step)? onStep,
  }) async {
    final steps = <PreflightStepResult>[];
    final binding = identity == null
        ? null
        : PreflightBinding.of(identity, config, appBuild: appBuild);
    var checked = identity;
    Map<String, dynamic>? diagnostic;
    EngineDownloadRequirement? pending;

    void record(PreflightStepResult step) {
      steps.add(step);
      onStep?.call(step);
    }

    EnginePreflightResult finish(PreflightStatus status) {
      final reached = steps.map((s) => s.step).toSet();
      for (final step in PreflightStep.values) {
        if (!reached.contains(step)) {
          steps.add(PreflightStepResult(step, PreflightStatus.skipped));
        }
      }
      steps.sort((a, b) => a.step.index.compareTo(b.step.index));
      return EnginePreflightResult(
        engineId: engineId,
        label: label,
        status: status,
        steps: List.unmodifiable(steps),
        identity: checked,
        binding: binding,
        diagnostic: diagnostic,
        pendingDownload: pending,
        checkedAt: DateTime.now(),
      );
    }

    // 1. Platform.
    if (!available || identity == null) {
      record(PreflightStepResult(PreflightStep.platform,
          PreflightStatus.unsupported,
          detail: redactPersonalPaths(
              unavailableReason ?? 'This engine cannot run on this platform.')));
      return finish(PreflightStatus.unsupported);
    }
    record(PreflightStepResult(PreflightStep.platform, PreflightStatus.passed,
        detail: '${identity.platform}/${identity.backend}'));
    if (cancellation?.isCancelled ?? false) {
      record(const PreflightStepResult(
          PreflightStep.runtime, PreflightStatus.cancelled));
      return finish(PreflightStatus.cancelled);
    }

    final ChessEngine engine;
    try {
      engine = build();
    } catch (error) {
      record(PreflightStepResult(PreflightStep.runtime, PreflightStatus.failed,
          detail: _short(error)));
      return finish(PreflightStatus.failed);
    }

    PreflightStatus status;
    try {
      status = await _exercise(
        engine: engine,
        engineId: engineId,
        label: label,
        identity: identity,
        config: config,
        consent: consent,
        cancellation: cancellation,
        record: record,
        onDiagnostic: (value) => diagnostic = value,
        onPending: (value) => pending = value,
        onIdentity: (value) => checked = value,
      );
    } catch (error) {
      // A defect in a check must still produce a result, not a crash.
      record(PreflightStepResult(PreflightStep.firstSearch,
          PreflightStatus.failed,
          detail: 'preflight error: ${_short(error)}'));
      status = PreflightStatus.failed;
    }

    // 9. Cleanup — always, also after a failure: a half-started engine must
    // not keep a process, worker or model behind.
    final cleanup = _dispose(engine);
    record(cleanup);
    if (cleanup.status != PreflightStatus.passed && status.admits) {
      status = PreflightStatus.failed;
    } else if (status == PreflightStatus.passed &&
        steps.any((s) => s.status == PreflightStatus.warning)) {
      status = PreflightStatus.warning;
    }
    return finish(status);
  }

  /// Steps 2–8. Returns the outcome so far; records each step via [record].
  Future<PreflightStatus> _exercise({
    required ChessEngine engine,
    required String engineId,
    required String label,
    required EngineIdentity identity,
    required BenchmarkConfig config,
    required PreflightDownloadConsent consent,
    required PreflightCancellation? cancellation,
    required void Function(PreflightStepResult) record,
    required void Function(Map<String, dynamic>) onDiagnostic,
    required void Function(EngineDownloadRequirement?) onPending,
    required void Function(EngineIdentity) onIdentity,
  }) async {
    bool cancelled() => cancellation?.isCancelled ?? false;

    // 2. Runtime: anything to download first? Ask; never download silently.
    var runtimeRecorded = false;
    if (engine is DownloadAwareEngine) {
      EngineDownloadRequirement? requirement;
      try {
        requirement = await (engine as DownloadAwareEngine).pendingDownload();
      } catch (error) {
        record(PreflightStepResult(
            PreflightStep.runtime, PreflightStatus.warning,
            detail: 'could not tell whether a download is needed: '
                '${_short(error)}'));
        runtimeRecorded = true;
      }
      if (requirement != null) {
        final allowed = await consent(label, requirement);
        if (!allowed) {
          onPending(requirement);
          record(PreflightStepResult(
              PreflightStep.runtime, PreflightStatus.notInstalled,
              detail: 'needs a download that was not approved: '
                  '${requirement.description} from '
                  '${requirement.source.host}'));
          return PreflightStatus.notInstalled;
        }
        record(PreflightStepResult(PreflightStep.runtime, PreflightStatus.passed,
            detail: 'download approved: ${requirement.description}'));
        runtimeRecorded = true;
      }
    }
    if (!runtimeRecorded) {
      record(const PreflightStepResult(
          PreflightStep.runtime, PreflightStatus.passed));
    }
    if (cancelled()) {
      record(const PreflightStepResult(
          PreflightStep.initialization, PreflightStatus.cancelled));
      return PreflightStatus.cancelled;
    }

    // 3. Initialization, 4. readiness.
    final watch = Stopwatch()..start();
    var initialized = false;
    // Only Preflight's own deadline is reported as Preflight giving up; an
    // adapter's TimeoutException (no `uciok`, no `readyok`) carries the
    // adapter's recorded diagnostic and goes through engineFailureOf.
    var preflightTimedOut = false;
    try {
      await Future.any([
        engine.initialize().timeout(initTimeout, onTimeout: () {
          preflightTimedOut = true;
          throw TimeoutException(
              'Preflight stopped waiting for initialize()', initTimeout);
        }),
        if (cancellation != null)
          cancellation.whenCancelled.then<void>((_) =>
              throw const EngineStartupFailure(EngineFailureKind.cancelled,
                  'Preflight was cancelled')),
      ]);
      initialized = true;
      record(PreflightStepResult(
          PreflightStep.initialization, PreflightStatus.passed,
          millis: watch.elapsedMilliseconds));
      requireEngineReady(engine, platform: enginePlatformLabel());
      record(const PreflightStepResult(
          PreflightStep.readiness, PreflightStatus.passed));
    } catch (error, stack) {
      final EngineInitializationException failure;
      if (preflightTimedOut && error is TimeoutException) {
        failure = EngineInitializationException(
          engine: engine.name,
          version: engine.version,
          stage: EngineInitStage.initialize,
          platform: enginePlatformLabel(),
          cause: error,
          causeStack: stack,
          kind: EngineFailureKind.readinessTimeout,
          engineId: engineId,
          detail: 'Preflight stopped waiting after ${initTimeout.inSeconds}s',
        );
      } else if (error is EngineStartupFailure &&
          error.kind == EngineFailureKind.cancelled) {
        failure = EngineInitializationException(
          engine: engine.name,
          version: engine.version,
          stage: EngineInitStage.initialize,
          platform: enginePlatformLabel(),
          cause: error,
          kind: EngineFailureKind.cancelled,
          engineId: engineId,
        );
      } else {
        failure = engineFailureOf(engine, error, stack, engineId: engineId);
      }
      onDiagnostic(Map<String, dynamic>.from(failure.toJson()));
      final status = preflightStatusForKind(failure.kind);
      record(PreflightStepResult(
          initialized ? PreflightStep.readiness : PreflightStep.initialization,
          status,
          detail: failure.summary,
          millis: watch.elapsedMilliseconds));
      return status;
    }

    // 5. Identity: what actually started.
    final checked = _refine(identity, engine);
    onIdentity(checked);
    final runtime =
        engine is EngineRuntimeReport ? engine as EngineRuntimeReport : null;
    final requestedVersion = runtime?.requestedVersion;
    final detectedVersion = runtime?.detectedVersion;
    final versionDiffers = requestedVersion != null &&
        detectedVersion != null &&
        !_sameVersion(requestedVersion, detectedVersion);
    final fallback = runtime?.fallbackReason;
    final notes = <String>[
      'version ${checked.engineVersion.isEmpty ? 'not reported' : checked.engineVersion}',
      'backend ${runtime?.effectiveBackend ?? checked.backend}',
      if (versionDiffers) 'requested $requestedVersion, found $detectedVersion',
      if (fallback != null) 'fallback: ${redactPersonalPaths(fallback)}',
    ];
    record(PreflightStepResult(
        PreflightStep.identity,
        versionDiffers || fallback != null
            ? PreflightStatus.warning
            : PreflightStatus.passed,
        detail: notes.join('; ')));

    // 6. Options the benchmark will ask for.
    final requested = config.requestedOptions();
    if (engine is UciOptionAware) {
      final aware = engine as UciOptionAware;
      final missing = [
        for (final name in requested.keys)
          if (!aware.advertisesOption(name)) name
      ];
      record(PreflightStepResult(
          PreflightStep.options,
          missing.isEmpty ? PreflightStatus.passed : PreflightStatus.warning,
          detail: missing.isEmpty
              ? '${aware.advertisedOptionNames.length} options advertised'
              : 'not advertised (will not be applied): ${missing.join(', ')}'));
    } else {
      record(PreflightStepResult(PreflightStep.options, PreflightStatus.passed,
          detail: requested.isEmpty
              ? 'no options requested'
              : 'not a UCI-option engine; requested options do not apply'));
    }
    if (cancelled()) {
      record(const PreflightStepResult(
          PreflightStep.firstSearch, PreflightStatus.cancelled));
      return PreflightStatus.cancelled;
    }

    // 7. First search, 8. legal move.
    final board = chess.Chess();
    if (!board.load(positionFen)) {
      record(const PreflightStepResult(
          PreflightStep.firstSearch, PreflightStatus.failed,
          detail: 'the preflight position did not load'));
      return PreflightStatus.failed;
    }
    final search = Stopwatch()..start();
    final String move;
    try {
      move = await engine
          .bestMove('position fen $positionFen', moveTime: moveTime)
          .timeout(moveTime + searchGrace);
    } on TimeoutException {
      try {
        engine.stop();
      } catch (_) {}
      record(PreflightStepResult(
          PreflightStep.firstSearch, PreflightStatus.timedOut,
          detail: 'no move within ${(moveTime + searchGrace).inSeconds}s',
          millis: search.elapsedMilliseconds));
      return PreflightStatus.timedOut;
    } catch (error) {
      record(PreflightStepResult(
          PreflightStep.firstSearch, PreflightStatus.failed,
          detail: _short(error), millis: search.elapsedMilliseconds));
      return PreflightStatus.failed;
    }
    record(PreflightStepResult(PreflightStep.firstSearch, PreflightStatus.passed,
        detail: 'bestmove $move', millis: search.elapsedMilliseconds));
    if (!applyUciMove(board, move.trim())) {
      record(PreflightStepResult(
          PreflightStep.legalMove, PreflightStatus.failed,
          detail: 'illegal move "$move" in $positionFen'));
      return PreflightStatus.failed;
    }
    record(const PreflightStepResult(
        PreflightStep.legalMove, PreflightStatus.passed));
    return PreflightStatus.passed;
  }

  PreflightStepResult _dispose(ChessEngine engine) {
    try {
      engine.dispose();
      if (engine.state != EngineState.disposed) {
        return PreflightStepResult(PreflightStep.cleanup, PreflightStatus.failed,
            detail: 'the engine reported ${engine.state.name} after dispose');
      }
      return const PreflightStepResult(
          PreflightStep.cleanup, PreflightStatus.passed);
    } catch (error) {
      return PreflightStepResult(PreflightStep.cleanup, PreflightStatus.failed,
          detail: 'dispose failed: ${_short(error)}');
    }
  }

  EngineIdentity _refine(EngineIdentity identity, ChessEngine engine) {
    var refined = identity;
    if (identity.kind == 'custom') {
      if (engine.version.isNotEmpty) {
        refined = refined.withReportedIdentity(name: null, version: engine.version);
      }
      return refined;
    }
    if (engine is EngineRuntimeReport) {
      final report = engine as EngineRuntimeReport;
      refined = refined.withRuntime(
        detectedVersion: report.detectedVersion,
        backend: report.effectiveBackend,
        fallbackReason: report.fallbackReason,
      );
    }
    return refined;
  }
}

/// `16` matches `16`, `16.0`; `16` does not match `17` or `10`.
bool _sameVersion(String requested, String detected) {
  final a = requested.trim().toLowerCase();
  final b = detected.trim().toLowerCase();
  if (a == b) return true;
  return b == '$a.0' || b.startsWith('$a.0.') || a == '$b.0';
}

String _short(Object error) {
  final text = redactPersonalPaths(error.toString()).replaceAll('\n', ' ');
  return text.length <= 240 ? text : '${text.substring(0, 240)}…';
}

/// Which engines a benchmark may use, from the latest preflight results.
///
/// Admission requires, per engine: a result whose binding matches the engine
/// as it would run now, with status `passed` — or `warning` once the user has
/// reviewed the warnings ([acknowledgeWarnings]). Everything else is listed
/// with the reason, never dropped.
class PreflightGate {
  final Map<String, EnginePreflightResult> _results = {};
  final Set<String> _acknowledged = {};

  Map<String, EnginePreflightResult> get results => Map.unmodifiable(_results);

  void record(EnginePreflightResult result) {
    _results[result.engineId] = result;
    _acknowledged.remove(result.engineId);
  }

  void forget(String engineId) {
    _results.remove(engineId);
    _acknowledged.remove(engineId);
  }

  void clear() {
    _results.clear();
    _acknowledged.clear();
  }

  /// The user has read the warnings for [engineId] and accepts them.
  void acknowledgeWarnings(String engineId) {
    final result = _results[engineId];
    if (result != null && result.status == PreflightStatus.warning) {
      _acknowledged.add(engineId);
    }
  }

  bool warningsAcknowledged(String engineId) => _acknowledged.contains(engineId);

  /// Why the stored result does not describe [current], or null when it does.
  String? isStale(String engineId, PreflightBinding? current) {
    final result = _results[engineId];
    if (result == null) return 'not checked';
    final binding = result.binding;
    if (binding == null || current == null) {
      return result.status == PreflightStatus.unsupported ? null : 'not checked';
    }
    return binding.changeFrom(current);
  }

  /// Splits [engineIds] into admitted engines and the reason each other one
  /// is not admitted. [bindings] are the current bindings per engine id.
  PreflightAdmission admission(
      List<String> engineIds, Map<String, PreflightBinding?> bindings) {
    final admitted = <String>[];
    final excluded = <String, String>{};
    for (final id in engineIds) {
      final result = _results[id];
      if (result == null) {
        excluded[id] = 'not checked';
        continue;
      }
      final stale = isStale(id, bindings[id]);
      if (stale != null) {
        excluded[id] = 'result is out of date: $stale';
        continue;
      }
      switch (result.status) {
        case PreflightStatus.passed:
          admitted.add(id);
        case PreflightStatus.warning:
          if (_acknowledged.contains(id)) {
            admitted.add(id);
          } else {
            excluded[id] = 'warnings not reviewed';
          }
        default:
          excluded[id] = result.status.id;
      }
    }
    return PreflightAdmission(admitted, excluded);
  }
}

class PreflightAdmission {
  final List<String> admitted;

  /// Engine id → why it is not admitted (`failed`, `not checked`, …).
  final Map<String, String> excluded;

  const PreflightAdmission(this.admitted, this.excluded);

  bool get allAdmitted => excluded.isEmpty;
}
