/// The Hardware Protection model: budgets, thresholds, pressure levels and the
/// pure decision logic that turns a resource reading into an action.
///
/// This file is deliberately free of `dart:io` and Flutter imports. Everything
/// here is arithmetic and state, so the pressure policy — the part that must
/// not silently reduce benchmark work — can be tested directly without a
/// device or a running benchmark.
///
/// Design notes that the rest of the system has to honour:
///
///  * A **budget** is a planning target derived from live system memory, not a
///    claim that the OS enforces a hard cap. On platforms without an
///    enforceable per-process memory limit the system reports that honestly
///    (see [HardwareCapabilitySet]) instead of pretending the number is a wall.
///  * **Warning** and **critical** thresholds are separate, and hysteresis
///    keeps a reading that hovers on a threshold from flipping the action on
///    and off every sample.
///  * The policy never mutates engine `Threads`, `Hash`, engine count or
///    statistical precision. The only things it may change are nonessential
///    application work (sampling rate, background concurrency, UI throttling)
///    and, at a user's explicit request, a safe stop at a game boundary.
library;

/// How the memory budget is chosen.
enum RamBudgetMode {
  /// Derive the limit from the memory the OS currently reports as usable,
  /// minus an OS reserve. Reacts to changing availability, not just to the
  /// installed physical RAM.
  automatic,

  /// A fixed absolute limit in megabytes, independent of the machine.
  absolute,

  /// A percentage of the currently available system memory.
  percentage;

  String get id => name;

  static RamBudgetMode fromId(String? id) => values.firstWhere(
        (value) => value.id == id,
        orElse: () => RamBudgetMode.automatic,
      );
}

/// The level of resource pressure, ordered from calm to severe.
enum ResourcePressureLevel {
  normal,
  warning,
  high,
  critical;

  String get id => name;

  /// Ordering used by the evaluator: higher index means more pressure.
  int get severity => values.indexOf(this);

  static ResourcePressureLevel fromId(String? id) => values.firstWhere(
        (value) => value.id == id,
        orElse: () => ResourcePressureLevel.normal,
      );
}

/// What a platform can actually do. The UI renders this rather than assuming
/// a control works everywhere.
enum CapabilityLevel {
  /// The capability is implemented and its effect is understood.
  fullySupported,

  /// Implemented with restrictions (for example, monitoring but no control).
  partiallySupported,

  /// Values can be read but nothing can be enforced from the app.
  monitoringOnly,

  /// The platform cannot expose the capability at all.
  unavailable;

  String get id => name;

  static CapabilityLevel fromId(String? id) => values.firstWhere(
        (value) => value.id == id,
        orElse: () => CapabilityLevel.unavailable,
      );
}

/// Summary of what a platform exposes for Hardware Protection.
///
/// Built once from the platform; the UI shows each entry with its level so a
/// control that is unavailable is never presented as if it worked.
class HardwareCapabilitySet {
  final CapabilityLevel applicationMemory;
  final CapabilityLevel engineProcessMemory;
  final CapabilityLevel processTreeMemory;
  final CapabilityLevel availableSystemMemory;
  final CapabilityLevel cpuManagement;
  final CapabilityLevel thermalMonitoring;
  final CapabilityLevel batteryMonitoring;
  final CapabilityLevel engineProcessControl;

  const HardwareCapabilitySet({
    required this.applicationMemory,
    required this.engineProcessMemory,
    required this.processTreeMemory,
    required this.availableSystemMemory,
    required this.cpuManagement,
    required this.thermalMonitoring,
    required this.batteryMonitoring,
    required this.engineProcessControl,
  });

  /// The honest summary line for a report: which capabilities this platform
  /// actually exposes.
  String get summary =>
      'application memory: ${applicationMemory.id}; engine process memory: '
      '${engineProcessMemory.id}; process-tree memory: '
      '${processTreeMemory.id}; available system memory: '
      '${availableSystemMemory.id}; CPU management: ${cpuManagement.id}; '
      'thermal: ${thermalMonitoring.id}; battery: ${batteryMonitoring.id}; '
      'engine process control: ${engineProcessControl.id}';

  Map<String, String> toJson() => {
        'applicationMemory': applicationMemory.id,
        'engineProcessMemory': engineProcessMemory.id,
        'processTreeMemory': processTreeMemory.id,
        'availableSystemMemory': availableSystemMemory.id,
        'cpuManagement': cpuManagement.id,
        'thermalMonitoring': thermalMonitoring.id,
        'batteryMonitoring': batteryMonitoring.id,
        'engineProcessControl': engineProcessControl.id,
      };

  factory HardwareCapabilitySet.fromJson(Map<String, dynamic> json) =>
      HardwareCapabilitySet(
        applicationMemory: CapabilityLevel.fromId(json['applicationMemory'] as String?),
        engineProcessMemory: CapabilityLevel.fromId(json['engineProcessMemory'] as String?),
        processTreeMemory: CapabilityLevel.fromId(json['processTreeMemory'] as String?),
        availableSystemMemory: CapabilityLevel.fromId(json['availableSystemMemory'] as String?),
        cpuManagement: CapabilityLevel.fromId(json['cpuManagement'] as String?),
        thermalMonitoring: CapabilityLevel.fromId(json['thermalMonitoring'] as String?),
        batteryMonitoring: CapabilityLevel.fromId(json['batteryMonitoring'] as String?),
        engineProcessControl: CapabilityLevel.fromId(json['engineProcessControl'] as String?),
      );
}

/// The platform family, passed in by the platform seam so this file stays pure.
enum HardwarePlatform {
  windows,
  linux,
  macos,
  android,
  ios,
  web,
  unknown;

  String get id => name;
}

/// Capability set for a platform, reflecting exactly what the resource seam
/// (`process_memory_io.dart` / `process_memory_web.dart`) can actually read on
/// that host. A level is `unavailable` wherever the implementation returns no
/// data, so the UI never presents a control as working when it cannot.
///
/// Only Linux reads system memory (`/proc/meminfo`), enumerates the process
/// tree (`/proc`), reads CPU time (`/proc/self/stat`), power state
/// (`/sys/class/power_supply`) and thermal zones (`/sys/class/thermal`).
/// macOS reads the application's and other processes' resident memory (`ps`)
/// and total system memory (`sysctl`) but enumerates no process tree.
/// Windows reads the application's own resident memory (`ProcessInfo`) and
/// controls engine processes, but reads no other process's memory, no system
/// memory, no CPU time, power or thermal state without FFI, so those are
/// reported as unavailable rather than guessed. Mobile and web cannot inspect
/// arbitrary host processes.
HardwareCapabilitySet hardwareCapabilitiesFor(HardwarePlatform platform) =>
    switch (platform) {
      HardwarePlatform.windows => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.fullySupported,
          engineProcessMemory: CapabilityLevel.unavailable,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.unavailable,
          cpuManagement: CapabilityLevel.partiallySupported,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.fullySupported),
      HardwarePlatform.linux => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.fullySupported,
          engineProcessMemory: CapabilityLevel.fullySupported,
          processTreeMemory: CapabilityLevel.partiallySupported,
          availableSystemMemory: CapabilityLevel.fullySupported,
          cpuManagement: CapabilityLevel.partiallySupported,
          thermalMonitoring: CapabilityLevel.monitoringOnly,
          batteryMonitoring: CapabilityLevel.partiallySupported,
          engineProcessControl: CapabilityLevel.fullySupported),
      HardwarePlatform.macos => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.fullySupported,
          engineProcessMemory: CapabilityLevel.fullySupported,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.partiallySupported,
          cpuManagement: CapabilityLevel.partiallySupported,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.fullySupported),
      HardwarePlatform.android => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.fullySupported,
          engineProcessMemory: CapabilityLevel.unavailable,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.unavailable,
          cpuManagement: CapabilityLevel.partiallySupported,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.unavailable),
      HardwarePlatform.ios => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.fullySupported,
          engineProcessMemory: CapabilityLevel.unavailable,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.unavailable,
          cpuManagement: CapabilityLevel.partiallySupported,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.unavailable),
      HardwarePlatform.web => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.unavailable,
          engineProcessMemory: CapabilityLevel.unavailable,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.unavailable,
          cpuManagement: CapabilityLevel.unavailable,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.unavailable),
      HardwarePlatform.unknown => const HardwareCapabilitySet(
          applicationMemory: CapabilityLevel.monitoringOnly,
          engineProcessMemory: CapabilityLevel.unavailable,
          processTreeMemory: CapabilityLevel.unavailable,
          availableSystemMemory: CapabilityLevel.unavailable,
          cpuManagement: CapabilityLevel.unavailable,
          thermalMonitoring: CapabilityLevel.unavailable,
          batteryMonitoring: CapabilityLevel.unavailable,
          engineProcessControl: CapabilityLevel.unavailable),
    };

/// How the live board refreshes during a benchmark.
enum LiveBoardMode {
  /// Choose a refresh rate from the current pressure: slower under pressure,
  /// restored when pressure subsides.
  auto,

  /// Live board on, at the configured rate.
  on,

  /// Live board rendering off. Benchmark events, game data and final
  /// positions are still collected and processed normally.
  off;

  String get id => name;

  static LiveBoardMode fromId(String? id) => values.firstWhere(
        (value) => value.id == id,
        orElse: () => LiveBoardMode.auto,
      );
}

/// User-facing Hardware Protection configuration.
///
/// Defaults are automatic and adaptive. A stored document from an older build
/// (or one with missing keys) falls back to these values, so enabling the
/// feature never depends on a migration.
class HardwareProtectionSettings {
  /// Master switch. When false the system does not sample, warn or mitigate.
  final bool enabled;

  /// Automatic, absolute or percentage budgeting.
  final RamBudgetMode ramBudgetMode;

  /// Megabytes of system memory kept free for the OS and other apps. Used by
  /// the automatic and percentage policies.
  final int memoryReserveMb;

  /// Optional absolute limit in megabytes (used when [ramBudgetMode] is
  /// [RamBudgetMode.absolute]). Null means "not set".
  final int? absoluteLimitMb;

  /// Optional percentage of available memory (used when [ramBudgetMode] is
  /// [RamBudgetMode.percentage]). Null means "not set".
  final double? percentageLimit;

  /// Fraction of the budget at which pressure becomes a warning.
  final double warningRatio;

  /// Fraction of the budget at which pressure becomes high.
  final double highRatio;

  /// Fraction of the budget at which pressure becomes critical.
  final double criticalRatio;

  /// Fraction the usage must fall below to leave the warning level.
  final double warningHysteresis;

  /// Fraction the usage must fall below to leave the high level.
  final double highHysteresis;

  /// Fraction the usage must fall below to leave the critical level.
  final double criticalHysteresis;

  /// Adaptive background-work management (nonessential work only).
  final bool cpuManagementEnabled;

  /// Maximum concurrent nonessential background tasks at normal pressure.
  final int backgroundWorkConcurrency;

  /// Reduce background work to this concurrency while under warning pressure.
  final int reducedBackgroundConcurrency;

  /// Collect thermal/battery indicators when the platform exposes them.
  final bool thermalPowerMonitoring;

  /// Live board mode.
  final LiveBoardMode liveBoardMode;

  /// Maximum board refreshes per second in `on` mode.
  final int liveBoardRefreshPerSecond;

  /// Seconds between resource samples.
  final int samplingIntervalSeconds;

  /// Record resource telemetry during benchmarks.
  final bool telemetryEnabled;

  /// Maximum telemetry records kept in memory and persisted.
  final int telemetryMaxRecords;

  /// How many completed-game checkpoints to keep coalesced before a forced
  /// flush. 1 means a checkpoint is initiated after every completed game.
  final int checkpointEveryGame;

  const HardwareProtectionSettings({
    this.enabled = true,
    this.ramBudgetMode = RamBudgetMode.automatic,
    this.memoryReserveMb = 1024,
    this.absoluteLimitMb,
    this.percentageLimit,
    this.warningRatio = 0.75,
    this.highRatio = 0.85,
    this.criticalRatio = 0.95,
    this.warningHysteresis = 0.05,
    this.highHysteresis = 0.05,
    this.criticalHysteresis = 0.05,
    this.cpuManagementEnabled = true,
    this.backgroundWorkConcurrency = 2,
    this.reducedBackgroundConcurrency = 1,
    this.thermalPowerMonitoring = true,
    this.liveBoardMode = LiveBoardMode.auto,
    this.liveBoardRefreshPerSecond = 4,
    this.samplingIntervalSeconds = 5,
    this.telemetryEnabled = true,
    this.telemetryMaxRecords = 2000,
    this.checkpointEveryGame = 1,
  });

  /// A plain-language explanation of the chosen memory policy, shown in the
  /// settings screen so the user knows what the numbers mean.
  String get budgetExplanation => switch (ramBudgetMode) {
        RamBudgetMode.automatic =>
            'Automatic: the limit is the memory the OS currently reports as '
            'usable, minus a ${memoryReserveMb} MB reserve. It follows changing '
            'availability, not just installed RAM. This is a planning target, '
            'not an OS-enforced cap.',
        RamBudgetMode.absolute =>
            'Absolute: the app and its engines aim to stay under '
            '${absoluteLimitMb ?? 0} MB. This is a planning target, not an '
            'OS-enforced cap on platforms that cannot enforce one.',
        RamBudgetMode.percentage =>
            'Percentage: the app and its engines aim to stay under '
            '${(percentageLimit ?? 0).toStringAsFixed(0)}% of the memory the '
            'OS currently reports as usable. This is a planning target, not an '
            'OS-enforced cap.',
      };

  HardwareProtectionSettings copyWith({
    bool? enabled,
    RamBudgetMode? ramBudgetMode,
    int? memoryReserveMb,
    int? absoluteLimitMb,
    double? percentageLimit,
    double? warningRatio,
    double? highRatio,
    double? criticalRatio,
    double? warningHysteresis,
    double? highHysteresis,
    double? criticalHysteresis,
    bool? cpuManagementEnabled,
    int? backgroundWorkConcurrency,
    int? reducedBackgroundConcurrency,
    bool? thermalPowerMonitoring,
    LiveBoardMode? liveBoardMode,
    int? liveBoardRefreshPerSecond,
    int? samplingIntervalSeconds,
    bool? telemetryEnabled,
    int? telemetryMaxRecords,
    int? checkpointEveryGame,
  }) =>
      HardwareProtectionSettings(
        enabled: enabled ?? this.enabled,
        ramBudgetMode: ramBudgetMode ?? this.ramBudgetMode,
        memoryReserveMb: memoryReserveMb ?? this.memoryReserveMb,
        absoluteLimitMb: absoluteLimitMb ?? this.absoluteLimitMb,
        percentageLimit: percentageLimit ?? this.percentageLimit,
        warningRatio: warningRatio ?? this.warningRatio,
        highRatio: highRatio ?? this.highRatio,
        criticalRatio: criticalRatio ?? this.criticalRatio,
        warningHysteresis: warningHysteresis ?? this.warningHysteresis,
        highHysteresis: highHysteresis ?? this.highHysteresis,
        criticalHysteresis: criticalHysteresis ?? this.criticalHysteresis,
        cpuManagementEnabled: cpuManagementEnabled ?? this.cpuManagementEnabled,
        backgroundWorkConcurrency:
            backgroundWorkConcurrency ?? this.backgroundWorkConcurrency,
        reducedBackgroundConcurrency:
            reducedBackgroundConcurrency ?? this.reducedBackgroundConcurrency,
        thermalPowerMonitoring:
            thermalPowerMonitoring ?? this.thermalPowerMonitoring,
        liveBoardMode: liveBoardMode ?? this.liveBoardMode,
        liveBoardRefreshPerSecond:
            liveBoardRefreshPerSecond ?? this.liveBoardRefreshPerSecond,
        samplingIntervalSeconds:
            samplingIntervalSeconds ?? this.samplingIntervalSeconds,
        telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
        telemetryMaxRecords: telemetryMaxRecords ?? this.telemetryMaxRecords,
        checkpointEveryGame: checkpointEveryGame ?? this.checkpointEveryGame,
      );

  List<String> validationErrors() {
    final errors = <String>[];
    if (memoryReserveMb < 0) {
      errors.add('The memory reserve cannot be negative.');
    }
    if (absoluteLimitMb != null && absoluteLimitMb! <= 0) {
      errors.add('An absolute memory limit must be positive.');
    }
    if (percentageLimit != null &&
        (percentageLimit! <= 0 || percentageLimit! > 100)) {
      errors.add('A percentage memory limit must be between 1 and 100.');
    }
    for (final (name, ratio) in <(String, double)>[
      ('warning', warningRatio),
      ('high', highRatio),
      ('critical', criticalRatio),
    ]) {
      if (!ratio.isFinite || ratio <= 0 || ratio > 1) {
        errors.add('The $name threshold must be between 0 and 1.');
      }
    }
    if (warningRatio >= highRatio) {
      errors.add('The warning threshold must be below the high threshold.');
    }
    if (highRatio >= criticalRatio) {
      errors.add('The high threshold must be below the critical threshold.');
    }
    for (final (name, hysteresis) in <(String, double)>[
      ('warning', warningHysteresis),
      ('high', highHysteresis),
      ('critical', criticalHysteresis),
    ]) {
      if (!hysteresis.isFinite || hysteresis < 0 || hysteresis >= 1) {
        errors.add('The $name hysteresis must be between 0 and 1.');
      }
    }
    if (backgroundWorkConcurrency < 1) {
      errors.add('Background work concurrency must be at least 1.');
    }
    if (reducedBackgroundConcurrency < 1 ||
        reducedBackgroundConcurrency > backgroundWorkConcurrency) {
      errors.add('Reduced background concurrency must be between 1 and the '
          'normal concurrency.');
    }
    if (liveBoardRefreshPerSecond < 0 || liveBoardRefreshPerSecond > 60) {
      errors.add('The board refresh rate must be between 0 and 60 per second.');
    }
    if (samplingIntervalSeconds < 1 || samplingIntervalSeconds > 60) {
      errors.add('The sampling interval must be between 1 and 60 seconds.');
    }
    if (telemetryMaxRecords < 1) {
      errors.add('The telemetry limit must be at least 1.');
    }
    if (checkpointEveryGame < 1) {
      errors.add('Checkpointing must run at least once per game.');
    }
    return errors;
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'ramBudgetMode': ramBudgetMode.id,
        'memoryReserveMb': memoryReserveMb,
        if (absoluteLimitMb != null) 'absoluteLimitMb': absoluteLimitMb,
        if (percentageLimit != null) 'percentageLimit': percentageLimit,
        'warningRatio': warningRatio,
        'highRatio': highRatio,
        'criticalRatio': criticalRatio,
        'warningHysteresis': warningHysteresis,
        'highHysteresis': highHysteresis,
        'criticalHysteresis': criticalHysteresis,
        'cpuManagementEnabled': cpuManagementEnabled,
        'backgroundWorkConcurrency': backgroundWorkConcurrency,
        'reducedBackgroundConcurrency': reducedBackgroundConcurrency,
        'thermalPowerMonitoring': thermalPowerMonitoring,
        'liveBoardMode': liveBoardMode.id,
        'liveBoardRefreshPerSecond': liveBoardRefreshPerSecond,
        'samplingIntervalSeconds': samplingIntervalSeconds,
        'telemetryEnabled': telemetryEnabled,
        'telemetryMaxRecords': telemetryMaxRecords,
        'checkpointEveryGame': checkpointEveryGame,
      };

  /// Reads a stored document. Missing keys keep their defaults, so a document
  /// written before Hardware Protection existed still loads.
  factory HardwareProtectionSettings.fromJson(Map<String, dynamic> json) {
    double? doubleOf(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : null;
    }

    int? intOf(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    bool boolOf(String key, bool fallback) =>
        json[key] is bool ? json[key] as bool : fallback;

    return HardwareProtectionSettings(
      enabled: boolOf('enabled', true),
      ramBudgetMode: RamBudgetMode.fromId(json['ramBudgetMode'] as String?),
      memoryReserveMb: intOf('memoryReserveMb') ?? 1024,
      absoluteLimitMb: intOf('absoluteLimitMb'),
      percentageLimit: doubleOf('percentageLimit'),
      warningRatio: doubleOf('warningRatio') ?? 0.75,
      highRatio: doubleOf('highRatio') ?? 0.85,
      criticalRatio: doubleOf('criticalRatio') ?? 0.95,
      warningHysteresis: doubleOf('warningHysteresis') ?? 0.05,
      highHysteresis: doubleOf('highHysteresis') ?? 0.05,
      criticalHysteresis: doubleOf('criticalHysteresis') ?? 0.05,
      cpuManagementEnabled: boolOf('cpuManagementEnabled', true),
      backgroundWorkConcurrency:
          intOf('backgroundWorkConcurrency') ?? 2,
      reducedBackgroundConcurrency:
          intOf('reducedBackgroundConcurrency') ?? 1,
      thermalPowerMonitoring: boolOf('thermalPowerMonitoring', true),
      liveBoardMode: LiveBoardMode.fromId(json['liveBoardMode'] as String?),
      liveBoardRefreshPerSecond:
          intOf('liveBoardRefreshPerSecond') ?? 4,
      samplingIntervalSeconds: intOf('samplingIntervalSeconds') ?? 5,
      telemetryEnabled: boolOf('telemetryEnabled', true),
      telemetryMaxRecords: intOf('telemetryMaxRecords') ?? 2000,
      checkpointEveryGame: intOf('checkpointEveryGame') ?? 1,
    );
  }
}

/// A resolved memory budget: the planning target the pressure thresholds are
/// measured against, plus a human-readable account of how it was derived.
class MemoryBudget {
  /// The planning limit in bytes. `null` when no usable limit can be derived.
  final int? limitBytes;

  /// How the limit was produced, for the report and the settings screen.
  final String source;

  /// Total system memory in bytes, when the platform reports it.
  final int? totalBytes;

  /// Memory the OS reports as currently available, when it reports it.
  final int? availableBytes;

  const MemoryBudget({
    this.limitBytes,
    required this.source,
    this.totalBytes,
    this.availableBytes,
  });

  bool get isUsable => limitBytes != null && limitBytes! > 0;

  Map<String, dynamic> toJson() => {
        if (limitBytes != null) 'limitBytes': limitBytes,
        'source': source,
        if (totalBytes != null) 'totalBytes': totalBytes,
        if (availableBytes != null) 'availableBytes': availableBytes,
      };

  factory MemoryBudget.fromJson(Map<String, dynamic> json) {
    int? intOf(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    return MemoryBudget(
      limitBytes: intOf('limitBytes'),
      source: json['source'] as String? ?? '',
      totalBytes: intOf('totalBytes'),
      availableBytes: intOf('availableBytes'),
    );
  }
}

/// Derives the memory budget from the settings and the live system memory.
///
/// `available` is the memory the OS currently reports as usable; falling back
/// to `total` when availability is not reported keeps the automatic policy
/// meaningful on platforms that only expose totals.
MemoryBudget resolveMemoryBudget(
  HardwareProtectionSettings settings, {
  int? totalBytes,
  int? availableBytes,
}) {
  final available = availableBytes ?? totalBytes;
  switch (settings.ramBudgetMode) {
    case RamBudgetMode.automatic: {
      if (available == null || available <= 0) {
        return const MemoryBudget(
          source: 'automatic: system memory unavailable',
        );
      }
      final reserve = settings.memoryReserveMb * 1024 * 1024;
      final limit = (available - reserve).clamp(0, available);
      return MemoryBudget(
        limitBytes: limit,
        totalBytes: totalBytes,
        availableBytes: availableBytes,
        source: 'automatic: available ${_mb(available)} MB minus a '
            '${settings.memoryReserveMb} MB reserve',
      );
    }
    case RamBudgetMode.absolute: {
      final limit = settings.absoluteLimitMb;
      if (limit == null || limit <= 0) {
        return const MemoryBudget(
          source: 'absolute: no limit set',
        );
      }
      return MemoryBudget(
        limitBytes: limit * 1024 * 1024,
        totalBytes: totalBytes,
        availableBytes: availableBytes,
        source: 'absolute: ${limit} MB',
      );
    }
    case RamBudgetMode.percentage: {
      final pct = settings.percentageLimit;
      if (pct == null || pct <= 0 || available == null || available <= 0) {
        return const MemoryBudget(
          source: 'percentage: no usable limit',
        );
      }
      return MemoryBudget(
        limitBytes: (available * pct / 100).floor(),
        totalBytes: totalBytes,
        availableBytes: availableBytes,
        source: 'percentage: ${pct.toStringAsFixed(0)}% of available '
            '${_mb(available)} MB',
      );
    }
  }
}

/// One resource reading: what the monitor measured, with unavailable metrics
/// kept distinct from a genuine zero.
class ResourceReading {
  final DateTime timestamp;

  /// Resident memory of the application process. Null when unavailable.
  final int? appRssBytes;

  /// Sum of the resident memory of the managed engine processes. Null when
  /// no engine process could be measured (not zero: unavailable).
  final int? engineRssBytes;

  /// Sum of the memory of the process tree (application plus managed engine
  /// processes, children counted once). Null when unavailable.
  final int? totalRssBytes;

  /// Memory the OS reports as available. Null when unavailable.
  final int? availableBytes;

  /// Total system memory. Null when unavailable.
  final int? totalBytes;

  /// Number of managed engine processes currently registered.
  final int engineProcessCount;

  /// Number of engines selected for the running benchmark.
  final int selectedEngineCount;

  /// Application CPU usage percentage over the sampling window, or null when
  /// the platform cannot report a scoped CPU figure.
  final double? cpuPercent;

  /// Battery/power state, or null when unavailable.
  final String? powerState;

  /// Thermal/performance-pressure state, or null when unavailable.
  final String? thermalState;

  const ResourceReading({
    required this.timestamp,
    this.appRssBytes,
    this.engineRssBytes,
    this.totalRssBytes,
    this.availableBytes,
    this.totalBytes,
    this.engineProcessCount = 0,
    this.selectedEngineCount = 0,
    this.cpuPercent,
    this.powerState,
    this.thermalState,
  });

  /// The memory figure the pressure policy compares against the budget. It
  /// deliberately uses [totalRssBytes] — application plus managed engine
  /// processes, each counted once — so a parent process and its children are
  /// not double-counted.
  int? get usageBytes => totalRssBytes;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (appRssBytes != null) 'appRssBytes': appRssBytes,
        if (engineRssBytes != null) 'engineRssBytes': engineRssBytes,
        if (totalRssBytes != null) 'totalRssBytes': totalRssBytes,
        if (availableBytes != null) 'availableBytes': availableBytes,
        if (totalBytes != null) 'totalBytes': totalBytes,
        'engineProcessCount': engineProcessCount,
        'selectedEngineCount': selectedEngineCount,
        if (cpuPercent != null) 'cpuPercent': cpuPercent,
        if (powerState != null) 'powerState': powerState,
        if (thermalState != null) 'thermalState': thermalState,
      };

  factory ResourceReading.fromJson(Map<String, dynamic> json) {
    int? intOf(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      return null;
    }

    double? doubleOf(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : null;
    }

    return ResourceReading(
      timestamp: DateTime.parse(json['timestamp'] as String),
      appRssBytes: intOf('appRssBytes'),
      engineRssBytes: intOf('engineRssBytes'),
      totalRssBytes: intOf('totalRssBytes'),
      availableBytes: intOf('availableBytes'),
      totalBytes: intOf('totalBytes'),
      engineProcessCount: intOf('engineProcessCount') ?? 0,
      selectedEngineCount: intOf('selectedEngineCount') ?? 0,
      cpuPercent: doubleOf('cpuPercent'),
      powerState: json['powerState'] as String?,
      thermalState: json['thermalState'] as String?,
    );
  }
}

/// The system-wide memory figures the budget is derived from.
///
/// A field is `null` when the platform cannot report it, which is kept
/// distinct from a real zero.
class SystemMemorySample {
  final int? totalBytes;
  final int? availableBytes;

  const SystemMemorySample({this.totalBytes, this.availableBytes});

  bool get isUsable => totalBytes != null || availableBytes != null;
}

/// One process's memory, as the platform reports it.
///
/// `rssBytes` is the resident set; `workingSetBytes` and `privateBytes` are
/// reported where the platform distinguishes them. They are kept separate so
/// the UI never adds incompatible measurements into a misleading total.
class ProcessMemorySample {
  final int pid;
  final int? rssBytes;
  final int? workingSetBytes;
  final int? privateBytes;

  const ProcessMemorySample({
    required this.pid,
    this.rssBytes,
    this.workingSetBytes,
    this.privateBytes,
  });

  /// The figure used for footprint accounting: resident memory, or the
  /// working set where resident memory is not reported.
  int? get accountedBytes => rssBytes ?? workingSetBytes;

  bool get isUsable => accountedBytes != null;
}

/// The abstract resource probe the runtime samples through. The platform seam
/// supplies the real implementation; tests supply a fake, so the sampling and
/// policy logic can be exercised without a device.
abstract class ResourceProbe {
  HardwarePlatform platform();
  SystemMemorySample systemMemory();
  ProcessMemorySample process(int pid);
  int? applicationRss();
  Duration applicationCpu();

  /// Children of one process, best-effort. Kept for callers that need a
  /// single lookup; the monitor uses [childrenByParent] so it enumerates the
  /// process tree once per sample rather than once per managed process.
  List<int> children(int pid);

  /// Every parent→children mapping the platform can enumerate, in a single
  /// pass. The monitor calls this once per sample and looks up each managed
  /// process's children from the result, so enumerating the process tree does
  /// not cost one full enumeration per engine. An empty map means "no
  /// children could be enumerated" (not "no children exist").
  Map<int, List<int>> childrenByParent();

  String? powerState();
  String? thermalState();
}

/// The mitigation the policy decided on for a reading.
enum PressureAction {
  /// Continue normally; collect lightweight monitoring data.
  none,

  /// Reduce nonessential background work and show a warning; ask the user.
  reduceBackground,

  /// Pause after the current game and save progress.
  pauseAfterGame,

  /// Stop at a safe boundary and preserve completed results.
  stop;

  String get id => name;
}

/// The outcome of evaluating one reading.
class PressureDecision {
  final ResourcePressureLevel level;
  final PressureAction action;
  final String reason;
  final MemoryBudget budget;

  const PressureDecision({
    required this.level,
    required this.action,
    required this.reason,
    required this.budget,
  });

  bool get isCalm => level == ResourcePressureLevel.normal;

  Map<String, dynamic> toJson() => {
        'level': level.id,
        'action': action.id,
        'reason': reason,
        'budget': budget.toJson(),
      };
}

/// Pure pressure evaluation with hysteresis.
///
/// Given a reading, a budget and the previous level, it returns the next level
/// and the action to take. The previous level is part of the input so the
/// hysteresis bands are stable across samples: leaving a level requires the
/// usage to fall below the entry threshold by the hysteresis fraction.
PressureDecision evaluatePressure(
  ResourceReading reading,
  MemoryBudget budget,
  HardwareProtectionSettings settings, {
  ResourcePressureLevel previous = ResourcePressureLevel.normal,
}) {
  if (!settings.enabled || !budget.isUsable) {
    return const PressureDecision(
      level: ResourcePressureLevel.normal,
      action: PressureAction.none,
      reason: 'Hardware Protection is disabled or no budget is available.',
      budget: MemoryBudget(source: 'none'),
    );
  }
  final usage = reading.usageBytes;
  if (usage == null || usage <= 0) {
    return PressureDecision(
      level: ResourcePressureLevel.normal,
      action: PressureAction.none,
      reason: 'No usable memory reading was available.',
      budget: budget,
    );
  }

  final limit = budget.limitBytes!;
  final warningAt = limit * settings.warningRatio;
  final highAt = limit * settings.highRatio;
  final criticalAt = limit * settings.criticalRatio;

  double ratioOf(double threshold, double hysteresis) =>
      threshold * (1 - hysteresis);

  ResourcePressureLevel next;
  String reason;
  PressureAction action;

  // The decision is evaluated top-down: a level is entered when usage reaches
  // its threshold, and left only when usage falls below the entry threshold by
  // the hysteresis fraction. A reading that sits in the hysteresis band (above
  // the exit threshold but below the entry threshold) with the previous level
  // still active *stays* at that level — the `else` branches below are the
  // explicit "stay" cases that keep a hovering reading from oscillating.
  if (usage >= criticalAt) {
    next = ResourcePressureLevel.critical;
    reason = 'Memory use reached ${_pct(usage, limit)} of the budget '
        '(${_mb(usage)} MB of ${_mb(limit)} MB); recovery is prioritised.';
    action = PressureAction.stop;
  } else if (previous == ResourcePressureLevel.critical) {
    if (usage < ratioOf(criticalAt, settings.criticalHysteresis)) {
      // Hysteresis: only leave critical once usage has fallen clearly below
      // the entry threshold, so a hovering reading does not oscillate.
      next = ResourcePressureLevel.high;
      reason = 'Memory use fell below the critical band; pressure remains high.';
      action = PressureAction.pauseAfterGame;
    } else {
      // Still in the critical hysteresis band: stay critical.
      next = ResourcePressureLevel.critical;
      reason = 'Memory use remains in the critical band '
          '(${_pct(usage, limit)} of the budget).';
      action = PressureAction.stop;
    }
  } else if (usage >= highAt) {
    next = ResourcePressureLevel.high;
    reason = 'Memory use reached ${_pct(usage, limit)} of the budget '
        '(${_mb(usage)} MB of ${_mb(limit)} MB).';
    action = PressureAction.pauseAfterGame;
  } else if (previous == ResourcePressureLevel.high) {
    if (usage < ratioOf(highAt, settings.highHysteresis)) {
      next = ResourcePressureLevel.warning;
      reason = 'Memory use fell below the high band; pressure remains elevated.';
      action = PressureAction.reduceBackground;
    } else {
      // Still in the high hysteresis band: stay high.
      next = ResourcePressureLevel.high;
      reason = 'Memory use remains in the high band '
          '(${_pct(usage, limit)} of the budget).';
      action = PressureAction.pauseAfterGame;
    }
  } else if (usage >= warningAt) {
    next = ResourcePressureLevel.warning;
    reason = 'Memory use reached ${_pct(usage, limit)} of the budget '
        '(${_mb(usage)} MB of ${_mb(limit)} MB).';
    action = PressureAction.reduceBackground;
  } else if (previous == ResourcePressureLevel.warning) {
    if (usage < ratioOf(warningAt, settings.warningHysteresis)) {
      next = ResourcePressureLevel.normal;
      reason = 'Memory use fell below the warning band; pressure is normal.';
      action = PressureAction.none;
    } else {
      // Still in the warning hysteresis band: stay warning.
      next = ResourcePressureLevel.warning;
      reason = 'Memory use remains in the warning band '
          '(${_pct(usage, limit)} of the budget).';
      action = PressureAction.reduceBackground;
    }
  } else {
    next = ResourcePressureLevel.normal;
    reason = 'Memory use is within the budget.';
    action = PressureAction.none;
  }

  return PressureDecision(level: next, action: action, reason: reason, budget: budget);
}

/// A user decision recorded for the diagnostic report.
enum PressureUserDecision {
  none,
  continueAnyway,
  pauseAfterGame,
  stop;

  String get id => name;

  static PressureUserDecision fromId(String? id) => values.firstWhere(
        (value) => value.id == id,
        orElse: () => PressureUserDecision.none,
      );
}

/// One recorded mitigation or user decision, for the diagnostic report.
class PressureEventRecord {
  final DateTime timestamp;
  final ResourcePressureLevel level;
  final PressureAction action;
  final PressureUserDecision? userDecision;
  final String reason;
  final MemoryBudget budget;

  const PressureEventRecord({
    required this.timestamp,
    required this.level,
    required this.action,
    this.userDecision,
    required this.reason,
    required this.budget,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'level': level.id,
        'action': action.id,
        if (userDecision != null) 'userDecision': userDecision!.id,
        'reason': reason,
        'budget': budget.toJson(),
      };

  factory PressureEventRecord.fromJson(Map<String, dynamic> json) =>
      PressureEventRecord(
        timestamp: DateTime.parse(json['timestamp'] as String),
        level: ResourcePressureLevel.fromId(json['level'] as String?),
        action: PressureAction.values.firstWhere(
          (value) => value.id == json['action'] as String?,
          orElse: () => PressureAction.none,
        ),
        userDecision: PressureUserDecision.fromId(json['userDecision'] as String?),
        reason: json['reason'] as String? ?? '',
        budget: MemoryBudget.fromJson(
            Map<String, dynamic>.from(json['budget'] as Map)),
      );
}

String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

String _pct(int usage, int limit) =>
    (usage * 100 / limit).clamp(0.0, 999.0).toStringAsFixed(1);

/// A small helper for the UI: a stable string for a capability level.
String capabilityLabel(CapabilityLevel level) => switch (level) {
      CapabilityLevel.fullySupported => 'supported',
      CapabilityLevel.partiallySupported => 'partial',
      CapabilityLevel.monitoringOnly => 'monitoring only',
      CapabilityLevel.unavailable => 'unavailable',
    };

/// The largest of two pressure levels, used when merging an evaluation with a
/// previously observed level that has not yet been cleared.
ResourcePressureLevel maxPressure(
    ResourcePressureLevel a, ResourcePressureLevel b) =>
    a.severity >= b.severity ? a : b;
