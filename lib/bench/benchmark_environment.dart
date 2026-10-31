/// The conditions a benchmark was measured under.
///
/// Two runs are only comparable when these match — or when the difference is
/// visible enough for a reader to discount it. Nothing here identifies a user;
/// the host summary is a coarse OS/CPU-count line, and no device ids, serials
/// or paths are recorded.
library;

import 'benchmark_fingerprint.dart' show hostSummary;
import 'engine_identity.dart' show platformLabel;

/// Version of the app and of the benchmark document format.
const String kBenchmarkFormatVersion = '2.3.2-dev2';

/// Measurement conditions for one run.
class BenchmarkEnvironment {
  final String appVersion;
  final String benchmarkVersion;
  final String platform;

  /// Coarse host description ("linux (8 logical CPUs; …)").
  final String host;

  /// Extra note, e.g. that custom engines are unavailable on this platform.
  final String notes;

  const BenchmarkEnvironment({
    required this.appVersion,
    required this.benchmarkVersion,
    required this.platform,
    required this.host,
    this.notes = '',
  });

  static const BenchmarkEnvironment unknown = BenchmarkEnvironment(
    appVersion: 'unknown',
    benchmarkVersion: kBenchmarkFormatVersion,
    platform: 'unknown',
    host: 'unknown',
  );

  /// Captures the current environment.
  factory BenchmarkEnvironment.capture({String appVersion = 'unknown'}) =>
      BenchmarkEnvironment(
        appVersion: appVersion,
        benchmarkVersion: kBenchmarkFormatVersion,
        platform: platformLabel(),
        host: hostSummary(),
      );

  BenchmarkEnvironment withNote(String note) => BenchmarkEnvironment(
        appVersion: appVersion,
        benchmarkVersion: benchmarkVersion,
        platform: platform,
        host: host,
        notes: note,
      );

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'benchmarkVersion': benchmarkVersion,
        'platform': platform,
        'host': host,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory BenchmarkEnvironment.fromJson(Map<String, dynamic> json) =>
      BenchmarkEnvironment(
        appVersion: (json['appVersion'] as String?) ?? 'unknown',
        benchmarkVersion:
            (json['benchmarkVersion'] as String?) ?? kBenchmarkFormatVersion,
        platform: (json['platform'] as String?) ?? 'unknown',
        host: (json['host'] as String?) ?? 'unknown',
        notes: (json['notes'] as String?) ?? '',
      );
}
