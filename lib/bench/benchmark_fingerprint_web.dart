// Browser implementation of the binary fingerprint helpers.
//
// A browser cannot start a user-supplied executable, so there is no binary to
// fingerprint. The functions keep the native signatures and say "unavailable".
library;

/// What `stat` says about a file. Mirrors the native type; unused on web.
class ExecutableStat {
  final int sizeBytes;
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
}

/// A short description of this host for a report header.
///
/// A browser cannot report its CPU or memory, and saying so is better than
/// guessing: the report marks the hardware as unavailable.
String hostSummary() => 'web browser (hardware not reported)';

/// Always null: a browser has no filesystem.
Future<ExecutableStat?> statExecutable(String path) async => null;

/// Always null: a browser has no file to hash.
Future<String?> sha256OfFile(String path) async => null;
