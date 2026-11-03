/// Web download transport: browsers own persistence, so there is no part file,
/// no rename and no path to inspect. Downloads are reported as unsupported
/// rather than pretended.
import 'engine_storage.dart';

class StreamedFile {
  final bool ok;
  final String? sha256;
  final int bytes;
  final String message;
  final bool cancelled;
  const StreamedFile({
    required this.ok, required this.bytes, required this.message,
    this.sha256, this.cancelled = false,
  });
}

typedef ProgressSink = void Function(int received, int? total);

Future<StreamedFile> streamToFile({
  required Uri uri,
  required String partPath,
  required int maxBytes,
  int? expectedBytes,
  ProgressSink? onProgress,
  bool Function()? cancelled,
}) async =>
    const StreamedFile(
      ok: false, bytes: 0,
      message: 'A browser has no writable path; models are fetched into '
          'browser-managed storage by the engine loader.',
    );

Future<String?> hashFile(String path) async => null;

Future<bool> fileExists(String path) async => false;

Future<int?> fileLength(String path) async => null;

Future<void> installFile(String partPath, String targetPath) async =>
    throw UnsupportedError('No filesystem on the web');

Future<void> writeSidecar(String targetPath, Map<String, dynamic> data) async {}

Future<Map<String, dynamic>?> readSidecar(String targetPath) async => null;

Future<void> deleteQuietly(String path) async {}

String artifactPathFor(EngineStorageLocation location, String engineId,
        String version, String fileName) =>
    'browser://cache-storage/$engineId/$version/$fileName';
