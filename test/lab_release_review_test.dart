import 'dart:async';
import 'dart:io';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/calibration.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bench_harness.dart';

RatingAnchor anchor(String id, {String version = '1.0', int budget = 100, String? hint}) =>
    RatingAnchor(
      id: id, engineName: 'Alpha', engineIdHint: hint, engineVersion: version,
      rating: 2000, scale: 'test', source: 'test', publishedDate: '2026-01-01',
      hardware: 'test', timeControl: 'test', timePerMoveMs: budget,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('later compatible anchor is selected over incompatible first match', () {
    final identities = [testIdentity('Alpha'), testIdentity('Beta')];
    final config = BenchmarkConfig.quick;
    final selected = selectCompatibleAnchor([
      anchor('wrong-version', version: '2.0'),
      anchor('wrong-budget', budget: 1000),
      anchor('conflicting-hint', hint: 'builtin:Gamma'),
      anchor('valid'),
    ], identities, config);
    expect(selected?.id, 'valid');
    expect(selectCompatibleAnchor([anchor('depth', version: '1.0')], identities,
        config.copyWith(searchDepth: () => 3)), isNull);
  });

  test('concurrent automatic preparation returns null instead of StateError', () async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(appName: 'CrispChess', packageName: 'crispchess', version: '2.3.2', buildNumber: '19', buildSignature: '');
    // A real temporary file makes fingerprintForProfile consult the gated
    // storage cache; a missing path returns before any storage read.
    final dir = await Directory.systemTemp.createTemp('crisp-lab-concurrent-');
    addTearDown(() => dir.delete(recursive: true));
    final binary = File('${dir.path}/alpha.bin');
    await binary.writeAsBytes(List<int>.filled(64, 7));
    final profiles = EngineProfileStore();
    await profiles.add(EngineProfile(id: 'p', name: 'Alpha', path: binary.path));
    // Resolve the custom identity before arming the gate; otherwise identity
    // discovery itself blocks and the test never reaches concurrent runAutomatic.
    final identityService = BenchmarkService(
      store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
      profileStore: profiles,
    );
    final identity = await identityService.identityFor('custom:p');
    final gate = Completer<void>();
    final store = BenchmarkStore(storage: _GatedStorage(gate));
    final service = BenchmarkService(store: store, profileStore: profiles);
    final decision = AutoBenchmarkDecision(
      shouldRun: true, reason: 'test', config: BenchmarkConfig.quick,
      identity: identity, opponents: const ['builtin:Built-in'],
    );
    final first = service.runAutomatic(decision);
    await Future<void>.delayed(Duration.zero);
    // The regression is the concurrent caller: it must be skipped, not throw
    // StateError. The first caller may still fail because the fixture binary is
    // not a real engine; that outcome is intentionally not asserted here.
    expect(await service.runAutomatic(decision), isNull);
    gate.complete();
    await first.then<void>((_) {}, onError: (Object _) {});
    await service.activeRunner?.dispose();
  });

  test('option synchronization cancellation keeps its reason', () async {
    final alpha = _SlowOptionsEngine('Alpha');
    final beta = ScriptedEngine('Beta');
    final identities = [testIdentity('Alpha'), testIdentity('Beta')];
    final runner = BenchmarkRunner(
      plan: buildPlan(config: benchConfig().copyWith(threads: 1, hashMb: 16), engines: identities),
      slots: {
        identities[0].engineId: BenchEngineSlot(identity: identities[0], build: () => alpha),
        identities[1].engineId: BenchEngineSlot(identity: identities[1], build: () => beta),
      },
      environment: BenchmarkEnvironment.unknown,
    );
    addTearDown(runner.dispose);
    final pending = runner.run();
    await alpha.optionsStarted.future;
    runner.cancel();
    alpha.optionsGate.complete();
    final run = await pending;
    expect(run.stopReason, 'cancelled');
    expect(run.engineStatus[identities[0].engineId]!.reason,
        'Initialization cancelled by user.');
  });

  test('UCI trailing integer, dotted and hyphenated versions are preserved', () async {
    for (final entry in {
      'Stockfish 17': '17', 'Komodo 14': '14', 'Berserk 13': '13',
      'Stockfish 17.1': '17.1', 'Engine 1.2-rc3': '1.2-rc3', 'NoVersion': '',
      'Komodo 14.1 64-bit': '14.1', 'Engine 2.0 x86_64-bit': '2.0',
    }.entries) {
      final engine = GenericUciEngine(EngineProfile(name: 'test', path: 'unused'));
      // The handshake parser is private; exercise it through the same line
      // handler used by the process stdout subscription.
      engine.debugHandleLine('id name ${entry.key}', handshake: true);
      expect(engine.version, entry.value, reason: entry.key);
      engine.dispose();
    }
  });
}

class _GatedStorage extends MemoryBenchmarkStorage {
  final Completer<void> gate;
  _GatedStorage(this.gate);
  @override
  Future<void> init() async {
    await gate.future;
    return super.init();
  }
  @override
  Future<String?> read(String key) async {
    await gate.future;
    return super.read(key);
  }
}

class _SlowOptionsEngine extends ScriptedEngine {
  _SlowOptionsEngine(super.name);
  final optionsStarted = Completer<void>();
  final optionsGate = Completer<void>();
  @override
  Future<void> synchronizeOptions() async {
    if (!optionsStarted.isCompleted) optionsStarted.complete();
    await optionsGate.future;
  }
}
