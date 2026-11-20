/// The running Hardware Protection monitor.
///
/// One instance per benchmark run. It samples the application process, the
/// managed engine processes (and, where the platform exposes it, their
/// children) at a low, adaptive rate; derives a memory budget from live system
/// memory; evaluates the pressure policy with hysteresis; and exposes the
/// resulting level, action and budget to the benchmark runner and the UI.
///
/// What it deliberately does *not* do: change an engine's `Threads` or `Hash`,
/// change the engine count, reduce the benchmark workload, or alter statistical
/// precision. Under pressure it slows its own sampling and reports the
/// recommended background concurrency; the only actions that touch a run are
/// `pauseAfterGame` and `stop`, which stop at a game boundary and preserve the
/// results already collected.
library;

import 'dart:async';
import 'dart:math' as math;

import 'engine_process_registry.dart' show ManagedProcessRegistry, managedProcessRegistry;
import 'hardware_protection.dart' show
    HardwareCapabilitySet,
    HardwareProtectionSettings,
    HardwarePlatform,
    LiveBoardMode,
    MemoryBudget,
    PressureAction,
    PressureDecision,
    PressureEventRecord,
    PressureUserDecision,
    ResourcePressureLevel,
    ResourceProbe,
    ResourceReading,
    SystemMemorySample,
    ProcessMemorySample,
    evaluatePressure,
    hardwareCapabilitiesFor,
    resolveMemoryBudget;
import 'process_memory.dart';
import 'resource_telemetry.dart' show ResourceTelemetryLog, ResourceTelemetryRecord;

/// The [ResourceProbe] backed by the platform resource seam.
class PlatformResourceProbe implements ResourceProbe {
  const PlatformResourceProbe();

  @override
  HardwarePlatform platform() => hardwarePlatform();

  @override
  SystemMemorySample systemMemory() => readSystemMemory();

  @override
  ProcessMemorySample process(int pid) => readProcessMemory(pid);

  @override
  int? applicationRss() => applicationRss();

  @override
  Duration applicationCpu() => readApplicationCpu();

  @override
  List<int> children(int pid) => childPidsOf(pid);

  @override
  Map<int, List<int>> childrenByParent() => allChildrenByParent();

  @override
  String? powerState() => readPowerState();

  @override
  String? thermalState() => readThermalState();
}

/// One sample plus the decision the policy made about it.
class HardwarePressureSample {
  final ResourceReading reading;
  final PressureDecision decision;

  const HardwarePressureSample({
    required this.reading,
    required this.decision,
  });
}

/// Context the runtime needs to describe a run in its telemetry.
class HardwareProtectionContext {
  final int selectedEngineCount;
  final String benchmarkMode;
  final int threads;
  final int hashMb;
  final String engineLifecycleState;

  const HardwareProtectionContext({
    required this.selectedEngineCount,
    required this.benchmarkMode,
    required this.threads,
    required this.hashMb,
    this.engineLifecycleState = 'running',
  });
}

/// The Hardware Protection monitor for one benchmark run.
class HardwareProtectionRuntime {
  final HardwareProtectionSettings settings;
  final ResourceProbe probe;
  final ManagedProcessRegistry registry;
  final ResourceTelemetryLog telemetry;

  HardwareProtectionRuntime({
    required this.settings,
    ResourceProbe? probe,
    ManagedProcessRegistry? registry,
    ResourceTelemetryLog? telemetry,
  })  : probe = probe ?? const PlatformResourceProbe(),
        registry = registry ?? managedProcessRegistry,
        telemetry = telemetry ?? ResourceTelemetryLog(
              maxRecords: settings.telemetryMaxRecords,
            );

  final StreamController<HardwarePressureSample> _samples =
      StreamController<HardwarePressureSample>.broadcast();
  final List<PressureEventRecord> _pressureEvents = [];

  Timer? _timer;
  ResourceReading? _lastReading;
  PressureDecision _lastDecision = const PressureDecision(
    level: ResourcePressureLevel.normal,
    action: PressureAction.none,
    reason: 'not started',
    budget: MemoryBudget(source: 'none'),
  );
  MemoryBudget _budget = const MemoryBudget(source: 'none');
  HardwareProtectionContext _context = const HardwareProtectionContext(
    selectedEngineCount: 0,
    benchmarkMode: 'unknown',
    threads: 0,
    hashMb: 0,
  );

  Duration? _lastCpu;
  DateTime? _lastCpuAt;
  double? _cpuPercent;

  int _elapsedTicks = 0;

  /// The platform capability matrix, computed once.
  HardwareCapabilitySet get capabilities =>
      hardwareCapabilitiesFor(probe.platform());

  Stream<HardwarePressureSample> get samples => _samples.stream;

  ResourceReading? get lastReading => _lastReading;
  PressureDecision get decision => _lastDecision;
  ResourcePressureLevel get level => _lastDecision.level;
  MemoryBudget get budget => _budget;
  double? get cpuPercent => _cpuPercent;
  List<PressureEventRecord> get pressureEvents =>
      List.unmodifiable(_pressureEvents);

  bool get isRunning => _timer != null;

  /// The effective sampling interval. Under warning or worse pressure the
  /// monitor slows its own nonessential sampling; this is adaptive scheduling
  /// of background work, not a change to the benchmark.
  Duration get interval {
    final base = Duration(seconds: settings.samplingIntervalSeconds);
    if (!settings.enabled || level == ResourcePressureLevel.normal) return base;
    // One slowdown step under pressure, capped so the monitor stays useful.
    return Duration(seconds: math.min(base.inSeconds * 2, 30));
  }

  /// Starts monitoring for a run.
  void start({
    required int selectedEngineCount,
    required String benchmarkMode,
    required int threads,
    required int hashMb,
    String engineLifecycleState = 'running',
  }) {
    _context = HardwareProtectionContext(
      selectedEngineCount: selectedEngineCount,
      benchmarkMode: benchmarkMode,
      threads: threads,
      hashMb: hashMb,
      engineLifecycleState: engineLifecycleState,
    );
    _lastCpu = null;
    _lastCpuAt = null;
    _cpuPercent = null;
    _elapsedTicks = 0;
    _runStartedAt = DateTime.now();
    _timer?.cancel();
    if (!settings.enabled) return;
    // Sample once immediately, then keep the monitor alive with a timer that
    // re-reads the effective interval on every cycle. A `Timer.periodic`
    // would capture the interval once, at creation, and never notice that the
    // pressure level (and therefore the intended rate) changed later — the
    // adaptive slowdown would never take effect.
    tick();
    _scheduleTick();
  }

  /// Schedules the next tick after the current effective interval. Reads
  /// [interval] fresh each cycle so the adaptive rate follows the pressure
  /// level as it changes. Cancelling [_timer] (via [stop]/[dispose]) stops the
  /// chain, since no further `_scheduleTick` runs.
  void _scheduleTick() {
    _timer?.cancel();
    _timer = Timer(interval, () {
      tick();
      _scheduleTick();
    });
  }

  /// Stops monitoring and releases the timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// A settings change is applied by building a fresh runtime for the next
  /// run; a running monitor keeps the settings it was started with so a
  /// mid-run change cannot silently alter the pressure policy. This method is
  /// therefore a deliberate no-op and exists so callers have a stable seam.
  void updateSettings(HardwareProtectionSettings newSettings) {
    // Intentionally empty: see the doc comment above.
  }

  /// Takes one sample and evaluates it. Public so tests can drive the monitor
  /// without a real timer.
  void tick() {
    _elapsedTicks++;
    final reading = _sample();
    _lastReading = reading;

    final sys = probe.systemMemory();
    _budget = resolveMemoryBudget(
      settings,
      totalBytes: sys.totalBytes,
      availableBytes: sys.availableBytes,
    );
    final decision = evaluatePressure(
      reading,
      _budget,
      settings,
      previous: _lastDecision.level,
    );
    _lastDecision = decision;

    if (settings.telemetryEnabled) {
      telemetry.add(ResourceTelemetryRecord(
        timestamp: reading.timestamp,
        appRssBytes: reading.appRssBytes,
        engineRssBytes: reading.engineRssBytes,
        totalRssBytes: reading.totalRssBytes,
        availableBytes: reading.availableBytes,
        cpuPercent: _cpuPercent,
        engineProcessCount: reading.engineProcessCount,
        engineLifecycleState: _context.engineLifecycleState,
        selectedEngineCount: _context.selectedEngineCount,
        benchmarkMode: _context.benchmarkMode,
        elapsedSeconds: (reading.timestamp.difference(_runStartedAt).inMilliseconds / 1000),
        threads: _context.threads,
        hashMb: _context.hashMb,
        pressureLevel: decision.level,
        mitigation: decision.action == PressureAction.none
            ? null
            : decision.action,
        thermalState: reading.thermalState,
        powerState: reading.powerState,
      ));
    }

    if (decision.level != _previousLevelForEvents()) {
      _pressureEvents.add(PressureEventRecord(
        timestamp: reading.timestamp,
        level: decision.level,
        action: decision.action,
        reason: decision.reason,
        budget: _budget,
      ));
      if (_pressureEvents.length > 500) _pressureEvents.removeAt(0);
    }

    if (_samples.hasListener && !_samples.isClosed) {
      _samples.add(HardwarePressureSample(reading: reading, decision: decision));
    }
  }

  ResourcePressureLevel _previousLevelForEvents() =>
      _pressureEvents.isEmpty
          ? ResourcePressureLevel.normal
          : _pressureEvents.last.level;

  /// Records a user decision (continue / pause / stop) for the report.
  void recordUserDecision(PressureUserDecision decision) {
    final record = PressureEventRecord(
      timestamp: DateTime.now(),
      level: _lastDecision.level,
      action: _lastDecision.action,
      userDecision: decision,
      reason: 'User decision: ${decision.id}',
      budget: _budget,
    );
    _pressureEvents.add(record);
    if (_pressureEvents.length > 500) _pressureEvents.removeAt(0);
    if (settings.telemetryEnabled) {
      telemetry.add(ResourceTelemetryRecord(
        timestamp: record.timestamp,
        appRssBytes: _lastReading?.appRssBytes,
        engineRssBytes: _lastReading?.engineRssBytes,
        totalRssBytes: _lastReading?.totalRssBytes,
        availableBytes: _lastReading?.availableBytes,
        cpuPercent: _cpuPercent,
        engineProcessCount: _lastReading?.engineProcessCount ?? 0,
        engineLifecycleState: _context.engineLifecycleState,
        selectedEngineCount: _context.selectedEngineCount,
        benchmarkMode: _context.benchmarkMode,
        elapsedSeconds: 0,
        threads: _context.threads,
        hashMb: _context.hashMb,
        pressureLevel: _lastDecision.level,
        userDecision: decision,
        thermalState: _lastReading?.thermalState,
        powerState: _lastReading?.powerState,
      ));
    }
  }

  /// Recommended concurrent nonessential background tasks for the current
  /// pressure. Never touches engine work.
  int backgroundConcurrency() {
    if (!settings.cpuManagementEnabled) return settings.backgroundWorkConcurrency;
    return level.severity >= ResourcePressureLevel.warning.severity
        ? settings.reducedBackgroundConcurrency
        : settings.backgroundWorkConcurrency;
  }

  /// Recommended live-board refresh rate for the current mode and pressure.
  int recommendedBoardRefreshPerSecond() {
    if (settings.liveBoardMode == LiveBoardMode.off) return 0;
    if (settings.liveBoardMode == LiveBoardMode.on) {
      return settings.liveBoardRefreshPerSecond;
    }
    // Auto: under warning or worse, halve the rate (at least once per second).
    if (level.severity >= ResourcePressureLevel.warning.severity) {
      return math.max(1, settings.liveBoardRefreshPerSecond ~/ 2);
    }
    return settings.liveBoardRefreshPerSecond;
  }

  DateTime _runStartedAt = DateTime.now();

  /// One resource sample: application memory, managed engine memory (and
  /// children where available), and the totals. Unavailable figures stay null.
  ResourceReading _sample() {
    final now = DateTime.now();
    final sys = probe.systemMemory();

    final appRss = probe.applicationRss();

    var engineRss = 0;
    var engineCount = 0;
    var enginesMeasured = false;
    final seen = <int>{};
    // Enumerate the process tree once for the whole sample, then look each
    // managed process's children up by pid. Calling children(pid) per managed
    // process would enumerate the tree once per engine, which scales badly with
    // the number of resident engines.
    final childrenByParent = probe.childrenByParent();
    for (final managed in registry.entries) {
      if (!seen.add(managed.pid)) continue;
      final mem = probe.process(managed.pid);
      final value = mem.accountedBytes;
      if (value != null) {
        engineRss += value;
        enginesMeasured = true;
      }
      engineCount++;
      // Supplement, not replace: walk children only where the platform
      // exposes them, and only for processes we manage.
      for (final child in childrenByParent[managed.pid] ?? const []) {
        if (!seen.add(child)) continue;
        final childMem = probe.process(child);
        final childValue = childMem.accountedBytes;
        if (childValue != null) {
          engineRss += childValue;
          enginesMeasured = true;
        }
      }
    }

    // The application process is the parent of the engine processes, so it is
    // counted once here and its children are not re-added.
    final total = (appRss ?? 0) + (enginesMeasured ? engineRss : 0);

    _cpuPercent = _updateCpu(now);

    return ResourceReading(
      timestamp: now,
      appRssBytes: appRss,
      engineRssBytes: enginesMeasured ? engineRss : null,
      totalRssBytes: (appRss != null || enginesMeasured) ? total : null,
      availableBytes: sys.availableBytes,
      totalBytes: sys.totalBytes,
      engineProcessCount: engineCount,
      selectedEngineCount: _context.selectedEngineCount,
      cpuPercent: _cpuPercent,
      powerState: settings.thermalPowerMonitoring ? probe.powerState() : null,
      thermalState: settings.thermalPowerMonitoring ? probe.thermalState() : null,
    );
  }

  double? _updateCpu(DateTime now) {
    final current = probe.applicationCpu();
    final previous = _lastCpu;
    final previousAt = _lastCpuAt;
    _lastCpu = current;
    _lastCpuAt = now;
    if (previous == null || previousAt == null) return null;
    final windowMs = now.difference(previousAt).inMilliseconds;
    if (windowMs <= 0) return null;
    final deltaMs = current.inMilliseconds - previous.inMilliseconds;
    if (deltaMs < 0) return null;
    return (deltaMs * 100 / windowMs).clamp(0.0, 1000.0);
  }

  /// Everything the diagnostic report needs from this run, in one map.
  /// The diagnostic snapshot for this run. By default it carries the summary
  /// (budget, latest decision, pressure events and the telemetry summary); with
  /// [includeTelemetry] it also carries the full bounded per-sample telemetry
  /// records, so the run's saved document contains the complete diagnostic
  /// data. The full records are only included at the final save, not at every
  /// per-game checkpoint, to keep checkpoints low-overhead.
  Map<String, dynamic> snapshotJson({bool includeTelemetry = false}) {
    final telemetryJson = includeTelemetry
        ? telemetry.toJson()
        : <String, dynamic>{
            'schema': 1,
            'recordCount': telemetry.count,
            'peakTotalBytes': telemetry.peakTotalBytes,
          };
    return <String, dynamic>{
      'schema': 1,
      'platform': probe.platform().id,
      'capabilities': capabilities.toJson(),
      'settings': settings.toJson(),
      'budget': _budget.toJson(),
      'level': _lastDecision.level.id,
      'action': _lastDecision.action.id,
      'reason': _lastDecision.reason,
      'cpuPercent': _cpuPercent,
      'pressureEvents': [for (final e in _pressureEvents) e.toJson()],
      'telemetry': telemetryJson,
    };
  }

  Future<void> dispose() async {
    stop();
    if (!_samples.isClosed) await _samples.close();
  }
}
