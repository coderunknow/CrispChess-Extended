/// The web has no filesystem: every operation reports that honestly instead of
/// pretending a directory exists.

Future<void> storageCreateDirectory(String path) async =>
    throw UnsupportedError('A browser has no filesystem directory.');

Future<void> storageWriteProbe(String path) async =>
    throw UnsupportedError('A browser has no filesystem directory.');

Future<({int moved, int skipped, String? error})> storageCopyTree(
        String from, String to,
        {void Function(String step)? onProgress}) async =>
    (moved: 0, skipped: 0, error: 'A browser has no filesystem to migrate.');

Future<void> storageWriteMigrationMarker(
    String to, Map<String, dynamic> data) async {}

Future<Map<String, dynamic>?> storageReadMigrationMarker(String root) async =>
    null;

Future<void> storageRemoveEngine(String rootPath, String relativeDir) async {}

Future<bool> storageDirectoryExists(String path) async => false;
