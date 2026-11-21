// Regression tests for the Hardware Protection model, budget resolution,
// pressure evaluation, capability reporting, the process registry, the live
// board throttle and the runtime monitor.
//
// These lock in the dev7 contract:
//  * memory budgets are hybrid (automatic/absolute/percentage) and never claim
//    an OS-enforced cap when the platform cannot enforce one;
//  * pressure evaluation uses separate warning/high/critical thresholds with
//    hysteresis so a hovering reading does not oscillate;
//  * unavailable metrics stay distinct from a genuine zero;
//  * the live board throttle never discards benchmark events;
//  * the monitor never touches engine Threads/Hash/engine count/precision.
import 'dart:async';

import 'package:crispchess/bench/live_board.dart' show LiveBoardThrottle;
import 'package:crispchess/diagnostics/engine_process_registry.dart';
import 'package:crispchess/diagnostics/hardware_protection.dart';
import 'package:crispchess/diagnostics/hardware_protection_service.dart';
import 'package:crispchess/diagnostics/resource_telemetry.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted [ResourceProbe] so the sampling and policy logic can be driven
/// without a device or a real process tree.
class _FakeProbe implements ResourceProbe {
  _FakeProbe({
    this.totalBytes,
    this.availableBytes,
    this.appRssBytes,
    this.engineRssByPid = const <int, int>{},
    this.childPidsByPid = const <int, List<int>>{},
    HardwarePlatform platform = HardwarePlatform.linux,
    String? powerState,
    String? thermalState,
  })
      : _platform = platform,
        _powerState = powerState,
        _thermalState = thermalState;

  HardwarePlatform _platform;
  int? totalBytes;
  int? availableBytes;
  int? appRssBytes;
  Map<int, int> engineRssByPid;
  Map<int, List<int>> childPidsByPid;

  /// Application CPU time reported by [applicationCpu]. Mutable so a test can
  /// drive the CPU-percent path; defaults to zero.
  Duration cpu = Duration.zero;
  String? _powerState;
  String? _thermalState;

  /// Test instrumentation: how many times [childrenByParent] was invoked.
  int childrenByParentCalls = 0;

  @override
  HardwarePlatform platform() => _platform;

  @override
  SystemMemorySample systemMemory() =>
      SystemMemorySample(totalBytes: totalBytes, availableBytes: availableBytes);

  @override
  ProcessMemorySample process(int pid) =>
      ProcessMemorySample(pid: pid, rssBytes: engineRssByPid[pid]);

  @override
  int? applicationRss() => appRssBytes;

  @override
  Duration? applicationCpu() => cpu;

  @override
  List<int> children(int pid) => childPidsByPid[pid] ?? const [];

  @override
  Map<int, List<int>> childrenByParent() {
    childrenByParentCalls++;
    final map = <int, List<int>>{};
    for (final entry in childPidsByPid.entries) {
      (map[entry.key] ??= <int>[]).addAll(entry.value);
    }
    return map;
  }

  @override
  String? powerState() => _powerState;

  @override
  String? thermalState() => _thermalState;
}

void main() {
  group('HardwareProtectionSettings', () {
    test('defaults are sensible and self-consistent', () {
      const settings = HardwareProtectionSettings();
      expect(settings.enabled, isTrue);
      expect(settings.ramBudgetMode, RamBudgetMode.automatic);
      expect(settings.memoryReserveMb, 1024);
      expect(settings.warningRatio, 0.75);
      expect(settings.highRatio, 0.85);
      expect(settings.criticalRatio, 0.95);
      expect(settings.warningHysteresis, 0.05);
      expect(settings.cpuManagementEnabled, isTrue);
      expect(settings.backgroundWorkConcurrency, 2);
      expect(settings.reducedBackgroundConcurrency, 1);
      expect(settings.liveBoardMode, LiveBoardMode.auto);
      expect(settings.liveBoardRefreshPerSecond, 4);
      // The class default must match the persisted default so a fresh instance
      // and a loaded one behave identically.
      expect(settings.samplingIntervalSeconds, 5);
      expect(settings.telemetryEnabled, isTrue);
      expect(settings.checkpointEveryGame, 1);
      expect(settings.validationErrors(), isEmpty);
    });

    test('copyWith changes only the named fields', () {
      const base = HardwareProtectionSettings();
      final updated = base.copyWith(
        absoluteLimitMb: 2048,
        percentageLimit: 70.0,
        liveBoardMode: LiveBoardMode.off,
      );
      expect(updated.absoluteLimitMb, 2048);
      expect(updated.percentageLimit, 70.0);
      expect(updated.liveBoardMode, LiveBoardMode.off);
      // Untouched fields keep their values.
      expect(updated.enabled, base.enabled);
      expect(updated.memoryReserveMb, base.memoryReserveMb);
      expect(updated.warningRatio, base.warningRatio);
      expect(updated.samplingIntervalSeconds, base.samplingIntervalSeconds);
    });

    test('JSON round-trip preserves every field', () {
      const original = HardwareProtectionSettings(
        ramBudgetMode: RamBudgetMode.percentage,
        memoryReserveMb: 512,
        percentageLimit: 60.0,
        warningRatio: 0.7,
        highRatio: 0.8,
        criticalRatio: 0.9,
        liveBoardMode: LiveBoardMode.on,
        liveBoardRefreshPerSecond: 8,
        samplingIntervalSeconds: 10,
        telemetryMaxRecords: 500,
      );
      final json = original.toJson();
      final restored = HardwareProtectionSettings.fromJson(json);
      expect(restored.ramBudgetMode, RamBudgetMode.percentage);
      expect(restored.memoryReserveMb, 512);
      expect(restored.percentageLimit, 60.0);
      expect(restored.warningRatio, 0.7);
      expect(restored.highRatio, 0.8);
      expect(restored.criticalRatio, 0.9);
      expect(restored.liveBoardMode, LiveBoardMode.on);
      expect(restored.liveBoardRefreshPerSecond, 8);
      expect(restored.samplingIntervalSeconds, 10);
      expect(restored.telemetryMaxRecords, 500);
    });

    test('a document written before Hardware Protection existed still loads', () {
      // An empty document must yield the defaults, not a half-configured policy.
      final restored = HardwareProtectionSettings.fromJson(const {});
      expect(restored.enabled, isTrue);
      expect(restored.ramBudgetMode, RamBudgetMode.automatic);
      expect(restored.samplingIntervalSeconds, 5);
      expect(restored.validationErrors(), isEmpty);
    });

    test('validation rejects inverted thresholds and out-of-range values', () {
      final bad = HardwareProtectionSettings(
        warningRatio: 0.9,
        highRatio: 0.8,
        criticalRatio: 0.85,
        samplingIntervalSeconds: 0,
        telemetryMaxRecords: 0,
        checkpointEveryGame: 0,
      );
      final errors = bad.validationErrors();
      expect(errors, isNotEmpty);
      expect(errors, contains('The warning threshold must be below the high threshold.'));
      expect(errors, contains('The sampling interval must be between 1 and 60 seconds.'));
      expect(errors, contains('The telemetry limit must be at least 1.'));
      expect(errors, contains('Checkpointing must run at least once per game.'));
    });

    test('budgetExplanation never claims an OS-enforced cap', () {
      final auto = HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.automatic).budgetExplanation;
      final absolute = HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 1024)
          .budgetExplanation;
      final percentage = HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.percentage, percentageLimit: 50)
          .budgetExplanation;
      for (final text in <String>[auto, absolute, percentage]) {
        expect(text, contains('planning target'));
        expect(text, contains('not an OS-enforced cap'));
      }
    });
  });

  group('resolveMemoryBudget', () {
    test('automatic derives the limit from total memory minus the reserve',
        () {
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(memoryReserveMb: 1024),
        totalBytes: 8 * 1024 * 1024 * 1024,
        availableBytes: 6 * 1024 * 1024 * 1024,
      );
      expect(budget.isUsable, isTrue);
      // The cap is based on *total* memory (stable), not MemAvailable, so the
      // run's own RSS does not shrink its own budget. 8 GiB total minus a 1 GiB
      // reserve = 7 GiB.
      expect(budget.limitBytes, 7 * 1024 * 1024 * 1024);
      expect(budget.source, contains('automatic'));
    });

    test('automatic falls back to total when availability is unavailable', () {
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(memoryReserveMb: 0),
        totalBytes: 4 * 1024 * 1024 * 1024,
        availableBytes: null,
      );
      expect(budget.limitBytes, 4 * 1024 * 1024 * 1024);
    });

    test('automatic stays usable when available memory is a measured zero',
        () {
      // Regression: a measured-zero availableBytes (the OS reports no currently
      // free physical memory) is a valid, critical reading, not an
      // "unavailable" one. It used to hit the `available <= 0` guard and
      // produce an unusable budget, which made evaluatePressure() return
      // NORMAL — disabling the policy at the low-memory edge instead of
      // escalating. With a valid total, the budget must still resolve.
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(memoryReserveMb: 1024),
        totalBytes: 8 * 1024 * 1024 * 1024,
        availableBytes: 0,
      );
      expect(budget.isUsable, isTrue);
      expect(budget.limitBytes, 7 * 1024 * 1024 * 1024);
    });

    test('automatic is unusable when no system memory is reported', () {
      final budget = resolveMemoryBudget(const HardwareProtectionSettings());
      expect(budget.isUsable, isFalse);
      expect(budget.limitBytes, isNull);
    });

    test('absolute uses the configured megabytes', () {
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 2048),
      );
      expect(budget.limitBytes, 2048 * 1024 * 1024);
    });

    test('absolute without a limit is unusable', () {
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(ramBudgetMode: RamBudgetMode.absolute),
      );
      expect(budget.isUsable, isFalse);
    });

    test('percentage is a fraction of total memory, not available memory',
        () {
      // Regression: the percentage used to be taken of *available* memory,
      // which already excludes the run's own RSS, so a 50% limit on free
      // memory was immediately saturated by the run's footprint. It is now a
      // fraction of total physical memory — the consistent quantity the run's
      // RSS is a subset of.
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.percentage, percentageLimit: 50),
        totalBytes: 16 * 1024 * 1024 * 1024,
        availableBytes: 8 * 1024 * 1024 * 1024,
      );
      expect(budget.limitBytes, (16 * 1024 * 1024 * 1024 * 0.5).floor());
    });

    test('percentage falls back to available when total is unavailable',
        () {
      final budget = resolveMemoryBudget(
        const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.percentage, percentageLimit: 50),
        availableBytes: 8 * 1024 * 1024 * 1024,
      );
      expect(budget.limitBytes, (8 * 1024 * 1024 * 1024 * 0.5).floor());
    });

    test('percentage without a usable limit or memory is unusable', () {
      final noLimit = resolveMemoryBudget(
        const HardwareProtectionSettings(ramBudgetMode: RamBudgetMode.percentage));
      expect(noLimit.isUsable, isFalse);
      final noMemory = resolveMemoryBudget(
        const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.percentage, percentageLimit: 50));
      expect(noMemory.isUsable, isFalse);
    });
  });

  group('evaluatePressure', () {
    const mb = 1024 * 1024;

    HardwareProtectionSettings _settings() => const HardwareProtectionSettings(
          warningRatio: 0.75,
          highRatio: 0.85,
          criticalRatio: 0.95,
          warningHysteresis: 0.05,
          highHysteresis: 0.05,
          criticalHysteresis: 0.05,
        );

    MemoryBudget _budget(int limitMb) =>
        MemoryBudget(limitBytes: limitMb * mb, source: 'test');

    ResourceReading _reading(int totalMb) =>
        ResourceReading(
          timestamp: DateTime.now(),
          totalRssBytes: totalMb * mb,
        );

    test('a reading below the warning threshold is calm', () {
      final decision = evaluatePressure(
        _reading(500), _budget(1000), _settings());
      expect(decision.level, ResourcePressureLevel.normal);
      expect(decision.action, PressureAction.none);
    });

    test('crossing the warning threshold raises warning and reduces background',
        () {
      final decision = evaluatePressure(
        _reading(800), _budget(1000), _settings());
      expect(decision.level, ResourcePressureLevel.warning);
      expect(decision.action, PressureAction.reduceBackground);
    });

    test('crossing the high threshold pauses after the game', () {
      final decision = evaluatePressure(
        _reading(900), _budget(1000), _settings());
      expect(decision.level, ResourcePressureLevel.high);
      expect(decision.action, PressureAction.pauseAfterGame);
    });

    test('crossing the critical threshold stops at a safe boundary', () {
      final decision = evaluatePressure(
        _reading(960), _budget(1000), _settings());
      expect(decision.level, ResourcePressureLevel.critical);
      expect(decision.action, PressureAction.stop);
    });

    test('hysteresis keeps a hovering reading from oscillating', () {
      // At 94% we are in the high band (>= 85%). Staying high requires the
      // reading not to fall below highAt * (1 - hysteresis) = 80.75%.
      final highDecision = evaluatePressure(
        _reading(940), _budget(1000), _settings(),
        previous: ResourcePressureLevel.high);
      expect(highDecision.level, ResourcePressureLevel.high);

      // Falling to 81% is still above the hysteresis band, so we stay high
      // rather than dropping straight to warning.
      final stillHigh = evaluatePressure(
        _reading(810), _budget(1000), _settings(),
        previous: ResourcePressureLevel.high);
      expect(stillHigh.level, ResourcePressureLevel.high);

      // Falling to 79% is below the band, so we drop to warning.
      final drops = evaluatePressure(
        _reading(790), _budget(1000), _settings(),
        previous: ResourcePressureLevel.high);
      expect(drops.level, ResourcePressureLevel.warning);
    });

    test('critical only clears once usage falls clearly below the band', () {
      // criticalAt = 950 MB; hysteresis band bottom = 950 * 0.95 = 902.5 MB.
      // 940 MB is above the exit band, so critical is held (not cleared).
      final at940 = evaluatePressure(
        _reading(940), _budget(1000), _settings(),
        previous: ResourcePressureLevel.critical);
      expect(at940.level, ResourcePressureLevel.critical);

      // 900 MB is below the exit band, so critical clears to high.
      final at900 = evaluatePressure(
        _reading(900), _budget(1000), _settings(),
        previous: ResourcePressureLevel.critical);
      expect(at900.level, ResourcePressureLevel.high);
    });

    test('a reading in the hysteresis band stays at the previous level', () {
      // This is the regression test for the oscillation bug: a reading that is
      // above the exit threshold but below the entry threshold, with the
      // previous level still active, must *stay* at that level rather than
      // dropping to the next lower one.
      //
      // High band: entry 850 MB, exit 807.5 MB. 830 MB is in the band.
      final highStays = evaluatePressure(
        _reading(830), _budget(1000), _settings(),
        previous: ResourcePressureLevel.high);
      expect(highStays.level, ResourcePressureLevel.high);
      expect(highStays.action, PressureAction.pauseAfterGame);

      // Critical band: entry 950 MB, exit 902.5 MB. 930 MB is in the band.
      final criticalStays = evaluatePressure(
        _reading(930), _budget(1000), _settings(),
        previous: ResourcePressureLevel.critical);
      expect(criticalStays.level, ResourcePressureLevel.critical);
      expect(criticalStays.action, PressureAction.stop);

      // Warning band: entry 750 MB, exit 712.5 MB. 730 MB is in the band.
      final warningStays = evaluatePressure(
        _reading(730), _budget(1000), _settings(),
        previous: ResourcePressureLevel.warning);
      expect(warningStays.level, ResourcePressureLevel.warning);
      expect(warningStays.action, PressureAction.reduceBackground);
    });

    test('disabled protection is always calm', () {
      final decision = evaluatePressure(
        _reading(990), _budget(1000),
        const HardwareProtectionSettings(enabled: false));
      expect(decision.level, ResourcePressureLevel.normal);
      expect(decision.action, PressureAction.none);
    });

    test('an unavailable reading is calm, not a false critical', () {
      final decision = evaluatePressure(
        ResourceReading(timestamp: DateTime.now(), totalRssBytes: null),
        _budget(1000), _settings());
      expect(decision.level, ResourcePressureLevel.normal);
      expect(decision.action, PressureAction.none);
      expect(decision.reason, contains('No usable memory reading'));
    });

    test('an unusable budget is calm', () {
      final decision = evaluatePressure(
        _reading(990), const MemoryBudget(source: 'none'), _settings());
      expect(decision.level, ResourcePressureLevel.normal);
      expect(decision.action, PressureAction.none);
    });
  });

  group('hardwareCapabilitiesFor', () {
    test('web reports every capability as unavailable (no fabricated parity)',
        () {
      final caps = hardwareCapabilitiesFor(HardwarePlatform.web);
      expect(caps.applicationMemory, CapabilityLevel.unavailable);
      expect(caps.engineProcessMemory, CapabilityLevel.unavailable);
      expect(caps.processTreeMemory, CapabilityLevel.unavailable);
      expect(caps.availableSystemMemory, CapabilityLevel.unavailable);
      expect(caps.cpuManagement, CapabilityLevel.unavailable);
      expect(caps.engineProcessControl, CapabilityLevel.unavailable);
    });

    test('desktop platforms can read their own memory and control engines', () {
      for (final platform in <HardwarePlatform>[
        HardwarePlatform.windows,
        HardwarePlatform.linux,
        HardwarePlatform.macos,
      ]) {
        final caps = hardwareCapabilitiesFor(platform);
        expect(caps.applicationMemory, CapabilityLevel.fullySupported);
        expect(caps.engineProcessControl, CapabilityLevel.fullySupported);
        // Regression: cpuManagement was reported as partiallySupported, but no
        // nonessential-work worker pool enforces the concurrency recommendation,
        // so the honest level is monitoringOnly (sample + advisory, no
        // enforcement).
        expect(caps.cpuManagement, CapabilityLevel.monitoringOnly);
      }
    });

    test('the capability matrix matches what the seam actually reads', () {
      // Regression: the matrix must not claim a capability the resource seam
      // returns no data for, or the UI presents a control as working when it
      // cannot read anything. Linux is the only host that reads system memory,
      // the process tree, CPU time, power and thermal state; macOS reads
      // process and system memory but enumerates no tree; Windows reads its
      // own application memory and system memory (via Win32 GlobalMemoryStatusEx)
      // but no other process's memory (that needs FFI).
      final linux = hardwareCapabilitiesFor(HardwarePlatform.linux);
      expect(linux.engineProcessMemory, CapabilityLevel.fullySupported);
      expect(linux.processTreeMemory, CapabilityLevel.partiallySupported);
      expect(linux.availableSystemMemory, CapabilityLevel.fullySupported);
      expect(linux.thermalMonitoring, CapabilityLevel.monitoringOnly);
      expect(linux.batteryMonitoring, CapabilityLevel.partiallySupported);

      final macos = hardwareCapabilitiesFor(HardwarePlatform.macos);
      expect(macos.engineProcessMemory, CapabilityLevel.fullySupported);
      expect(macos.processTreeMemory, CapabilityLevel.unavailable);
      expect(macos.availableSystemMemory, CapabilityLevel.partiallySupported);
      expect(macos.thermalMonitoring, CapabilityLevel.unavailable);
      expect(macos.batteryMonitoring, CapabilityLevel.unavailable);

      final windows = hardwareCapabilitiesFor(HardwarePlatform.windows);
      expect(windows.engineProcessMemory, CapabilityLevel.unavailable);
      expect(windows.processTreeMemory, CapabilityLevel.unavailable);
      expect(windows.availableSystemMemory, CapabilityLevel.fullySupported);
      expect(windows.thermalMonitoring, CapabilityLevel.unavailable);
      expect(windows.batteryMonitoring, CapabilityLevel.unavailable);

      // Mobile cannot inspect arbitrary host processes or system memory.
      for (final platform in <HardwarePlatform>[
        HardwarePlatform.android,
        HardwarePlatform.ios,
      ]) {
        final caps = hardwareCapabilitiesFor(platform);
        expect(caps.engineProcessMemory, CapabilityLevel.unavailable);
        expect(caps.processTreeMemory, CapabilityLevel.unavailable);
        expect(caps.availableSystemMemory, CapabilityLevel.unavailable);
        expect(caps.thermalMonitoring, CapabilityLevel.unavailable);
        expect(caps.batteryMonitoring, CapabilityLevel.unavailable);
      }
    });

    test('mobile platforms cannot inspect arbitrary host processes', () {
      final android = hardwareCapabilitiesFor(HardwarePlatform.android);
      expect(android.processTreeMemory, CapabilityLevel.unavailable);
      expect(android.engineProcessControl, CapabilityLevel.unavailable);
      final ios = hardwareCapabilitiesFor(HardwarePlatform.ios);
      expect(ios.engineProcessMemory, CapabilityLevel.unavailable);
      expect(ios.engineProcessControl, CapabilityLevel.unavailable);
    });

    test('the capability set round-trips through JSON', () {
      final caps = hardwareCapabilitiesFor(HardwarePlatform.linux);
      final restored = HardwareCapabilitySet.fromJson(caps.toJson());
      expect(restored.applicationMemory, caps.applicationMemory);
      expect(restored.processTreeMemory, caps.processTreeMemory);
      expect(restored.engineProcessControl, caps.engineProcessControl);
    });
  });

  group('ManagedProcessRegistry', () {
    test('register, contains and unregister behave correctly', () {
      final registry = ManagedProcessRegistry();
      expect(registry.contains(42), isFalse);
      registry.register(42, label: 'stockfish');
      expect(registry.contains(42), isTrue);
      expect(registry.count, 1);
      registry.unregister(42);
      expect(registry.contains(42), isFalse);
      // Unregistering an unknown pid is idempotent, not an error.
      registry.unregister(999);
      expect(registry.count, 0);
    });

    test('re-registering a pid refreshes the label, not the entry', () {
      final registry = ManagedProcessRegistry();
      registry.register(7, label: 'first');
      registry.register(7, label: 'second');
      expect(registry.count, 1);
      expect(registry.entries.single.label, 'second');
    });

    test('snapshotJson describes the managed set', () {
      final registry = ManagedProcessRegistry();
      registry.register(1, label: 'a');
      registry.register(2, label: 'b');
      final json = registry.snapshotJson();
      expect(json['count'], 2);
      expect((json['processes'] as List).length, 2);
    });
  });

  group('LiveBoardThrottle', () {
    test('off mode never renders but still keeps the latest move', () {
      final throttle = LiveBoardThrottle(
          mode: LiveBoardMode.off, refreshPerSecond: 10);
      expect(throttle.onMove(fen: 'fen1', san: 'e4'), isFalse);
      expect(throttle.onMove(fen: 'fen2', san: 'e5'), isFalse);
      // The move was recorded, not discarded.
      expect(throttle.lastFen, 'fen2');
      expect(throttle.lastSan, 'e5');
      expect(throttle.pendingMoves, 2);
      expect(throttle.isEnabled, isFalse);
    });

    test('on mode renders immediately then throttles', () {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final throttle = LiveBoardThrottle(
          mode: LiveBoardMode.on,
          refreshPerSecond: 2,
          clock: () => now);
      // First move renders.
      expect(throttle.onMove(fen: 'f1', san: 'a'), isTrue);
      // Immediate second move is throttled (interval is 500 ms at 2/s).
      expect(throttle.onMove(fen: 'f2', san: 'b'), isFalse);
      expect(throttle.pendingMoves, 1);
      // Advance past the interval: the next move renders.
      now = now.add(const Duration(milliseconds: 600));
      expect(throttle.onMove(fen: 'f3', san: 'c'), isTrue);
    });

    test('auto mode slows under warning pressure and restores when calm', () {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final throttle = LiveBoardThrottle(
          mode: LiveBoardMode.auto,
          refreshPerSecond: 10,
          clock: () => now);
      // Normal: 100 ms interval.
      expect(throttle.onMove(fen: 'a', san: '1'), isTrue);
      now = now.add(const Duration(milliseconds: 110));
      expect(throttle.onMove(fen: 'b', san: '2'), isTrue);

      throttle.pressureLevel = ResourcePressureLevel.warning;
      // Under warning the interval doubles (200 ms at 10/s).
      now = now.add(const Duration(milliseconds: 110));
      expect(throttle.onMove(fen: 'c', san: '3'), isFalse);
      now = now.add(const Duration(milliseconds: 110));
      expect(throttle.onMove(fen: 'd', san: '4'), isTrue);

      // Pressure clears: the fast interval is restored.
      throttle.pressureLevel = ResourcePressureLevel.normal;
      now = now.add(const Duration(milliseconds: 110));
      expect(throttle.onMove(fen: 'e', san: '5'), isTrue);
    });

    test('poke forces the next move to render; reset clears pending state', () {
      var now = DateTime(2026, 1, 1, 0, 0, 0);
      final throttle = LiveBoardThrottle(
          mode: LiveBoardMode.on, refreshPerSecond: 1, clock: () => now);
      expect(throttle.onMove(fen: 'a', san: '1'), isTrue);
      expect(throttle.onMove(fen: 'b', san: '2'), isFalse);
      // Poke forces a render on the next move regardless of the interval.
      throttle.poke();
      expect(throttle.onMove(fen: 'c', san: '3'), isTrue);
      // Reset forgets the position and the pending count.
      throttle.reset();
      expect(throttle.pendingMoves, 0);
      expect(throttle.lastFen, isNull);
    });
  });

  group('HardwareProtectionRuntime', () {
    test('tick produces a reading and a decision without a timer', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 1000),
        probe: _FakeProbe(
          totalBytes: 4 * 1024 * 1024 * 1024,
          availableBytes: 3 * 1024 * 1024 * 1024,
          appRssBytes: 200 * 1024 * 1024,
        ),
      );
      runtime.tick();
      final reading = runtime.lastReading!;
      expect(reading.appRssBytes, 200 * 1024 * 1024);
      expect(reading.engineRssBytes, isNull);
      // 200 MB of a 1000 MB budget is below the warning threshold.
      expect(runtime.level, ResourcePressureLevel.normal);
      expect(runtime.budget.limitBytes, 1000 * 1024 * 1024);
    });

    test('engine process memory is summed without double counting children',
        () {
      final registry = ManagedProcessRegistry();
      registry.register(10, label: 'engine-a');
      registry.register(20, label: 'engine-b');
      // 10 has a child 11; the child is counted once.
      final probe = _FakeProbe(
        appRssBytes: 100 * 1024 * 1024,
        engineRssByPid: {
          10: 300 * 1024 * 1024,
          11: 100 * 1024 * 1024,
          20: 200 * 1024 * 1024,
        },
        childPidsByPid: {10: [11]},
      );
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 10000),
        probe: probe,
        registry: registry,
      );
      runtime.tick();
      final reading = runtime.lastReading!;
      // 300 + 100 + 200 = 600 MB of engine memory.
      expect(reading.engineRssBytes, 600 * 1024 * 1024);
      // Total = app (100) + engines (600) = 700 MB.
      expect(reading.totalRssBytes, 700 * 1024 * 1024);
      expect(reading.engineProcessCount, 2);
    });

    test('the process tree is enumerated once per sample, not once per engine',
        () {
      // Regression: enumerating the process tree per managed engine made the
      // sampling cost scale with the number of resident engines (a full
      // /proc listing per engine). The monitor must enumerate once per sample
      // and look each engine's children up from that single pass.
      final registry = ManagedProcessRegistry();
      registry.register(10, label: 'engine-a');
      registry.register(20, label: 'engine-b');
      registry.register(30, label: 'engine-c');
      final probe = _FakeProbe(
        appRssBytes: 100 * 1024 * 1024,
        engineRssByPid: {
          10: 100 * 1024 * 1024,
          11: 50 * 1024 * 1024,
          20: 200 * 1024 * 1024,
          30: 300 * 1024 * 1024,
        },
        childPidsByPid: {10: [11]},
      );
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 10000),
        probe: probe,
        registry: registry,
      );

      runtime.tick();
      final reading = runtime.lastReading!;
      // All three engines plus the child are still summed correctly.
      expect(reading.engineRssBytes, 650 * 1024 * 1024);
      // One enumeration for this sample, regardless of engine count.
      expect(probe.childrenByParentCalls, 1);

      runtime.tick();
      expect(probe.childrenByParentCalls, 2);
    });

    test('an unmeasurable engine process leaves the figure unavailable, not zero',
        () {
      final registry = ManagedProcessRegistry();
      registry.register(10, label: 'engine-a');
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 10000),
        probe: _FakeProbe(appRssBytes: 100 * 1024 * 1024),
        registry: registry,
      );
      runtime.tick();
      final reading = runtime.lastReading!;
      expect(reading.engineRssBytes, isNull);
      // The total still uses the application figure, so it is available.
      expect(reading.totalRssBytes, 100 * 1024 * 1024);
    });

    test('a critical reading stops and is recorded as a pressure event', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 1000),
        probe: _FakeProbe(appRssBytes: 960 * 1024 * 1024),
      );
      runtime.tick();
      expect(runtime.level, ResourcePressureLevel.critical);
      expect(runtime.decision.action, PressureAction.stop);
      expect(runtime.pressureEvents, isNotEmpty);
      expect(runtime.pressureEvents.single.level,
          ResourcePressureLevel.critical);
    });

    test('telemetry is recorded, bounded and distinguishes unavailable from zero',
        () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute,
            absoluteLimitMb: 1000,
            telemetryMaxRecords: 2),
        probe: _FakeProbe(appRssBytes: 100 * 1024 * 1024),
      );
      runtime.tick();
      runtime.tick();
      runtime.tick();
      // Bounded to the configured maximum.
      expect(runtime.telemetry.count, 2);
      // A record with an unavailable engine figure keeps it null, not 0.
      final record = runtime.telemetry.records.first;
      expect(record.engineRssBytes, isNull);
      expect(record.appRssBytes, 100 * 1024 * 1024);
    });

    test('background concurrency and board rate react to pressure, not engines',
        () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute,
            absoluteLimitMb: 1000,
            backgroundWorkConcurrency: 4,
            reducedBackgroundConcurrency: 1,
            liveBoardMode: LiveBoardMode.auto,
            liveBoardRefreshPerSecond: 8),
        probe: _FakeProbe(appRssBytes: 100 * 1024 * 1024),
      );
      // Calm: full background concurrency and the full board rate.
      runtime.tick();
      expect(runtime.backgroundConcurrency(), 4);
      expect(runtime.recommendedBoardRefreshPerSecond(), 8);
    });

    test('a critical reading reduces background work and halves the board rate',
        () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute,
            absoluteLimitMb: 1000,
            backgroundWorkConcurrency: 4,
            reducedBackgroundConcurrency: 1,
            liveBoardMode: LiveBoardMode.auto,
            liveBoardRefreshPerSecond: 8),
        probe: _FakeProbe(appRssBytes: 960 * 1024 * 1024),
      );
      runtime.tick();
      expect(runtime.level, ResourcePressureLevel.critical);
      expect(runtime.backgroundConcurrency(), 1);
      expect(runtime.recommendedBoardRefreshPerSecond(), 4);
    });

    test('board rate is zero when the board is off and untouched when on', () {
      final off = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute,
            absoluteLimitMb: 10000,
            liveBoardMode: LiveBoardMode.off,
            liveBoardRefreshPerSecond: 8),
        probe: _FakeProbe(appRssBytes: 100 * 1024 * 1024),
      );
      off.tick();
      expect(off.recommendedBoardRefreshPerSecond(), 0);

      final on = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute,
            absoluteLimitMb: 10000,
            liveBoardMode: LiveBoardMode.on,
            liveBoardRefreshPerSecond: 6),
        probe: _FakeProbe(appRssBytes: 960 * 1024 * 1024),
      );
      on.tick();
      // In `on` mode the configured rate is honoured even under pressure.
      expect(on.recommendedBoardRefreshPerSecond(), 6);
    });

    test('the sampling rate adapts when pressure rises', () {
      // Regression: the monitor was driven by `Timer.periodic(interval)`,
      // which captures the interval once at creation. Raising the pressure
      // level (and therefore the intended rate) later had no effect. The
      // timer must re-read the effective interval on every cycle so the
      // adaptive slowdown actually takes effect.
      final probe = _FakeProbe(appRssBytes: 100 * 1024 * 1024);
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
          ramBudgetMode: RamBudgetMode.absolute,
          absoluteLimitMb: 10000,
          samplingIntervalSeconds: 1,
        ),
        probe: probe,
      );
      final samples = <HardwarePressureSample>[];
      StreamSubscription<HardwarePressureSample>? subscription;
      FakeAsync().run((fakeAsync) {
        subscription = runtime.samples.listen((s) => samples.add(s));

        runtime.start(
          selectedEngineCount: 0,
          benchmarkMode: 'test',
          threads: 1,
          hashMb: 1,
        );
        // start() samples once immediately, at the base rate. The samples
        // stream is an async broadcast controller, so the immediate event is
        // queued on the microtask queue and must be flushed before it is
        // observed by the listener.
        fakeAsync.flushMicrotasks();
        expect(samples.length, 1);
        expect(runtime.interval, const Duration(seconds: 1));

        // Normal pressure: the next tick lands one base interval later.
        fakeAsync.elapse(const Duration(seconds: 1));
        expect(samples.length, 2);

        // The probe now reports critical pressure (9600 MB of a 10000 MB
        // budget is 96%, past the 95% critical threshold). The tick already
        // scheduled (at the base rate) fires and evaluates it; from then on
        // the rate doubles.
        probe.appRssBytes = 9600 * 1024 * 1024;
        fakeAsync.elapse(const Duration(seconds: 1));
        expect(samples.length, 3);
        expect(runtime.level, ResourcePressureLevel.critical);
        expect(runtime.interval, const Duration(seconds: 2));

        // One base interval later there is NO tick: the next one is scheduled
        // at the doubled (adaptive) interval. Under the old fixed-period
        // timer this would have fired.
        fakeAsync.elapse(const Duration(seconds: 1));
        expect(samples.length, 3);

        // And it does fire after the doubled interval elapses.
        fakeAsync.elapse(const Duration(seconds: 1));
        expect(samples.length, 4);
      });
      subscription?.cancel();
      runtime.stop();
    });

    test('a user decision is recorded against the telemetry', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 1000),
        probe: _FakeProbe(appRssBytes: 960 * 1024 * 1024),
      );
      runtime.tick();
      runtime.recordUserDecision(PressureUserDecision.continueAnyway);
      final last = runtime.telemetry.records.last;
      expect(last.userDecision, PressureUserDecision.continueAnyway);
    });

    test('dispose stops monitoring and closes the stream', () async {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(),
        probe: _FakeProbe(),
      );
      runtime.start(
        selectedEngineCount: 2,
        benchmarkMode: 'manual',
        threads: 4,
        hashMb: 256,
      );
      expect(runtime.isRunning, isTrue);
      await runtime.dispose();
      expect(runtime.isRunning, isFalse);
    });

    test('snapshotJson summarises the run for the diagnostic report', () async {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(
            ramBudgetMode: RamBudgetMode.absolute, absoluteLimitMb: 1000),
        probe: _FakeProbe(
            appRssBytes: 960 * 1024 * 1024,
            thermalState: 'nominal',
            powerState: 'on-battery'),
      );
      runtime.start(
        selectedEngineCount: 3,
        benchmarkMode: 'intelligent',
        threads: 8,
        hashMb: 512,
      );
      final json = runtime.snapshotJson();
      expect(json['platform'], 'linux');
      expect(json['level'], 'critical');
      expect(json['threads'], 8);
      expect(json['hashMb'], 512);
      expect(json['telemetry']['schema'], 1);
      expect(json['capabilities'], isA<Map>());
      await runtime.dispose();
    });
  });

  group('ResourceTelemetryLog', () {
    test('is bounded and keeps the newest records', () {
      final log = ResourceTelemetryLog(maxRecords: 3);
      for (var i = 0; i < 5; i++) {
        log.add(ResourceTelemetryRecord(
          timestamp: DateTime.now().add(Duration(seconds: i)),
          engineProcessCount: i,
          engineLifecycleState: 'running',
          selectedEngineCount: 1,
          benchmarkMode: 'manual',
          elapsedSeconds: i.toDouble(),
          threads: 1,
          hashMb: 16,
          pressureLevel: ResourcePressureLevel.normal,
        ));
      }
      expect(log.count, 3);
      // The newest records survive.
      expect(log.records.last.engineProcessCount, 4);
    });

    test('peakTotalBytes tracks the largest total footprint', () {
      final log = ResourceTelemetryLog();
      log.add(ResourceTelemetryRecord(
        timestamp: DateTime.now(),
        totalRssBytes: 100,
        engineProcessCount: 0,
        engineLifecycleState: 'running',
        selectedEngineCount: 0,
        benchmarkMode: 'manual',
        elapsedSeconds: 0,
        threads: 1,
        hashMb: 16,
        pressureLevel: ResourcePressureLevel.normal,
      ));
      log.add(ResourceTelemetryRecord(
        timestamp: DateTime.now(),
        totalRssBytes: 300,
        engineProcessCount: 0,
        engineLifecycleState: 'running',
        selectedEngineCount: 0,
        benchmarkMode: 'manual',
        elapsedSeconds: 0,
        threads: 1,
        hashMb: 16,
        pressureLevel: ResourcePressureLevel.normal,
      ));
      expect(log.peakTotalBytes, 300);
    });

    test('a missing or older document yields an empty log, not an error', () {
      final empty = ResourceTelemetryLog.fromJson(const {});
      expect(empty.count, 0);
      final legacy = ResourceTelemetryLog.fromJson(
          {'records': const [{'engineProcessCount': 1}]});
      // A record missing its timestamp is skipped rather than crashing.
      expect(legacy.count, 0);
    });

    test('CSV output is additive and readable', () {
      final log = ResourceTelemetryLog();
      log.add(ResourceTelemetryRecord(
        timestamp: DateTime.utc(2026, 1, 1),
        totalRssBytes: 123,
        engineProcessCount: 2,
        engineLifecycleState: 'running',
        selectedEngineCount: 2,
        benchmarkMode: 'manual',
        elapsedSeconds: 1.5,
        threads: 4,
        hashMb: 256,
        pressureLevel: ResourcePressureLevel.warning,
        mitigation: PressureAction.reduceBackground,
      ));
      final csv = log.toCsv();
      expect(csv, contains('timestamp_utc,'));
      expect(csv, contains('warning'));
      expect(csv, contains('reduceBackground'));
    });
  });
}
