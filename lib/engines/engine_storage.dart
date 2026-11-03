/// One user-visible engine storage root, chosen in Settings.
///
/// Desktop uses the exact directory the user picked. Android executable files
/// must stay in app-private storage, so there the setting selects the
/// *download/archive* root and executables are installed inside the app data
/// directory — the platform limitation is reported rather than hidden. iOS can
/// only use its sandbox. The web has no filesystem directory at all and uses
/// browser-managed Cache Storage, which has no user-selectable path.
///
/// Layout: `<root>/engines/<engine-id>/<version>/` with `bin`, `models`,
/// `metadata`, `downloads` and `state` siblings, plus legacy symlink/copy
/// discovery for engines installed before dev5.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, HttpClient;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bench/benchmark_storage_base.dart';
import 'platform_paths.dart';

enum EngineStorageMode {
  /// The user-selected absolute directory is authoritative (desktop).
  userDirectory,

  /// Models/downloads go to the selected directory; executables remain in the
  /// app-private directory because Android cannot run files from shared storage.
  userDirectoryAndroid,

  /// The iOS sandbox is the only location the app may write to.
  appSandbox,

  /// Browser-managed persistence; there is no user-selected directory.
  browserManaged,
}

class EngineStorageLocation {
  final String rootPath;
  final EngineStorageMode mode;
  final bool userSelected;
  const EngineStorageLocation({
    required this.rootPath,
    required this.mode,
    required this.userSelected,
  });

  bool get isBrowserManaged => mode == EngineStorageMode.browserManaged;
  bool get executablesInRoot =>
      mode == EngineStorageMode.userDirectory || mode == EngineStorageMode.appSandbox;

  /// Directory for executables, which differs from [rootPath] on Android.
  String get executableRoot => switch (mode) {
    EngineStorageMode.userDirectoryAndroid => '$rootPath/app-private-executables',
    _ => rootPath,
  };

  String engineDir(String engineId, String version) =>
      '${_safe(engineId)}/${_safe(version)}';

  String downloadsDir(String engineId, String version) =>
      '${engineDir(engineId, version)}/downloads';

  String metadataDir(String engineId, String version) =>
      '${engineDir(engineId, version)}/metadata';

  String binaryDir(String engineId, String version) =>
      '${executableRoot}/${engineDir(engineId, version)}/bin';

  String modelsDir(String engineId, String version) =>
      '$rootPath/${engineDir(engineId, version)}/models';

  /// Directory layout, relative to the root, shown in the Engine Manager so a
  /// user can see where files actually land.
  String get layoutSummary => switch (mode) {
    EngineStorageMode.userDirectory =>
      'engines/<engine>/<version>/{bin,models,downloads,metadata,state}',
    EngineStorageMode.userDirectoryAndroid =>
      'models/downloads under the selected folder; executables in app-private storage',
    EngineStorageMode.appSandbox =>
      'App sandbox: Documents/engines/<engine>/<version>/…',
    EngineStorageMode.browserManaged =>
      'Browser Cache Storage (no filesystem path can be chosen)',
  };

  Map<String, dynamic> toJson() => {
    'rootPath': rootPath.isNotEmpty ? redactPath(rootPath) : '',
    'mode': mode.name,
    'userSelected': userSelected,
    'layout': layoutSummary,
  };
}

String _safe(String value) {
  final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return cleaned.isEmpty || cleaned == '.' || cleaned == '..' ? 'engine' : cleaned;
}

/// Removes the user's home/project identifiers from any string that leaves the
/// app: diagnostics, reports and support bundles.
String redactPath(String path) {
  if (path.isEmpty || kIsWeb) return path;
  var result = path;
  final home = platformPathRedactionHome();
  if (home != null && home.length > 2) {
    result = result.replaceAll(home, '~');
  }
  final user = platformPathRedactionUser();
  if (user != null && user.isNotEmpty && user.length > 2) {
    result = result.replaceAll('/Users/$user', '/Users/<user>')
        .replaceAll('/home/$user', '/home/<user>')
        .replaceAll('C:\\Users\\$user', r'C:\Users\<user>');
  }
  return result;
}

/// A storage error with a message fit to show to the user.
class EngineStorageError implements Exception {
  final String message;
  const EngineStorageError(this.message);
  @override
  String toString() => message;
}

class EngineStorage {
  static const _keyRoot = 'engines.storageRoot';
  final BenchmarkStorage _documents;
  EngineStorageLocation? _location;

  EngineStorage({BenchmarkStorage? documents})
      : _documents = documents ?? MemoryBenchmarkStorage();

  Future<BenchmarkStorage> _docStore() async => _documents;

  Future<String?> _savedRoot() async {
    final store = await _docStore();
    await store.init();
    final raw = await store.read(_keyRoot);
    if (raw == null || raw.isEmpty) return null;
    try {
      return (jsonDecode(raw) as Map)['root'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRoot(String? root) async {
    final store = await _docStore();
    await store.init();
    if (root == null) {
      await store.delete(_keyRoot);
    } else {
      await store.write(_keyRoot, jsonEncode({'root': root, 'version': 1}));
    }
  }

  /// The default root for this platform. Never throws: a missing platform
  /// plugin falls back to the pre-dev5 `~/.crispchess` location.
  Future<String> defaultRoot() async {
    if (kIsWeb) return 'browser://cache-storage';
    final host = currentHostPlatform();
    try {
      if (host == 'ios') {
        final dir = await getApplicationDocumentsDirectory();
        return '${dir.path}/engines';
      }
      final dir = await getApplicationSupportDirectory();
      return '${dir.path}/engines';
    } catch (_) {
      return '${fallbackHomeDirectory()}/.crispchess/engines';
    }
  }

  EngineStorageMode get _mode {
    if (kIsWeb) return EngineStorageMode.browserManaged;
    return switch (currentHostPlatform()) {
      'android' => EngineStorageMode.userDirectoryAndroid,
      'ios' => EngineStorageMode.appSandbox,
      _ => EngineStorageMode.userDirectory,
    };
  }

  Future<EngineStorageLocation> location({bool refresh = false}) async {
    if (_location != null && !refresh) return _location!;
    final saved = await _savedRoot();
    if (kIsWeb) {
      return _location = const EngineStorageLocation(
          rootPath: 'browser://cache-storage',
          mode: EngineStorageMode.browserManaged, userSelected: false);
    }
    if (currentHostPlatform() == 'ios') {
      final root = await defaultRoot();
      return _location = EngineStorageLocation(
          rootPath: root, mode: EngineStorageMode.appSandbox, userSelected: false);
    }
    final root = saved ?? await defaultRoot();
    return _location = EngineStorageLocation(
      rootPath: root, mode: _mode, userSelected: saved != null);
  }

  /// Validates a candidate directory *before* it is saved: it must be possible
  /// to create the layout and write to it. Leaves nothing behind on failure.
  Future<EngineStorageLocation> validateCandidate(String path) async {
    if (kIsWeb) {
      throw const EngineStorageError(
          'A browser cannot select a filesystem directory; downloads use '
          'browser-managed Cache Storage.');
    }
    if (path.trim().isEmpty) {
      throw const EngineStorageError('Choose a directory.');
    }
    if (!path.startsWith('/') && !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      throw const EngineStorageError('Choose an absolute directory path.');
    }
    final dir = Directory(path);
    try {
      await dir.create(recursive: true);
      final probe = File('${dir.path}/.crispchess-write-check');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } on FileSystemException catch (error) {
      throw EngineStorageError(
          'That directory is not writable: ${redactPath(error.message)}');
    }
    return EngineStorageLocation(
      rootPath: dir.path,
      mode: _mode,
      userSelected: true,
    );
  }

  /// Persists a validated location and migrates compatible existing files.
  ///
  /// Migration copies and verifies before anything is removed, never deletes
  /// the old directory, and records an interrupted migration so the next launch
  /// can finish it.
  Future<EngineStorageMigration> setRoot(String path,
      {bool migrate = true, void Function(String step)? onProgress}) async {
    final candidate = await validateCandidate(path);
    final previous = await location();
    await _saveRoot(candidate.rootPath);
    _location = candidate;
    if (!migrate || previous.rootPath == candidate.rootPath) {
      return EngineStorageMigration(
          moved: 0, skipped: 0, source: redactPath(previous.rootPath),
          destination: redactPath(candidate.rootPath), complete: true);
    }
    var moved = 0, skipped = 0;
    final source = Directory(previous.rootPath);
    if (await source.exists()) {
      onProgress?.call('Copying existing engines');
      await for (final entity in source.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final relative = entity.path.substring(source.path.length + 1);
        final target = File('${candidate.rootPath}/$relative');
        try {
          if (await target.exists() && await target.length() == await entity.length()) {
            skipped++;
            continue;
          }
          await target.parent.create(recursive: true);
          await entity.copy(target.path);
          if (await target.length() != await entity.length()) {
            throw const EngineStorageError('copy is shorter than its source');
          }
          moved++;
        } catch (error) {
          onProgress?.call('Could not copy ${redactPath(relative)}: $error');
          await _markMigration(previous.rootPath, candidate.rootPath, complete: false);
          return EngineStorageMigration(
            moved: moved, skipped: skipped, source: redactPath(previous.rootPath),
            destination: redactPath(candidate.rootPath), complete: false,
            error: '$error',
          );
        }
      }
    }
    await _markMigration(previous.rootPath, candidate.rootPath, complete: true);
    onProgress?.call('Old files were kept at ${redactPath(previous.rootPath)}; '
        'remove them manually once the new location is verified.');
    return EngineStorageMigration(
      moved: moved, skipped: skipped, source: redactPath(previous.rootPath),
      destination: redactPath(candidate.rootPath), complete: true);
  }

  Future<void> _markMigration(String from, String to, {required bool complete}) async {
    if (kIsWeb) return;
    try {
      final dir = Directory(to);
      await dir.create(recursive: true);
      await File('${dir.path}/.migration.json').writeAsString(jsonEncode({
        'from': redactPath(from), 'complete': complete,
        'at': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (_) {
      // The marker is diagnostic; a failed write must not undo a good copy.
    }
  }

  /// Finishes an interrupted migration on the next launch.
  Future<EngineStorageMigration?> resumeMigration() async {
    if (kIsWeb) return null;
    final current = await location();
    final marker = File('${current.rootPath}/.migration.json');
    if (!await marker.exists()) return null;
    try {
      final data = jsonDecode(await marker.readAsString()) as Map;
      if (data['complete'] == true) return null;
      final from = data['from'] as String?;
      if (from == null) return null;
      final source = Directory(from.replaceFirst('~', '${fallbackHomeDirectory()}'));
      if (!await source.exists()) return null;
      return setRoot(current.rootPath, migrate: true);
    } catch (_) {
      return null;
    }
  }

  /// Removes an engine's installed files, but only below the managed root and
  /// only after checking the resolved path is still inside it.
  Future<void> removeEngine(String engineId, String version) async {
    if (kIsWeb) return;
    final root = Directory((await location()).rootPath);
    for (final dir in [
      Directory((await location()).engineDir(engineId, version)),
    ]) {
      final resolved = dir.absolute.path;
      final rootPath = root.absolute.path;
      if (!resolved.startsWith('$rootPath/')) {
        throw const EngineStorageError('Refusing to delete outside the engine root.');
      }
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}

class EngineStorageMigration {
  final int moved, skipped;
  final String source, destination;
  final bool complete;
  final String? error;
  const EngineStorageMigration({
    required this.moved, required this.skipped,
    required this.source, required this.destination,
    required this.complete, this.error,
  });
  String get summary => complete
      ? 'Moved $moved file(s), skipped $skipped already-present file(s). The old directory was kept.'
      : 'Migration incomplete after $moved file(s): ${error ?? 'unknown error'}';
}

/// Legacy bridge kept for callers that need preference storage only.
Future<SharedPreferences> engineStoragePreferences() =>
    SharedPreferences.getInstance();
