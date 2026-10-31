// Native implementation of the binary fingerprint helpers.
//
// Not imported directly: `benchmark_fingerprint.dart` picks this file on
// platforms with `dart:io` and `benchmark_fingerprint_web.dart` in a browser.
library;

import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

/// What `stat` says about a file, which is enough to invalidate a cached
/// digest without reading the file again.
class ExecutableStat {
  final int sizeBytes;

  /// Milliseconds since the epoch, so the value survives a JSON round trip and
  /// compares equal across reads (a `DateTime` with microseconds does not).
  final int modifiedMillis;

  const ExecutableStat({
    required this.sizeBytes,
    required this.modifiedMillis,
  });

  Map<String, dynamic> toJson() => {
        'size': sizeBytes,
        'modified': modifiedMillis,
      };

  factory ExecutableStat.fromJson(Map<String, dynamic> json) {
    final size = json['size'];
    final modified = json['modified'];
    return ExecutableStat(
      sizeBytes: size is num ? size.toInt() : 0,
      modifiedMillis: modified is num ? modified.toInt() : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ExecutableStat &&
      other.sizeBytes == sizeBytes &&
      other.modifiedMillis == modifiedMillis;

  @override
  int get hashCode => Object.hash(sizeBytes, modifiedMillis);

  @override
  String toString() => 'ExecutableStat($sizeBytes bytes, $modifiedMillis)';
}

/// `stat` for [path], or null when it cannot be read.
Future<ExecutableStat?> statExecutable(String path) async {
  try {
    final stat = await File(path).stat();
    if (stat.type == FileSystemEntityType.notFound) return null;
    return ExecutableStat(
      sizeBytes: stat.size,
      modifiedMillis: stat.modified.millisecondsSinceEpoch,
    );
  } catch (_) {
    return null;
  }
}

/// A short description of this machine for a report header.
///
/// Deliberately coarse: a rating measured on a specific CPU does not transfer
/// to another one, and the report has to say at least which class of machine it
/// came from. No hardware identifier is collected or stored.
String hostSummary() {
  final cpus = Platform.numberOfProcessors;
  final os = Platform.operatingSystem;
  final version = Platform.operatingSystemVersion;
  return '$os (${cpus.toString()} logical CPU${cpus == 1 ? '' : 's'}; '
      '$version)';
}

/// SHA-256 of the file at [path], or null when it cannot be read.
Future<String?> sha256OfFile(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    // Streamed, so a large neural-network engine binary does not have to be
    // held in memory to be identified.
    final digest = await crypto.sha256.bind(file.openRead()).first;
    return digest.toString();
  } catch (_) {
    return null;
  }
}
