/// Bounded resource telemetry for a benchmark run.
///
/// One record per sample, carrying the measurements the diagnostic report needs
/// to explain why a run consumed what it did: application memory, managed
/// engine memory, the total footprint, available system memory, CPU, engine
/// count and lifecycle state, the run's configuration, pressure events,
/// mitigations and user decisions.
///
/// The log is bounded in memory and in storage: [maxRecords] caps it, and the
/// oldest records are dropped first. It is written under its own versioned key
/// so it never disturbs the benchmark result format, and a reader from an
/// older build simply sees no telemetry rather than failing.
library;

import 'hardware_protection.dart'
    show PressureAction, PressureUserDecision, ResourcePressureLevel;

/// Schema of the persisted telemetry document.
const int kResourceTelemetrySchema = 1;

/// One telemetry sample.
class ResourceTelemetryRecord {
  final DateTime timestamp;
  final int? appRssBytes;
  final int? engineRssBytes;
  final int? totalRssBytes;
  final int? availableBytes;
  final double? cpuPercent;
  final int engineProcessCount;
  final String engineLifecycleState;
  final int selectedEngineCount;
  final String benchmarkMode;
  final double elapsedSeconds;
  final int threads;
  final int hashMb;
  final ResourcePressureLevel pressureLevel;
  final PressureAction? mitigation;
  final PressureUserDecision? userDecision;
  final String? thermalState;
  final String? powerState;
  final double? uiFrameGapMs;

  const ResourceTelemetryRecord({
    required this.timestamp,
    this.appRssBytes,
    this.engineRssBytes,
    this.totalRssBytes,
    this.availableBytes,
    this.cpuPercent,
    required this.engineProcessCount,
    required this.engineLifecycleState,
    required this.selectedEngineCount,
    required this.benchmarkMode,
    required this.elapsedSeconds,
    required this.threads,
    required this.hashMb,
    required this.pressureLevel,
    this.mitigation,
    this.userDecision,
    this.thermalState,
    this.powerState,
    this.uiFrameGapMs,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        if (appRssBytes != null) 'appRssBytes': appRssBytes,
        if (engineRssBytes != null) 'engineRssBytes': engineRssBytes,
        if (totalRssBytes != null) 'totalRssBytes': totalRssBytes,
        if (availableBytes != null) 'availableBytes': availableBytes,
        if (cpuPercent != null) 'cpuPercent': cpuPercent,
        'engineProcessCount': engineProcessCount,
        'engineLifecycleState': engineLifecycleState,
        'selectedEngineCount': selectedEngineCount,
        'benchmarkMode': benchmarkMode,
        'elapsedSeconds': elapsedSeconds,
        'threads': threads,
        'hashMb': hashMb,
        'pressureLevel': pressureLevel.id,
        if (mitigation != null) 'mitigation': mitigation!.id,
        if (userDecision != null) 'userDecision': userDecision!.id,
        if (thermalState != null) 'thermalState': thermalState,
        if (powerState != null) 'powerState': powerState,
        if (uiFrameGapMs != null) 'uiFrameGapMs': uiFrameGapMs,
      };

  factory ResourceTelemetryRecord.fromJson(Map<String, dynamic> json) {
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

    return ResourceTelemetryRecord(
      timestamp: DateTime.parse(json['timestamp'] as String),
      appRssBytes: intOf('appRssBytes'),
      engineRssBytes: intOf('engineRssBytes'),
      totalRssBytes: intOf('totalRssBytes'),
      availableBytes: intOf('availableBytes'),
      cpuPercent: doubleOf('cpuPercent'),
      engineProcessCount: intOf('engineProcessCount') ?? 0,
      engineLifecycleState: json['engineLifecycleState'] as String? ?? 'unknown',
      selectedEngineCount: intOf('selectedEngineCount') ?? 0,
      benchmarkMode: json['benchmarkMode'] as String? ?? 'unknown',
      elapsedSeconds: doubleOf('elapsedSeconds') ?? 0,
      threads: intOf('threads') ?? 0,
      hashMb: intOf('hashMb') ?? 0,
      pressureLevel: ResourcePressureLevel.fromId(json['pressureLevel'] as String?),
      mitigation: json['mitigation'] is String
          ? PressureAction.values.firstWhere(
              (value) => value.id == json['mitigation'],
              orElse: () => PressureAction.none,
            )
          : null,
      userDecision: json['userDecision'] is String
          ? PressureUserDecision.fromId(json['userDecision'] as String)
          : null,
      thermalState: json['thermalState'] as String?,
      powerState: json['powerState'] as String?,
      uiFrameGapMs: doubleOf('uiFrameGapMs'),
    );
  }
}

/// A bounded, versioned collection of telemetry records.
/// Escape a value for CSV: quote it when it contains a comma, a double quote
/// or a line break, and double any embedded double quotes. Without this a
/// value such as a state string containing a comma would be split across
/// columns and shift every following field in the row.
String _csvEscape(String value) {
  if (value.isEmpty) return '';
  if (value.contains(',') || value.contains('"') ||
      value.contains('\n') || value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

class ResourceTelemetryLog {
  final int maxRecords;
  final List<ResourceTelemetryRecord> records = [];

  ResourceTelemetryLog({this.maxRecords = 2000});

  void add(ResourceTelemetryRecord record) {
    records.add(record);
    // A non-positive limit is invalid (a persisted `-1` reaches here through
    // the settings). Never trim on it: `records.length > -1` is always true and
    // would drain the list and then throw removing from an empty list. Only
    // trim against a positive cap; a zero or negative limit leaves the log
    // unbounded rather than crashing the sampler.
    if (maxRecords <= 0) return;
    while (records.length > maxRecords) {
      records.removeAt(0);
    }
  }

  int get count => records.length;

  /// Peak total footprint observed, for the report header.
  int? get peakTotalBytes {
    int? peak;
    for (final record in records) {
      final value = record.totalRssBytes;
      if (value != null && (peak == null || value > peak)) peak = value;
    }
    return peak;
  }

  Map<String, dynamic> toJson() => {
        'schema': kResourceTelemetrySchema,
        'records': [for (final record in records) record.toJson()],
      };

  /// Reads a stored document. A missing or older document yields an empty log
  /// rather than an error, so telemetry never blocks the app.
  factory ResourceTelemetryLog.fromJson(
      Map<String, dynamic> json, {int maxRecords = 2000}) {
    final log = ResourceTelemetryLog(maxRecords: maxRecords);
    final raw = json['records'];
    if (raw is List) {
      for (final entry in raw) {
        if (entry is Map) {
          // A record that cannot be parsed (a missing or malformed timestamp,
          // a corrupt field) is skipped rather than failing the whole read:
          // telemetry is best-effort and must never block the app or crash a
          // diagnostic report built from an older or partial document.
          try {
            log.add(
              ResourceTelemetryRecord.fromJson(
                  Map<String, dynamic>.from(entry)),
            );
          } catch (_) {
            // Skip this record and keep reading the rest of the document.
          }
        }
      }
    }
    return log;
  }

  /// The CSV the diagnostic report writes. New columns are additive; a reader
  /// that does not know them simply ignores them.
  String toCsv() {
    final buffer = StringBuffer(
        'timestamp_utc,app_rss_bytes,engine_rss_bytes,total_rss_bytes,'
        'available_bytes,cpu_percent,engine_processes,engine_lifecycle,'
        'selected_engines,benchmark_mode,elapsed_seconds,threads,hash_mb,'
        'pressure_level,mitigation,user_decision,thermal,power,ui_gap_ms\n');
    for (final record in records) {
      buffer.writeln(<String>[
        _csvEscape(record.timestamp.toUtc().toIso8601String()),
        _csvEscape('${record.appRssBytes ?? ""}'),
        _csvEscape('${record.engineRssBytes ?? ""}'),
        _csvEscape('${record.totalRssBytes ?? ""}'),
        _csvEscape('${record.availableBytes ?? ""}'),
        _csvEscape('${record.cpuPercent ?? ""}'),
        _csvEscape('${record.engineProcessCount}'),
        _csvEscape(record.engineLifecycleState),
        _csvEscape('${record.selectedEngineCount}'),
        _csvEscape(record.benchmarkMode),
        _csvEscape('${record.elapsedSeconds.toStringAsFixed(3)}'),
        _csvEscape('${record.threads}'),
        _csvEscape('${record.hashMb}'),
        _csvEscape(record.pressureLevel.id),
        _csvEscape('${record.mitigation?.id ?? ""}'),
        _csvEscape('${record.userDecision?.id ?? ""}'),
        _csvEscape('${record.thermalState ?? ""}'),
        _csvEscape('${record.powerState ?? ""}'),
        _csvEscape('${record.uiFrameGapMs ?? ""}'),
      ].join(','));
    }
    return buffer.toString();
  }
}
