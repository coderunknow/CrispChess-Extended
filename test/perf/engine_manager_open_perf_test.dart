/// Reproduction and measurement harness for the Engine Manager open path
/// (dev6 audit, Phase 1).
///
/// Measures the work the manager's open path performs against a set of fake
/// engine binaries — the same operations the screen triggers through
/// [BenchmarkService.changedEngines] and the automatic-benchmark decisions —
/// so the before/after comparison of the performance repair is reproducible
/// without the real engines or the target hardware.
///
/// Run: flutter test test/perf/engine_manager_open_perf_test.dart
/// Optional: PERF_RESULTS_PATH=<file> also writes the measurements as JSON.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crispchess/bench/benchmark_fingerprint.dart' show sha256OfFile;
import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_settings.dart';
import 'package:crispchess/bench/benchmark_storage_io.dart';
import 'package:crispchess/bench/benchmark_store.dart'
    show BenchmarkStore, kBenchmarkIdentitiesKey;
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/engines/engine_registry.dart' show customEngineId;
import 'package:crispchess/engines/generic_uci_engine_stub.dart';

/// Binary sizes in MB: two large neural-network style engines (lc0's network
/// is ~40 MB), a few mid-size Stockfish-class binaries, and several small
/// ones. Total ≈ 84 MB per full scan.
const _sizesMb = [20, 20, 8, 8, 8, 4, 4, 4, 4, 4];

class _Harness {
  late Directory root;
  late BenchmarkService service;
  final List<EngineProfile> profiles = [];

  Future<void> setUp() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    root = await Directory.systemTemp.createTemp('dev6-perf-');
    service = BenchmarkService(
      store: BenchmarkStore(
          storage: FileBenchmarkStorage(rootOverride: root)),
    );
    await service.init();
    await _writeBinaries();
    for (final entry in _sizesMb.indexed) {
      final (index, mb) = entry;
      final profile = EngineProfile(
          name: 'FakeEngine$index',
          path: '${root.path}/engine_$index.bin');
      await service.profileStore.add(profile);
      profiles.add(profile);
    }
  }

  /// Fake binaries: repeated deterministic bytes, cheap to generate.
  Future<void> _writeBinaries() async {
    final block = utf8.encode('CrispChessDev6PerfHarness0123456789\n');
    for (var index = 0; index < _sizesMb.length; index++) {
      final sizeBytes = _sizesMb[index] * 1024 * 1024;
      final data = List<int>.filled(sizeBytes, 0);
      for (var i = 0; i < sizeBytes; i++) {
        data[i] = block[i % block.length];
      }
      await File('${root.path}/engine_$index.bin')
          .writeAsBytes(data, flush: true);
    }
  }

  /// Seeds the "previously benchmarked" state: the identity of every engine is
  /// stored with its *current* fingerprint, so the change scan measures the
  /// steady-state cost of an open — hashing/lookup work only, no re-run.
  Future<void> seedKnownIdentities() async {
    final identities = <String, Map<String, dynamic>>{};
    for (final profile in profiles) {
      final fingerprint = await service.store
          .fingerprintForProfile(profile.id, profile.path);
      final identity = EngineIdentity.forCustom(
        profile: profile,
        detectedName: profile.displayName,
        detectedAuthor: null,
        binarySha256: fingerprint.sha256,
        stat: fingerprint.stat,
      );
      identities[customEngineId(profile)] = identity.toJson();
    }
    await service.store.storage
        .write(kBenchmarkIdentitiesKey, jsonEncode(identities));
  }

  /// A fresh service, like the next app launch (in-memory caches empty).
  BenchmarkService freshService() => BenchmarkService(
        store: BenchmarkStore(
            storage: FileBenchmarkStorage(rootOverride: root)),
      );

  Future<void> tearDown() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Max event-loop gap observed while [action] runs — a responsiveness proxy:
/// a UI isolate doing the hashing itself shows long gaps, hashing on a worker
/// isolate does not.
Future<Duration> _maxEventLoopGap(Future<void> Function() action) async {
  final maxGap = Stopwatch();
  var longest = Duration.zero;
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    if (maxGap.isRunning) {
      if (maxGap.elapsed > longest) longest = maxGap.elapsed;
    }
    maxGap
      ..reset()
      ..start();
  });
  try {
    await action();
  } finally {
    timer.cancel();
    if (maxGap.isRunning && maxGap.elapsed > longest) {
      longest = maxGap.elapsed;
    }
  }
  return longest;
}

void main() {
  test(
    'Engine Manager open path: measurements',
    timeout: const Timeout(Duration(minutes: 10)),
    () async {
      final harness = _Harness();
      await harness.setUp();
      await harness.seedKnownIdentities();
      final results = <String, Object>{};
      const reps = 3;

      // --- Profile load (the screen's first step) --------------------------
      final loadStopwatch = Stopwatch()..start();
      await harness.service.profileStore.load();
      loadStopwatch.stop();
      results['profileLoadMs'] = loadStopwatch.elapsedMicroseconds / 1000;

      // --- Settings read ----------------------------------------------------
      final settingsStopwatch = Stopwatch()..start();
      final defaults = await harness.service.autoSettings();
      settingsStopwatch.stop();
      results['autoSettingsReadMs'] =
          settingsStopwatch.elapsedMicroseconds / 1000;
      results['defaultAfterAdd'] = defaults.afterAdd;
      results['defaultAfterVersionChange'] = defaults.afterVersionChange;

      // --- Change scan, cold (fingerprint cache deleted) --------------------
      // The cache has a crash-recovery copy (fingerprints.json.bak) that
      // storage.read() falls back to when the primary is missing, so deleting
      // only the file leaves a near-warm cache (dev6 review). The storage
      // API's delete removes both copies — that is a real cold cache.
      final coldScan = <double>[];
      for (var i = 0; i < reps; i++) {
        final service = harness.freshService();
        await service.init();
        await harness.service.store.storage.delete('fingerprints');
        final stopwatch = Stopwatch()..start();
        final changed = await service.changedEngines();
        stopwatch.stop();
        coldScan.add(stopwatch.elapsedMicroseconds / 1000);
        results['coldScanChangedCount_run$i'] = changed.length;
      }
      results['coldScanMsMedian'] = _median(coldScan);

      // --- Change scan, warm, fresh service (next app launch) ---------------
      final warmScan = <double>[];
      for (var i = 0; i < reps; i++) {
        final service = harness.freshService();
        await service.init();
        final stopwatch = Stopwatch()..start();
        await service.changedEngines();
        stopwatch.stop();
        warmScan.add(stopwatch.elapsedMicroseconds / 1000);
      }
      results['warmScanNewServiceMsMedian'] = _median(warmScan);

      // --- Change scan, warm, same service (re-open in one session) ---------
      final sameService = harness.freshService();
      await sameService.init();
      final sameScan = <double>[];
      for (var i = 0; i < reps; i++) {
        final stopwatch = Stopwatch()..start();
        await sameService.changedEngines();
        stopwatch.stop();
        sameScan.add(stopwatch.elapsedMicroseconds / 1000);
      }
      results['warmScanSameServiceMsMedian'] = _median(sameScan);

      // --- Re-benchmark decision for an unchanged engine --------------------
      // With the factory defaults the decision stops at its settings gate,
      // which is a different operation from the baseline's change detection
      // (dev6 review). The trigger is enabled here so both revisions measure
      // the same path, and the decision is asserted unchanged before timing.
      await harness.service.setAutoSettings(const AutoBenchmarkSettings(
          afterAdd: false, afterVersionChange: true));
      final decisionProbe = await harness.service
          .decideAfterChange(customEngineId(harness.profiles.first));
      results['decisionProbeShouldRun'] = decisionProbe.shouldRun;
      results['decisionProbeReason'] = decisionProbe.reason;
      final decision = <double>[];
      for (var i = 0; i < reps; i++) {
        final stopwatch = Stopwatch()..start();
        await harness.service.decideAfterChange(customEngineId(harness.profiles.first));
        stopwatch.stop();
        decision.add(stopwatch.elapsedMicroseconds / 1000);
      }
      results['decideAfterChangeMsMedian'] = _median(decision);

      // --- Add-decision with afterAdd off (must stay cheap) -----------------
      final offSettings = AutoBenchmarkSettings(
          afterAdd: false, afterVersionChange: false);
      await harness.service.setAutoSettings(offSettings);
      final offStopwatch = Stopwatch()..start();
      final offDecision =
          await harness.service.decideAfterAdd(harness.profiles.first);
      offStopwatch.stop();
      results['decideAfterAddOffMs'] = offStopwatch.elapsedMicroseconds / 1000;
      results['decideAfterAddOffShouldRun'] = offDecision.shouldRun;

      // --- Responsiveness proxy while a binary is hashed --------------------
      final gap = await _maxEventLoopGap(() async {
        await sha256OfFile('${harness.root.path}/engine_0.bin');
      });
      results['hash20MBMaxEventLoopGapMs'] = gap.inMicroseconds / 1000;
      final hashStopwatch = Stopwatch()..start();
      await sha256OfFile('${harness.root.path}/engine_0.bin');
      hashStopwatch.stop();
      results['hash20MBWallMs'] = hashStopwatch.elapsedMicroseconds / 1000;

      // --- Environment ------------------------------------------------------
      results['binaryCount'] = _sizesMb.length;
      results['totalBinaryMB'] = _sizesMb.fold<int>(0, (a, b) => a + b);
      results['platform'] = Platform.operatingSystemVersion;

      final json = const JsonEncoder.withIndent('  ').convert(results);
      // ignore: avoid_print
      print('PERF_RESULTS_BEGIN\n$json\nPERF_RESULTS_END');
      final out = Platform.environment['PERF_RESULTS_PATH'];
      if (out != null) {
        await File(out).writeAsString(json, flush: true);
      }
      await harness.tearDown();
    },
  );
}
