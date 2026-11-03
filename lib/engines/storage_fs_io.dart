import 'dart:convert';
import 'dart:io';

/// Creates [path] recursively. Throws when the directory is not writable.
Future<void> storageCreateDirectory(String path) =>
    Directory(path).create(recursive: true).then((_) {});

/// Throws unless [path] can actually be written to; leaves nothing behind.
///
/// The probe file is removed in a `finally`: a read-only directory that lets the
/// create succeed and the delete fail must not accumulate marker files, and a
/// failed probe must not leave the layout half-initialised.
Future<void> storageWriteProbe(String path) async {
  final probe = File('${Directory(path).path}/.crispchess-write-check');
  try {
    await probe.writeAsString('ok', flush: true);
  } finally {
    try {
      if (await probe.exists()) await probe.delete();
    } catch (_) {
      // A marker that cannot be removed is not a reason to reject the root;
      // the write itself is what was being tested.
    }
  }
}

/// Copies every file below [from] into [to], keeping relative paths.
///
/// Returns how many files were copied and how many already matched. Nothing is
/// deleted: the caller keeps the old directory until the new one is verified.
Future<({int moved, int skipped, String? error})> storageCopyTree(
    String from, String to,
    {void Function(String step)? onProgress}) async {
  var moved = 0, skipped = 0;
  final source = Directory(from);
  if (!await source.exists()) {
    return (moved: 0, skipped: 0, error: null);
  }
  onProgress?.call('Copying existing engines');
  await for (final entity in source.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = entity.path.substring(source.path.length + 1);
    final target = File('$to/$relative');
    try {
      if (await target.exists() &&
          await target.length() == await entity.length()) {
        skipped++;
        continue;
      }
      await target.parent.create(recursive: true);
      await entity.copy(target.path);
      if (await target.length() != await entity.length()) {
        return (moved: moved, skipped: skipped,
            error: 'copy is shorter than its source: $relative');
      }
      moved++;
    } catch (error) {
      return (moved: moved, skipped: skipped, error: '$relative: $error');
    }
  }
  return (moved: moved, skipped: skipped, error: null);
}

/// Records an in-progress or finished migration inside the destination.
Future<void> storageWriteMigrationMarker(String to, Map<String, dynamic> data) async {
  final dir = Directory(to);
  await dir.create(recursive: true);
  await File('${dir.path}/.migration.json').writeAsString(jsonEncode(data));
}

/// Reads an interrupted migration marker, or null when there is none.
Future<Map<String, dynamic>?> storageReadMigrationMarker(String root) async {
  try {
    final marker = File('$root/.migration.json');
    if (!await marker.exists()) return null;
    return Map<String, dynamic>.from(
        jsonDecode(await marker.readAsString()) as Map);
  } catch (_) {
    return null;
  }
}

/// Deletes an engine's files, refusing to leave the storage root.
Future<void> storageRemoveEngine(String rootPath, String relativeDir) async {
  final root = Directory(rootPath).absolute.path;
  final dir = Directory('$rootPath/$relativeDir');
  final resolved = dir.absolute.path;
  if (!resolved.startsWith('$root/')) {
    throw ArgumentError('Refusing to delete outside the engine root.');
  }
  if (await dir.exists()) await dir.delete(recursive: true);
}

/// Whether a migration source directory still exists.
Future<bool> storageDirectoryExists(String path) => Directory(path).exists();
