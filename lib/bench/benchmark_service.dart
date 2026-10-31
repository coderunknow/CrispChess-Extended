/// One place that knows what can be benchmarked, and how a run is started.
///
/// Everything the Engine Lab and the automatic triggers need lives here, so a
/// run started by the Engine Manager after an engine was added is the same run
/// as one started by hand: same plan, same runner, same storage, same rules.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

import '../engines/engine_registry.dart';
import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../services/engine_profile_store.dart';
import 'benchmark_config.dart';
import 'benchmark_environment.dart';
import 'benchmark_plan.dart';
import 'benchmark_run.dart';
import 'benchmark_runner.dart';
import 'benchmark_settings.dart';
import 'benchmark_store.dart';
import 'calibration.dart';
import 'engine_identity.dart';
import 'opening_suite.dart';
import 'stability_probe.dart';

/// One engine the Lab could measure, and whether it can run here.
class EngineCandidate {
  final String engineId;
  final String label;

  /// True for a user-added UCI engine.
  final bool isCustom;

  /// False when the platform cannot build this engine at all (a browser cannot
  /// start a user-supplied executable).
  final bool available;

  /// Why it is unavailable. Null when it is available.
  final String? unavailableReason;

  const EngineCandidate({
    required this.engineId,
    required this.label,
    required this.isCustom,
    this.available = true,
    this.unavailableReason,
  });
}

/// What an automatic trigger decided, and why.
///
/// A refusal carries a reason too: "nothing happened" is not an answer the UI
/// can give honestly, and it would leave the user unable to tell a disabled
/// setting from a broken one.
class AutoBenchmarkDecision {
  final bool shouldRun;
  final String reason;

  /// The run to start; null when [shouldRun] is false.
  final BenchmarkConfig? config;

  /// The engine the decision is about.
  final EngineIdentity? identity;

  /// Engines to play against, chosen when the decision was made.
  final List<String> opponents;

  const AutoBenchmarkDecision({
    required this.shouldRun,
    required this.reason,
    this.config,
    this.identity,
    this.opponents = const [],
  });

  factory AutoBenchmarkDecision.skip(String reason) =>
      AutoBenchmarkDecision(shouldRun: false, reason: reason);
}

/// An engine whose stored measurement no longer describes the binary on disk.
class ChangedEngine {
  final String engineId;
  final String label;
  final String change;

  const ChangedEngine({
    required this.engineId,
    required this.label,
    required this.change,
  });
}

class BenchmarkService {
  final BenchmarkStore store;
  final BenchmarkSettingsStore settingsStore;
  final EngineProfileStore profileStore;

  BenchmarkService({
    BenchmarkStore? store,
    BenchmarkSettingsStore? settingsStore,
    EngineProfileStore? profileStore,
  })  : store = store ?? BenchmarkStore(),
        settingsStore = settingsStore ?? BenchmarkSettingsStore(),
        profileStore = profileStore ?? EngineProfileStore();

  static BenchmarkService? _shared;

  /// The instance the whole app shares, so a run started from the Engine
  /// Manager is visible in the Lab and vice versa.
  static BenchmarkService get shared => _shared ??= BenchmarkService();

  /// Drops the shared instance. For tests, and for a sign-out-style reset that
  /// this app does not have yet.
  static void resetShared() => _shared = null;

  BenchmarkRunner? _active;
  Future<String>? _appVersion;

  bool get isRunning => _active != null;
  BenchmarkRunner? get activeRunner => _active;

  Future<void> init() async {
    await store.init();
    await settingsStore.init();
  }

  /// The app version recorded with a run, from the platform rather than a
  /// constant, so a report says which build produced it.
  Future<String> appVersion() => _appVersion ??= () async {
        try {
          final info = await PackageInfo.fromPlatform();
          final version = info.version.trim();
          final build = info.buildNumber.trim();
          if (version.isEmpty) return kBenchmarkFormatVersion;
          return build.isEmpty ? version : '$version+$build';
        } catch (error) {
          debugPrint('[EngineLab] package info unavailable: $error');
          return kBenchmarkFormatVersion;
        }
      }();

  // ------------------------------------------------------------------ engines

  Future<List<EngineProfile>> profiles() async {
    try {
      return await profileStore.load();
    } catch (error) {
      debugPrint('[EngineLab] could not load engine profiles: $error');
      return const [];
    }
  }

  /// Every engine that could take part, including the ones that cannot run on
  /// this platform — with the reason, instead of disappearing from the list.
  Future<List<EngineCandidate>> candidates() async {
    // Named for what it holds: a local called `candidates` in a method called
    // `candidates` shadows the method, and the next `candidates()` inside it
    // would refer to a list that is not initialised yet.
    final found = <EngineCandidate>[];
    for (final name in builtInMatchEngines) {
      found.add(EngineCandidate(
        engineId: builtInEngineId(name),
        label: name,
        isCustom: false,
      ));
    }
    for (final profile in await profiles()) {
      found.add(EngineCandidate(
        engineId: customEngineId(profile),
        label: profile.displayName,
        isCustom: true,
        available: customEnginesSupported,
        unavailableReason: customEnginesSupported
            ? null
            : 'A browser cannot start a user-supplied executable.',
      ));
    }
    return found;
  }

  /// The identity a run records for [engineId].
  ///
  /// Throws [EngineUnavailableException] when the engine cannot be built here:
  /// an identity invented from a name would put a number in a rating pool for
  /// an engine that never ran.
  Future<EngineIdentity> identityFor(String engineId) async {
    if (isCustomEngineId(engineId)) {
      if (!customEnginesSupported) {
        throw EngineUnavailableException(
            engineId, 'custom engines cannot run in a browser');
      }
      final all = await profiles();
      final profile = profileForEngineId(engineId, all);
      if (profile == null) {
        throw EngineUnavailableException(engineId, 'the engine profile is gone');
      }
      final fingerprint =
          await store.fingerprintForProfile(profile.id, profile.path);
      return EngineIdentity.forCustom(
        profile: profile,
        detectedName: profile.detectedName,
        detectedAuthor: profile.detectedAuthor,
        binarySha256: fingerprint.sha256,
        stat: fingerprint.stat,
      );
    }

    final name = builtInNameFromId(engineId);
    if (name == null) {
      throw EngineUnavailableException(engineId, 'not a known engine id');
    }
    final engine = createEngineForId(engineId, profiles: const []);
    try {
      return EngineIdentity.forBuiltIn(
        name: name,
        engineVersion: engine.version,
        appBuild: kBenchmarkFormatVersion,
      );
    } finally {
      engine.dispose();
    }
  }

  // --------------------------------------------------------------------- runs

  /// Builds a runner without starting it, so the caller can attach listeners
  /// and pass it to [runWithRunner]. The Lab does this to show progress from the
  /// first event; [run] is the short form for callers that do not care.
  Future<BenchmarkRunner> createRunner({
    required List<String> engineIds,
    required BenchmarkConfig config,
    TournamentFormat format = TournamentFormat.roundRobin,
    String? referenceEngineId,
    Map<String, OpeningSuite> suites = const {},
    RatingAnchor? anchor,
    String? trigger,
  }) async {
    if (_active != null) {
      throw StateError('A benchmark is already running.');
    }
    if (engineIds.length < 2) {
      throw ArgumentError('A benchmark needs at least two engines.');
    }
    final validation = validateConfig(config, engineCount: engineIds.length);
    if (!validation.isValid) {
      throw ArgumentError(validation.errors.join(' '));
    }

    final all = await profiles();
    final identities = <EngineIdentity>[];
    final slots = <String, BenchEngineSlot>{};
    final unavailable = <String>[];
    for (final engineId in engineIds) {
      try {
        final identity = await identityFor(engineId);
        identities.add(identity);
        slots[identity.engineId] = BenchEngineSlot(
          identity: identity,
          build: () => createEngineForId(engineId, profiles: all),
        );
      } on EngineUnavailableException catch (error) {
        unavailable.add(
            '${engineLabelForId(engineId, all)}: ${error.reason}');
      }
    }
    if (identities.length < 2) {
      throw StateError('Fewer than two engines can run here. '
          '${unavailable.join('; ')}');
    }

    final suite = openingSuiteById(config.openingSuiteId, extra: suites);
    final plan = buildPlan(
      config: config,
      engines: identities,
      format: format,
      referenceEngineId: referenceEngineId,
      suite: suite,
    );
    final runner = BenchmarkRunner(
      plan: plan,
      slots: slots,
      environment: BenchmarkEnvironment.capture(appVersion: await appVersion()),
      anchor: anchor,
      trigger: trigger,
      // Stored as the run goes: closing the app mid-benchmark keeps the games
      // already played, marked as a partial run rather than as a finished one.
      onProgressSave: store.saveRun,
      validationWarnings: [...validation.warnings, ...unavailable],
    );
    return runner;
  }

  /// Runs [runner] to completion, saving it, and releases the "running" flag.
  Future<BenchmarkRun> runWithRunner(BenchmarkRunner runner) async {
    _active = runner;
    try {
      final run = await runner.run();
      await store.saveRun(run);
      return run;
    } finally {
      _active = null;
      await runner.dispose();
    }
  }

  Future<BenchmarkRun> run({
    required List<String> engineIds,
    required BenchmarkConfig config,
    TournamentFormat format = TournamentFormat.roundRobin,
    String? referenceEngineId,
    Map<String, OpeningSuite> suites = const {},
    RatingAnchor? anchor,
    String? trigger,
  }) async {
    final runner = await createRunner(
      engineIds: engineIds,
      config: config,
      format: format,
      referenceEngineId: referenceEngineId,
      suites: suites,
      anchor: anchor,
      trigger: trigger,
    );
    return runWithRunner(runner);
  }

  Future<StabilityReport> probeStability(
    String engineId, {
    StabilityProbe probe = const StabilityProbe(),
  }) async {
    final identity = await identityFor(engineId);
    final all = await profiles();
    return probe.run(
      identity: identity,
      build: () => createEngineForId(engineId, profiles: all),
    );
  }

  // ------------------------------------------------------------------ history

  Future<List<BenchmarkRunSummary>> history() => store.summaries();

  Future<BenchmarkRun?> loadRun(String id) => store.loadRun(id);

  Future<bool> deleteRun(String id) => store.deleteRun(id);

  Future<ImportResult> importRun(String text) async {
    final results = await store.importJson(text);
    return results.first;
  }

  Future<String?> exportRunJson(String id) => store.exportRunJson(id);

  Future<String> exportAllJson() => store.exportAllJson();

  // ----------------------------------------------------------------- settings

  Future<AutoBenchmarkSettings> autoSettings() => settingsStore.autoSettings();

  Future<void> setAutoSettings(AutoBenchmarkSettings settings) =>
      settingsStore.setAutoSettings(settings);

  Future<BenchmarkConfig> lastConfig() => settingsStore.lastConfig();

  Future<void> setLastConfig(BenchmarkConfig config) =>
      settingsStore.setLastConfig(config);

  Future<List<String>> lastEngineIds() => settingsStore.lastEngineIds();

  Future<void> setLastEngineIds(List<String> ids) =>
      settingsStore.setLastEngineIds(ids);

  Future<Map<String, OpeningSuite>> openingSuites() =>
      settingsStore.openingSuites();

  Future<void> setOpeningSuites(Map<String, OpeningSuite> suites) =>
      settingsStore.setOpeningSuites(suites);

  Future<List<RatingAnchor>> anchors() => settingsStore.anchors();

  Future<void> saveAnchors(List<RatingAnchor> anchors) =>
      settingsStore.setAnchors(anchors);

  // ----------------------------------------------------------------- triggers

  /// Whether the engine on disk still matches what was measured.
  ///
  /// Only engines that have been benchmarked before are checked: fingerprinting
  /// every engine at start-up would hash every binary on the device to learn
  /// that nothing changed.
  Future<List<ChangedEngine>> changedEngines() async {
    final known = await store.knownIdentities();
    final all = await profiles();
    final changed = <ChangedEngine>[];
    for (final entry in known.entries) {
      try {
        final identity = await identityFor(entry.key);
        final change = identity.changeFrom(entry.value);
        if (change != null) {
          changed.add(ChangedEngine(
            engineId: entry.key,
            label: identity.label,
            change: change,
          ));
        }
      } on EngineUnavailableException catch (error) {
        changed.add(ChangedEngine(
          engineId: entry.key,
          label: engineLabelForId(entry.key, all),
          change: 'unavailable: ${error.reason}',
        ));
      } catch (error) {
        debugPrint('[EngineLab] could not check ${entry.key}: $error');
      }
    }
    return changed;
  }

  /// Engines an automatic run could compare [engineId] against.
  ///
  /// Other user-added engines first — same backend, so the comparison means
  /// something — then one built-in engine as a reference point.
  Future<List<String>> _opponentsFor(String engineId) async {
    final candidates = await candidates();
    final custom = [
      for (final candidate in candidates)
        if (candidate.available && candidate.isCustom && candidate.engineId != engineId)
          candidate.engineId
    ];
    if (custom.isNotEmpty) return custom.take(3).toList();
    final builtIn = [
      for (final candidate in candidates)
        if (candidate.available && !candidate.isCustom)
          candidate.engineId
    ];
    return builtIn.take(2).toList();
  }

  /// Whether adding [profile] should start a benchmark.
  Future<AutoBenchmarkDecision> decideAfterAdd(EngineProfile profile) async {
    if (!customEnginesSupported) {
      return AutoBenchmarkDecision.skip(
          'Automatic benchmarks need a platform that can run a downloaded '
          'executable, and a browser cannot.');
    }
    final settings = await settingsStore.autoSettings();
    if (!settings.afterAdd) {
      return AutoBenchmarkDecision.skip(
          'Automatic benchmarks after adding an engine are switched off.');
    }
    final engineId = customEngineId(profile);
    EngineIdentity identity;
    try {
      identity = await identityFor(engineId);
    } on EngineUnavailableException catch (error) {
      return AutoBenchmarkDecision.skip(
          'That engine cannot be started here (${error.reason}).');
    }
    if (identity.fingerprintKind == 'unavailable') {
      return AutoBenchmarkDecision.skip(
          'The engine binary could not be fingerprinted, so a later change '
          'could not be detected either.');
    }
    final known = await store.knownIdentities();
    final previous = known[identity.engineId];
    if (previous != null && previous.matchesVersionOf(identity)) {
      return AutoBenchmarkDecision.skip(
          'This build of the engine has already been benchmarked.');
    }
    final opponents = await _opponentsFor(engineId);
    if (opponents.isEmpty) {
      return AutoBenchmarkDecision.skip(
          'There is no other engine to play against.');
    }
    return AutoBenchmarkDecision(
      shouldRun: true,
      reason: previous == null
          ? 'New engine: measuring it against ${opponents.length} '
              'engine(s) with the Quick preset.'
          : 'The engine changed: re-measuring it with the Quick preset.',
      config: settings.toConfig(
          seed: DateTime.now().millisecondsSinceEpoch % 100000),
      identity: identity,
      opponents: opponents,
    );
  }

  /// Whether an engine whose binary changed should be re-measured.
  Future<AutoBenchmarkDecision> decideAfterChange(String engineId) async {
    final settings = await settingsStore.autoSettings();
    if (!settings.afterVersionChange) {
      return AutoBenchmarkDecision.skip(
          'Automatic benchmarks after an engine change are switched off.');
    }
    final known = await store.knownIdentities();
    final previous = known[engineId];
    if (previous == null) {
      return AutoBenchmarkDecision.skip(
          'That engine has never been benchmarked, so nothing can have '
          'changed.');
    }
    EngineIdentity identity;
    try {
      identity = await identityFor(engineId);
    } on EngineUnavailableException catch (error) {
      return AutoBenchmarkDecision.skip(
          'That engine cannot be started here (${error.reason}).');
    }
    final change = identity.changeFrom(previous);
    if (change == null) {
      return AutoBenchmarkDecision.skip('The engine is unchanged.');
    }
    final opponents = await _opponentsFor(engineId);
    if (opponents.isEmpty) {
      return AutoBenchmarkDecision.skip(
          'There is no other engine to play against.');
    }
    return AutoBenchmarkDecision(
      shouldRun: true,
      reason: 'The engine changed ($change): re-measuring it with the Quick '
          'preset.',
      config: settings.toConfig(
          seed: DateTime.now().millisecondsSinceEpoch % 100000),
      identity: identity,
      opponents: opponents,
    );
  }

  /// Starts the run a decision describes, or returns null when it decided not
  /// to run. Never throws for a refusal; a failure to start is reported to the
  /// caller, which shows it.
  Future<BenchmarkRun?> runAutomatic(AutoBenchmarkDecision decision) async {
    final identity = decision.identity;
    final config = decision.config;
    if (!decision.shouldRun || identity == null || config == null) return null;
    if (_active != null) {
      debugPrint('[EngineLab] automatic run skipped: a benchmark is running');
      return null;
    }
    final engineIds = [identity.engineId, ...decision.opponents];
    if (engineIds.length < 2) return null;
    return run(
      engineIds: engineIds,
      config: config,
      trigger: 'automatic',
    );
  }

  /// True when this platform can benchmark user-added engines.
  bool get supportsCustomEngines => customEnginesSupported;

  /// A short note for the Lab about what this platform can measure.
  String get platformNote => kIsWeb
      ? 'Web builds benchmark the engines that ship with the app. A '
          'user-supplied executable cannot start in a browser.'
      : 'This build benchmarks every engine listed here, including the ones '
          'you added yourself.';
}
