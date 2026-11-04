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

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bench/benchmark_storage.dart';
import 'platform_paths.dart';
import 'storage_fs.dart';

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
      '$executableRoot/${engineDir(engineId, version)}/bin';

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
    'rootPath': rootPath.isNotEmpty ? redactStoragePath(rootPath) : '',
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
///
/// Deliberately not named `redactPath`: `engine_initialization.redactPath`
/// reduces a path to its last component, and two functions with the same name
/// and different meanings cannot be imported side by side.
String redactStoragePath(String path) {
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
      : _documents = documents ?? _defaultDocuments();

  /// The store that remembers the chosen root.
  ///
  /// This used to default to [MemoryBenchmarkStorage], which made every
  /// `EngineStorage()` its own island: `setRoot` wrote the choice into the
  /// screen's instance, `LynxEngine` built a fresh one that read nothing back
  /// and fell through to `defaultRoot()`, and the selection was lost on the
  /// next launch. A root the user picked but nothing looks in is worse than no
  /// setting at all — an engine downloaded there is invisible to every other
  /// caller. The persisted store costs one small JSON document.
  static BenchmarkStorage _defaultDocuments() =>
      createDefaultBenchmarkStorage();

  /// The instance the app-wide UI and the engines share, so a root chosen in
  /// Engine Manager is the root a download writes to and the root startup
  /// looks in. Tests pass an explicit store instead.
  static final EngineStorage shared = EngineStorage();

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
    try {
      await storageCreateDirectory(path);
      await storageWriteProbe(path);
    } catch (error) {
      throw EngineStorageError(
          'That directory is not writable: ${redactStoragePath('$error')}');
    }
    return EngineStorageLocation(
      rootPath: path,
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
          moved: 0, skipped: 0, source: redactStoragePath(previous.rootPath),
          destination: redactStoragePath(candidate.rootPath), complete: true);
    }
    final copied = await storageCopyTree(
        previous.rootPath, candidate.rootPath, onProgress: onProgress);
    final moved = copied.moved, skipped = copied.skipped;
    if (copied.error != null) {
      onProgress?.call(
          'Could not copy ${redactStoragePath(copied.error!)}');
      await _markMigration(previous.rootPath, candidate.rootPath, complete: false);
      return EngineStorageMigration(
        moved: moved, skipped: skipped, source: redactStoragePath(previous.rootPath),
        destination: redactStoragePath(candidate.rootPath), complete: false,
        error: copied.error,
      );
    }
    await _markMigration(previous.rootPath, candidate.rootPath, complete: true);
    onProgress?.call('Old files were kept at ${redactStoragePath(previous.rootPath)}; '
        'remove them manually once the new location is verified.');
    return EngineStorageMigration(
      moved: moved, skipped: skipped, source: redactStoragePath(previous.rootPath),
      destination: redactStoragePath(candidate.rootPath), complete: true);
  }

  Future<void> _markMigration(String from, String to, {required bool complete}) async {
    if (kIsWeb) return;
    try {
      await storageWriteMigrationMarker(to, {
        // The REAL path, not the redacted form. Restoration has to resolve it,
        // and redaction (`HOME ?? USERPROFILE`) and restoration
        // (`HOME ?? APPDATA`) do not even agree on which variable is the home
        // directory, so a `~` in the marker could never be expanded back on
        // Windows. The marker lives in the app's own storage directory, next to
        // the engine files it describes, not in a report.
        'from': from, 'complete': complete,
        'at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {
      // The marker is diagnostic; a failed write must not undo a good copy.
    }
  }

  /// Finishes an interrupted migration on the next launch.
  Future<EngineStorageMigration?> resumeMigration() async {
    if (kIsWeb) return null;
    final current = await location();
    final data = await storageReadMigrationMarker(current.rootPath);
    if (data == null || data['complete'] == true) return null;
    final from = data['from'] as String?;
    if (from == null) return null;
    // Markers written before this version stored a redacted path; expand it the
    // way those versions meant to. New markers store the real path.
    final source =
        from.startsWith('~') ? from.replaceFirst('~', fallbackHomeDirectory()) : from;
    // Nothing to finish if the old tree is gone, or if it is the root that is
    // already active (that is what "no migration needed" looks like).
    if (source == current.rootPath) return null;
    if (!await storageDirectoryExists(source)) return null;
    // Copy from the recorded source into the ACTIVE root. Passing the active
    // root as the destination of `setRoot` made `previous == candidate`, which
    // returned `complete: true` without copying anything and never cleared the
    // marker — so an interrupted move stayed interrupted forever while the UI
    // reported it as finished.
    final copied =
        await storageCopyTree(source, current.rootPath, onProgress: null);
    final finished = copied.error == null;
    await _markMigration(source, current.rootPath, complete: finished);
    return EngineStorageMigration(
      moved: copied.moved,
      skipped: copied.skipped,
      source: redactStoragePath(source),
      destination: redactStoragePath(current.rootPath),
      complete: finished,
      error: copied.error,
    );
  }

  /// Removes an engine's installed files, but only below the managed root and
  /// only after checking the resolved path is still inside it.
  Future<void> removeEngine(String engineId, String version) async {
    if (kIsWeb) return;
    final current = await location();
    try {
      // Sanitised through engineDir: a traversal-shaped id can never name a
      // path outside the managed root, so this can only be a no-op for it.
      await storageRemoveEngine(current.rootPath, current.engineDir(engineId, version));
    } on ArgumentError {
      throw const EngineStorageError(
          'Refusing to delete outside the engine root.');
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
