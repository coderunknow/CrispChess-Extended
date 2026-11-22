// Regression tests for the Hardware Protection wiring into the benchmark
// runner: the monitor is started with the run's context, a critical decision
// stops the run at a safe game boundary (preserving completed results), a
// high decision pauses after a game, checkpoints fire after every completed
// game, and the monitor is disposed when the run ends.
//
// These lock in the dev7 contract that Hardware Protection only observes and
// pauses/stops at safe boundaries — it never changes engine strength,
// Threads/Hash, engine count or benchmark precision.
import 'dart:async';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/diagnostics/hardware_protection.dart';
import 'package:crispchess/diagnostics/hardware_protection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/bench_harness.dart';

/// A [ResourceProbe] that reports a fixed application footprint so the pressure
/// policy can be driven deterministically in a runner test.
class _FixedProbe implements ResourceProbe {
  _FixedProbe(this.appRssBytes);

  final int? appRssBytes;

  @override
  HardwarePlatform platform() => HardwarePlatform.linux;

  @override
  SystemMemorySample systemMemory() =>
      const SystemMemorySample(totalBytes: 8 * 1024 * 1024 * 1024);

  @override
  ProcessMemorySample process(int pid) => ProcessMemorySample(pid: pid);

  @override
  int? applicationRss() => appRssBytes;

  @override
  Duration? applicationCpu() => Duration.zero;

  @override
  List<int> children(int pid) => const [];

  @override
  Map<int, List<int>> childrenByParent() => const {};

  @override
  String? powerState() => null;

  @override
  String? thermalState() => null;
}

const _mb = 1024 * 1024;

/// A [ResourceProbe] whose application footprint can be changed between
/// samples, so a test can drive a pressure escalation (HIGH → CRITICAL) while
/// the runner is paused.
class _MutableProbe implements ResourceProbe {
  _MutableProbe(this.appRssBytes);

  int? appRssBytes;

  @override
  HardwarePlatform platform() => HardwarePlatform.linux;

  @override
  SystemMemorySample systemMemory() =>
      const SystemMemorySample(totalBytes: 8 * 1024 * 1024 * 1024);

  @override
  ProcessMemorySample process(int pid) => ProcessMemorySample(pid: pid);

  @override
  int? applicationRss() => appRssBytes;

  @override
  Duration? applicationCpu() => Duration.zero;

  @override
  List<int> children(int pid) => const [];

  @override
  Map<int, List<int>> childrenByParent() => const {};

  @override
  String? powerState() => null;

  @override
  String? thermalState() => null;
}

BenchmarkRunner _runner(
  BenchmarkConfig config, {
  HardwareProtectionRuntime? hardware,
  required ScriptedEngine white,
  required ScriptedEngine black,
  Future<void> Function(BenchmarkRun run)? onProgressSave,
  int partialSaveInterval = 1,
}) {
  final identities = [testIdentity('Alpha'), testIdentity('Beta')];
  final plan = buildPlan(config: config, engines: identities);
  return BenchmarkRunner(
    plan: plan,
    slots: {
      identities[0].engineId:
          BenchEngineSlot(identity: identities[0], build: () => white),
      identities[1].engineId:
          BenchEngineSlot(identity: identities[1], build: () => black),
    },
    environment: BenchmarkEnvironment.unknown,
    onProgressSave: onProgressSave,
    hardwareProtection: hardware,
    partialSaveInterval: partialSaveInterval,
  );
}

void main() {
  group('BenchmarkRunner hardware protection wiring', () {
    test('a critical decision stops the run at a game boundary', () async {
      // 960 MB of a 1000 MB absolute budget is above the critical threshold.
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
        ),
        probe: _FixedProbe(960 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 2, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final run = await runner.run();

      // The run stopped because of resource pressure, not a normal completion.
      expect(run.stopReason, 'resource pressure');
      // No game was started: the boundary was honoured before a search began.
      expect(run.games.where((g) => !g.warmUp), isEmpty);
      await runner.dispose();
    });

    test('a critical escalation interrupts a pressure-pause and stops the run',
        () async {
      // Regression: while the runner is pressure-paused, the game loop is
      // blocked in `_awaitResume()`. A HIGH→CRITICAL escalation used to only
      // emit a pressure event and never wake the pause, so the run stayed
      // paused indefinitely and never executed the STOP. A CRITICAL sample must
      // break the pause so the loop's boundary check stops the run.
      //
      // 850 MB of a 1000 MB absolute budget is exactly the high threshold
      // (pauseAfterGame); 950 MB is the critical threshold (stop).
      final probe = _MutableProbe(850 * _mb);
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
          // Keep the monitor's own timer out of the way; the test drives
          // samples explicitly.
          samplingIntervalSeconds: 60,
        ),
        probe: probe,
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 4, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final runFuture = runner.run();

      // Wait until the runner has paused itself at a game boundary.
      final pauseCompleter = Completer<void>();
      final sub = runner.events.listen((event) {
        if (event is BenchmarkPausedEvent && event.pressure) {
          pauseCompleter.complete();
        }
      });
      await pauseCompleter.future;
      expect(runner.isPressurePaused, isTrue);

      // Pressure rises to CRITICAL while the run is paused.
      probe.appRssBytes = 950 * _mb;
      runtime.tick();

      final run = await runFuture;
      expect(run.stopReason, 'resource pressure');

      sub.cancel();
      await runner.dispose();
    });

    test('a critical escalation during a pause stops without starting another game',
        () async {
      // Regression: `_checkPressureBoundary()` is the only place that turns a
      // CRITICAL (stop) decision into a loop break. When a CRITICAL escalation
      // breaks a pressure-pause (via `_breakPauseForStop`) while the loop is
      // blocked in `_awaitResume()`, the loop used to fall straight through to
      // `playBenchGame` and start another game under pressure; only the *next*
      // iteration's top-of-loop check would stop it. The loop must re-check the
      // boundary after the pause wait so no extra game starts.
      //
      // 850 MB of a 1000 MB budget is the high threshold (pauseAfterGame);
      // 950 MB is the critical threshold (stop).
      final probe = _MutableProbe(850 * _mb);
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
          samplingIntervalSeconds: 60,
        ),
        probe: probe,
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 4, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final runFuture = runner.run();

      final pauseCompleter = Completer<void>();
      final startedGames = <int>[];
      final sub = runner.events.listen((event) {
        if (event is BenchmarkPausedEvent && event.pressure) {
          pauseCompleter.complete();
        }
        if (event is BenchmarkGameStartedEvent) {
          startedGames.add(event.gameNumber);
        }
      });

      await pauseCompleter.future;
      expect(runner.isPressurePaused, isTrue);
      final gamesAtPause = List.of(startedGames);

      // Pressure rises to CRITICAL while the run is paused; this breaks the
      // pause. The loop must re-check the boundary and stop, starting no new
      // game.
      probe.appRssBytes = 950 * _mb;
      runtime.tick();

      final run = await runFuture;
      expect(run.stopReason, 'resource pressure');

      // No new game may have started after the pause broke: the re-check after
      // `_awaitResume()` must break the loop before `playBenchGame`.
      expect(startedGames, gamesAtPause,
          reason: 'a CRITICAL escalation that breaks a pause must stop the run '
              'without starting another game under pressure');

      sub.cancel();
      await runner.dispose();
    });

    test('a calm decision lets the run complete normally', () async {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
        ),
        probe: _FixedProbe(100 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 2, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final run = await runner.run();

      expect(run.stopReason, 'completed');
      expect(run.gamesCompleted, greaterThan(0));
      await runner.dispose();
    });

    test('checkpoints fire after every completed game', () async {
      final saved = <BenchmarkRun>[];
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
        ),
        probe: _FixedProbe(100 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 2, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
        onProgressSave: (run) async => saved.add(run),
      );

      final run = await runner.run();

      // The per-game checkpoints are fire-and-forget; let the scheduled
      // writes land before counting them.
      await Future.delayed(const Duration(milliseconds: 20));

      // partialSaveInterval defaults to 1: at least one checkpoint per
      // completed game plus the final save.
      expect(saved.length, greaterThanOrEqualTo(run.gamesCompleted));
      // The final saved document is the finished run.
      expect(saved.last.stopReason, 'completed');
      await runner.dispose();
    });

    test('the checkpoint cadence is honoured, not hardcoded to one', () async {
      // Regression: the runner used to hardcode partialSaveInterval = 1 and
      // BenchmarkService never passed the user's checkpointEveryGame setting,
      // so changing the cadence had no effect. The runner must honour a
      // configured cadence.
      final saved = <BenchmarkRun>[];
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
          checkpointEveryGame: 2,
        ),
        probe: _FixedProbe(100 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 4, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
        onProgressSave: (run) async => saved.add(run),
        partialSaveInterval: 2,
      );

      final run = await runner.run();
      await Future.delayed(const Duration(milliseconds: 20));

      // 4 completed games with a cadence of 2: two mid-run checkpoints (at
      // games 2 and 4) plus the two end-of-run saves (the flush and the
      // finished save) = 4 saves. The hardcoded every-game cadence would
      // produce 4 mid-run checkpoints + 2 end = 6.
      expect(run.gamesCompleted, 4);
      expect(saved.length, 4);
      await runner.dispose();
    });

    test('the monitor is disposed when the run ends', () async {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
        ),
        probe: _FixedProbe(100 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );
      await runner.run();
      // run() disposes the monitor before returning; a second dispose is safe.
      expect(runtime.isRunning, isFalse);
      await runner.dispose();
    });

    test('the hardware protection snapshot is persisted with the run', () async {
      final saved = <BenchmarkRun>[];
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
        ),
        probe: _FixedProbe(100 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
        onProgressSave: (run) async => saved.add(run),
      );

      await runner.run();

      // The final saved document carries the Hardware Protection snapshot,
      // including the full bounded telemetry, so the diagnostic data is not
      // collected and then discarded.
      final finalSave = saved.last;
      expect(finalSave.hardwareProtection, isNotNull);
      expect(finalSave.hardwareProtection!['platform'], 'linux');
      expect(finalSave.hardwareProtection!['level'], 'normal');
      expect(finalSave.hardwareProtection!['telemetry'], isA<Map>());
      expect(
          (finalSave.hardwareProtection!['telemetry'] as Map)['schema'], 1);

      // The snapshot survives a save/load round trip (backward-compatible).
      final loaded = BenchmarkRun.fromJson(finalSave.toJson());
      expect(loaded.hardwareProtection, isNotNull);
      expect(loaded.hardwareProtection!['platform'], 'linux');

      await runner.dispose();
    });

    test('a high-pressure decision pauses the run at a safe boundary', () async {
      // 900 MB of a 1000 MB budget is in the high band (>= 85%). The decision
      // is evaluated at start(), so the boundary check pauses before the first
      // game begins — a search is never cut in half.
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
        ),
        probe: _FixedProbe(900 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final runFuture = runner.run();

      // Poll until the runner reports a pressure pause (bounded, so a
      // regression that stops pausing fails fast rather than hanging).
      final paused = await _waitFor(() => runner.isPressurePaused,
          const Duration(seconds: 5));
      expect(paused, isTrue);

      // Cancelling resumes the run and stops it cleanly; no result is
      // fabricated by the pause.
      runner.cancel();
      final run = await runFuture;
      expect(run.stopReason, 'cancelled');
      await runner.dispose();
    });

    test('a resumed pressure pause does not re-pause at the same level',
        () async {
      // Regression: after a user resumes a HIGH-pressure pause, a decision
      // that persists at the same HIGH level must not pause again immediately.
      // Without the acknowledged-level gate the run would re-pause on the next
      // boundary and strand until pressure happened to clear. Only a strictly
      // higher level re-pauses.
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
        ),
        probe: _FixedProbe(900 * _mb),
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final runFuture = runner.run();

      final paused = await _waitFor(() => runner.isPressurePaused,
          const Duration(seconds: 5));
      expect(paused, isTrue);

      // The user resumes while pressure is still HIGH (the probe is fixed at
      // 900 MB of the 1000 MB budget). The run must continue to completion
      // rather than immediately re-pausing at the same level.
      runner.resume();
      final run = await runFuture;
      expect(run.stopReason, 'completed');
      await runner.dispose();
    });

    test('a pressure drop then rise back re-pauses at the recovered level',
        () async {
      // Regression: the acknowledged level is forgotten when pressure falls
      // below it, so a later rise back to that level is a new event and pauses
      // again. This is the counterpart to the resumability test above: the
      // gate is not a one-way latch. The monitor's tick() is driven directly
      // so the test does not depend on the adaptive timer's (pressure-doubled)
      // cadence.
      final probe = _MutableProbe(900 * _mb);
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
          samplingIntervalSeconds: 1,
        ),
        probe: probe,
      );
      final runner = _runner(
        benchConfig(gamesPerPairing: 1, repetitions: 4, plyCap: 200),
        hardware: runtime,
        white: ScriptedEngine('Alpha'),
        black: ScriptedEngine('Beta'),
      );

      final runFuture = runner.run();

      // HIGH pressure pauses the run.
      final firstPause = await _waitFor(() => runner.isPressurePaused,
          const Duration(seconds: 5));
      expect(firstPause, isTrue);
      runner.resume();

      // Pressure clears below warning; a tick re-evaluates the decision and the
      // level drop forgets the acknowledged HIGH level.
      probe.appRssBytes = 100 * _mb;
      runtime.tick();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Pressure rises back to HIGH: a tick makes it a new pause at the
      // recovered level (the acknowledged gate was reset, not latched).
      probe.appRssBytes = 900 * _mb;
      runtime.tick();
      final rePaused = await _waitFor(() => runner.isPressurePaused,
          const Duration(seconds: 5));
      expect(rePaused, isTrue);

      runner.cancel();
      final run = await runFuture;
      expect(run.stopReason, 'cancelled');
      await runner.dispose();
    });

    test('a mid-run error persists the partial results before propagating',
        () async {
      // If an unexpected error escapes the game loop (a runner-side failure,
      // not an engine move error — `playBenchGame` converts those to forfeits),
      // the run must not be silently discarded: the partial results already
      // collected are checkpointed before the error is rethrown.
      final saved = <BenchmarkRun>[];
      // 900 MB of a 1000 MB budget is in the high band, so the pressure
      // decision is `pauseAfterGame`; `_checkPressureBoundary` calls `pause()`
      // at the first game boundary, where the injected throw escapes.
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 1000,
        ),
        probe: _FixedProbe(900 * _mb),
      );
      final identities = [testIdentity('Alpha'), testIdentity('Beta')];
      final plan = buildPlan(
        config: benchConfig(gamesPerPairing: 1, repetitions: 1, plyCap: 200),
        engines: identities,
      );
      final runner = _ThrowingPauseRunner(
        plan: plan,
        slots: {
          identities[0].engineId:
              BenchEngineSlot(identity: identities[0], build: () => ScriptedEngine('Alpha')),
          identities[1].engineId:
              BenchEngineSlot(identity: identities[1], build: () => ScriptedEngine('Beta')),
        },
        environment: BenchmarkEnvironment.unknown,
        onProgressSave: (run) async => saved.add(run),
        hardwareProtection: runtime,
      );

      await expectLater(
        runner.run(),
        throwsA(isA<StateError>()),
      );

      // The abnormal exit persisted the partial run before rethrowing, so the
      // completed game is not silently discarded.
      expect(saved, isNotEmpty);
      await runner.dispose();
    });
  });
}

/// A [BenchmarkRunner] whose [pause] throws, so a test can drive an error to
/// escape the game loop at a safe boundary (the pressure-pause call site) and
/// prove the runner persists the partial results before propagating it.
class _ThrowingPauseRunner extends BenchmarkRunner {
  _ThrowingPauseRunner({
    required super.plan,
    required super.slots,
    required super.environment,
    super.onProgressSave,
    super.hardwareProtection,
  });

  @override
  void pause() => throw StateError('injected pause failure');
}

/// Awaits [condition] becoming true, returning false on timeout.
Future<bool> _waitFor(bool Function() condition, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return true;
    await Future.delayed(const Duration(milliseconds: 5));
  }
  return condition();
}
