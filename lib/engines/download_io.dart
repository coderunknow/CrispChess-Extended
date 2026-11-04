/// Native download transport: HTTPS streaming to a private part file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'engine_storage.dart';

/// Result of streaming [uri] into [target].
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

/// Streams an HTTPS URL to [partPath], following at most 5 HTTPS redirects and
/// refusing any redirect back to plain HTTP. [maxBytes] bounds the transfer so a
/// hostile or mistaken endpoint cannot fill the disk.
Future<StreamedFile> streamToFile({
  required Uri uri,
  required String partPath,
  required int maxBytes,
  int? expectedBytes,
  ProgressSink? onProgress,
  bool Function()? cancelled,
}) async {
  // The caller validates the scheme too, but this function is the thing that
  // opens a socket: refusing here means no future caller can hand it a plain
  // HTTP URL and have the guarantee depend on the caller's diligence.
  if (uri.scheme != 'https') {
    return const StreamedFile(
        ok: false, bytes: 0, message: 'Refusing a non-HTTPS URL.');
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    // HttpClientRequest.followRedirects defaults to true, and dart:io then
    // follows the chain itself: response.isRedirect is false for every hop and
    // this loop never runs, so a redirect to plain HTTP would be followed
    // silently. The redirects are followed by hand below BECAUSE the client is
    // told not to.
    Future<HttpClientResponse> send(Uri target) async {
      final request = await client.getUrl(target);
      request.followRedirects = false;
      return request.close();
    }

    var response = await send(uri);
    var current = uri;
    var redirects = 0;
    while (response.isRedirect) {
      final location = response.headers.value('location');
      if (location == null || redirects++ >= 5) {
        return const StreamedFile(ok: false, bytes: 0, message: 'Too many redirects.');
      }
      await response.drain<void>();
      final next = current.resolve(location);
      if (next.scheme != 'https') {
        return const StreamedFile(ok: false, bytes: 0, message: 'Redirect left HTTPS.');
      }
      current = next;
      response = await send(next);
    }
    if (response.statusCode != 200) {
      return StreamedFile(
          ok: false, bytes: 0, message: 'HTTP ${response.statusCode} from the official source.');
    }
    final total = response.contentLength > 0 ? response.contentLength : expectedBytes;
    if (total != null && total > maxBytes) {
      return StreamedFile(ok: false, bytes: 0,
          message: 'Artifact ($total bytes) exceeds the size limit.');
    }
    final file = File(partPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    var received = 0;
    try {
      await for (final chunk in response) {
        if (cancelled?.call() ?? false) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return const StreamedFile(ok: false, bytes: 0,
              message: 'Download cancelled.', cancelled: true);
        }
        received += chunk.length;
        if (received > maxBytes) {
          await sink.close();
          if (await file.exists()) await file.delete();
          return const StreamedFile(ok: false, bytes: 0,
              message: 'Download exceeded the size limit.');
        }
        sink.add(chunk);
        hasher.add(chunk);
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    hasher.close();
    if (total != null && received != total) {
      if (await file.exists()) await file.delete();
      return StreamedFile(ok: false, bytes: received,
          message: 'Truncated download ($received of $total bytes).');
    }
    return StreamedFile(ok: true, bytes: received,
        message: 'Downloaded.', sha256: digestSink.value.toString());
  } on EngineStorageError catch (error) {
    return StreamedFile(ok: false, bytes: 0, message: error.message);
  } on IOException catch (error) {
    return StreamedFile(ok: false, bytes: 0, message: 'Download failed: $error');
  } finally {
    client.close(force: true);
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Creates [path] (and its parents) before a download starts.
Future<void> ensureDirectory(String path) =>
    Directory(path).create(recursive: true).then((_) {});

Future<String?> hashFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    hasher.add(chunk);
  }
  hasher.close();
  return sink.value.toString();
}

Future<bool> fileExists(String path) => File(path).exists();

Future<int?> fileLength(String path) async {
  final file = File(path);
  return await file.exists() ? file.length() : null;
}

/// Moves a verified part file into place. A same-directory rename is atomic on
/// every supported desktop/mobile filesystem; the destination is only removed
/// once the replacement is known good.
Future<void> installFile(String partPath, String targetPath) async {
  final target = File(targetPath);
  if (await target.exists()) await target.delete();
  await File(partPath).rename(targetPath);
}

Future<void> writeSidecar(String targetPath, Map<String, dynamic> data) =>
    File('$targetPath.json').writeAsString(jsonEncode(data));

Future<Map<String, dynamic>?> readSidecar(String targetPath) async {
  try {
    final file = File('$targetPath.json');
    if (!await file.exists()) return null;
    return Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map);
  } catch (_) {
    return null;
  }
}

Future<void> deleteQuietly(String path) async {
  final file = File(path);
  if (await file.exists()) await file.delete();
}

String artifactPathFor(EngineStorageLocation location, String engineId,
        String version, String fileName) =>
    '${location.rootPath}/$engineId/$version/downloads/$fileName';
