/// Lightweight resource diagnostics.
///
/// Snapshots what the Dart runtime can report cheaply — the process's
/// resident memory via `getCurrentRSS()`, plus counters the engine lifecycle
/// maintains — while a diagnostics session is actually open. There is no
/// continuous polling, no shell-outs to PowerShell or `ps`: a diagnostic
/// feature must not become its own resource problem (dev6).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show ProcessInfo;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Process-lifecycle counters, maintained at the spawn and dispose sites.
///
/// Kept as plain statics on purpose: they are incremented from the engine
/// implementation in a few known places and read from the diagnostics UI and
/// the export. A change-detection stream would be architecture for its own
/// sake here.
class DiagCounters {
  /// UCI child processes started since launch.
  static int enginesStarted = 0;

  /// UCI child processes believed to be alive right now.
  static int enginesAlive = 0;

  /// Engine processes that died without being disposed deliberately.
  static int enginesDiedUnexpectedly = 0;

  /// Engine initialization attempts in flight.
  static int initializationsActive = 0;

  /// Benchmark runs started since launch.
  static int benchmarksStarted = 0;

  /// Benchmark runs still active (runs survive the screen that started them).
  static int benchmarksActive = 0;

  /// UCI handshake probes in flight (add-engine, configure, preflight).
  static int probesActive = 0;

  static Map<String, Object> snapshot() => {
        'enginesStarted': enginesStarted,
        'enginesAlive': enginesAlive,
        'enginesDiedUnexpectedly': enginesDiedUnexpectedly,
        'initializationsActive': initializationsActive,
        'benchmarksStarted': benchmarksStarted,
        'benchmarksActive': benchmarksActive,
        'probesActive': probesActive,
      };

  static void reset() {
    enginesStarted = 0;
    enginesAlive = 0;
    enginesDiedUnexpectedly = 0;
    initializationsActive = 0;
    benchmarksStarted = 0;
    benchmarksActive = 0;
    probesActive = 0;
  }
}

/// One resource snapshot.
class ResourceSample {
  final DateTime timestamp;
  final int rssBytes;
  final int engineProcessCount;
  final int initializationCount;
  final int probeCount;
  final int benchmarkCount;

  const ResourceSample({
    required this.timestamp,
    required this.rssBytes,
    required this.engineProcessCount,
    required this.initializationCount,
    required this.probeCount,
    required this.benchmarkCount,
  });

  List<Object> toCsvRow() => [
        timestamp.toUtc().toIso8601String(),
        rssBytes,
        engineProcessCount,
        initializationCount,
        probeCount,
        benchmarkCount,
      ];
}

/// Samples resources while a diagnostics session wants them.
///
/// `start`/`stop` belong to the diagnostics screen: sampling runs only while
/// that screen is open and can be switched off there, and never runs just
/// because the app is idle.
class ResourceSampler {
  final Duration interval;

  /// Newest sample last, bounded to [maxSamples] (600 samples ≈ 20 minutes
  /// at the default interval).
  final List<ResourceSample> samples = <ResourceSample>[];
  final int maxSamples;

  Timer? _timer;
  bool _enabled = true;
  int? _peakRssBytes;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  ResourceSampler({
    this.interval = const Duration(seconds: 2),
    this.maxSamples = 600,
  });

  bool get isRunning => _timer != null;
  bool get enabled => _enabled;
  set enabled(bool value) {
    _enabled = value;
    if (!value) stop();
  }

  /// Emits every time a sample is taken. The diagnostics screen listens and
  /// rebuilds its resource header — without this, a quiet app (no log
  /// events) would leave the displayed memory and counters frozen at the
  /// opening snapshot despite sampling continuing.
  Stream<void> get changes => _changes.stream;

  /// Peak resident memory seen while sampling, for the report header.
  int? get peakRssBytes => _peakRssBytes;

  void start() {
    if (_timer != null || !_enabled || kIsWeb) return;
    sample();
    _timer = Timer.periodic(interval, (_) => sample());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Takes one sample now. Safe on platforms without RSS reporting: the
  /// sample is skipped rather than invented.
  void sample() {
    final rss = _currentRssBytes();
    if (rss == null) return;
    _peakRssBytes = math.max(_peakRssBytes ?? 0, rss);
    samples.add(ResourceSample(
      timestamp: DateTime.now(),
      rssBytes: rss,
      engineProcessCount: math.max(DiagCounters.enginesAlive, 0),
      initializationCount: DiagCounters.initializationsActive,
      probeCount: DiagCounters.probesActive,
      benchmarkCount: DiagCounters.benchmarksActive,
    ));
    while (samples.length > maxSamples) {
      samples.removeAt(0);
    }
    if (_changes.hasListener && !_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Resident memory of the current process, or null where unsupported.
  /// A plain read of a runtime-maintained counter — nanoseconds, no shell
  /// outs and nothing worth avoiding.
  int? _currentRssBytes() {
    if (kIsWeb) return null;
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      try {
        return ProcessInfo.maxRss;
      } catch (_) {
        return null;
      }
    }
  }

  /// The performance.csv section of an exported report.
  String toCsv() {
    final buffer = StringBuffer(
        'timestamp_utc,rss_bytes,engine_processes,initializations,probes,benchmarks\n');
    for (final sample in samples) {
      buffer.writeln(sample.toCsvRow().join(','));
    }
    return buffer.toString();
  }

  /// Compact JSON for the metadata document.
  Map<String, dynamic> summaryJson() => {
        'sampleIntervalSeconds': interval.inSeconds,
        'sampleCount': samples.length,
        if (_peakRssBytes != null) 'peakRssBytes': _peakRssBytes,
        if (samples.isNotEmpty) 'latestRssBytes': samples.last.rssBytes,
        'counters': DiagCounters.snapshot(),
      };

  static Map<String, dynamic> countersJson() => DiagCounters.snapshot();

  static String countersAsJsonText() =>
      const JsonEncoder.withIndent('  ').convert(DiagCounters.snapshot());
}
