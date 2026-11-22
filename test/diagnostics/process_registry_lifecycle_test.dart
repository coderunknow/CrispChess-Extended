// Regression test for the managed-process registry lifecycle across benchmark
// runs. The registry is process-global: engines are created all over the app
// (benchmarks, preflight, the game screen), so a run's cleanup must remove
// only the processes *that run* registered. Clearing the whole registry would
// discard registrations owned by other live engines (a concurrent preflight,
// the game screen) and charge a later run their memory.
//
// `BenchmarkService.runWithRunner` snapshots the registered PIDs before the run
// and, in its finally block, calls `removeNotIn(preRunPids)` after the runner
// is disposed. The runner's own engine disposal unregisters the processes it
// watched; `removeNotIn` is the safety net for anything the run registered
// outside the runner's watch — and it deliberately leaves pre-run entries
// (owned by other components) untouched.
@TestOn('vm')
library;

import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/diagnostics/engine_process_registry.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bench_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ManagedProcessRegistry per-run ownership', () {
    test('snapshotPids returns the current registrations', () {
      final registry = ManagedProcessRegistry();
      registry.register(111, label: 'a');
      registry.register(222, label: 'b');
      expect(registry.snapshotPids(), {111, 222});
    });

    test('removeNotIn removes only PIDs not in the baseline', () {
      final registry = ManagedProcessRegistry();
      // Baseline (owned outside this run): 111. The run registers 222.
      registry.register(111, label: 'pre-existing');
      final baseline = registry.snapshotPids();
      registry.register(222, label: 'run-owned');
      expect(registry.contains(222), isTrue);

      registry.removeNotIn(baseline);

      // The run's PID is gone; the pre-existing owner's PID survives.
      expect(registry.contains(222), isFalse);
      expect(registry.contains(111), isTrue);
    });

    test('removeNotIn with an empty baseline clears every entry', () {
      final registry = ManagedProcessRegistry();
      registry.register(1, label: 'a');
      registry.register(2, label: 'b');
      registry.removeNotIn(const {});
      expect(registry.count, isZero);
    });

    test('a run preserves pre-run registrations owned by other engines',
        () async {
      // A process registered by another live component (preflight, the game
      // screen) before this run starts. Per-run ownership means the run must
      // not discard it.
      managedProcessRegistry.clear();
      managedProcessRegistry.register(888888, label: 'other engine');
      expect(managedProcessRegistry.contains(888888), isTrue);

      final service = BenchmarkService(
        store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
        profileStore: EngineProfileStore(),
      );
      await service.runWithRunner(_scriptedRunner());

      // The pre-existing registration survives the run's cleanup.
      expect(managedProcessRegistry.contains(888888), isTrue);
    });

    test('the registry starts clean for a run with no prior registrations',
        () async {
      managedProcessRegistry.clear();
      final service = BenchmarkService(
        store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
        profileStore: EngineProfileStore(),
      );
      await service.runWithRunner(_scriptedRunner());
      expect(managedProcessRegistry.count, isZero);
    });
  });
}

/// A minimal runner over two scripted engines, one short game, so the run
/// completes without real engine processes (and therefore without registering
/// any PIDs of its own).
BenchmarkRunner _scriptedRunner() {
  final identities = [testIdentity('Alpha'), testIdentity('Beta')];
  final plan = buildPlan(
    config: benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 20),
    engines: identities,
  );
  return BenchmarkRunner(
    plan: plan,
    slots: {
      identities[0].engineId:
          BenchEngineSlot(identity: identities[0], build: () => ScriptedEngine('Alpha')),
      identities[1].engineId:
          BenchEngineSlot(identity: identities[1], build: () => ScriptedEngine('Beta')),
    },
    environment: BenchmarkEnvironment.unknown,
  );
}
