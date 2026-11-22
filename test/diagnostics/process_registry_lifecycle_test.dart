// Regression test for the managed-process registry lifecycle across benchmark
// runs. The registry is process-global: a PID registered outside the runner's
// watch (or one whose handle was lost) would otherwise survive into the next
// run and be charged to it as an engine. `BenchmarkService.runWithRunner`'s
// finally block clears the registry after the runner is disposed, so a fresh
// run never inherits the previous run's process set.
//
// The runner's own engine disposal unregisters the processes it watched; the
// `clear()` is the safety net for everything else. This test registers a PID
// that no engine will unregister and proves it is gone after a run.
@TestOn('vm')
library;

import 'package:crispchess/bench/benchmark_environment.dart';
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

  group('ManagedProcessRegistry lifecycle across runs', () {
    test('a run clears process-global registrations left by the previous run',
        () async {
      final service = BenchmarkService(
        store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
        profileStore: EngineProfileStore(),
      );

      // Simulate a process registered outside the runner's watch — for example
      // a helper that was registered but whose handle was never released. It
      // is still in the process-global registry when the next run starts.
      managedProcessRegistry.register(999999, label: 'stale helper');
      expect(managedProcessRegistry.contains(999999), isTrue);

      final run = await service.runWithRunner(_scriptedRunner());
      expect(run.games, isNotEmpty);

      // The run's finally block cleared the registry: the stale PID did not
      // survive into the next run, so a fresh run cannot charge it as an engine.
      expect(managedProcessRegistry.contains(999999), isFalse);
      expect(managedProcessRegistry.count, isZero);
    });

    test('the registry starts empty for a run with no prior registrations',
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
