/// Verified, resumable, deduplicated engine/model downloads.
///
/// Every artifact declares an official HTTPS source, licence, platform and
/// optional *published* SHA-256. A hash calculated locally after download is
/// labelled `local` and never presented as upstream authentication. Files land
/// in `<root>/engines/<id>/<version>/downloads`, are verified, then installed
/// atomically; an interrupted transfer is never visible to an engine loader.
library;

import 'dart:async';

import 'package:crypto/crypto.dart';

import 'download_io.dart'
    if (dart.library.js_interop) 'download_web.dart';
import 'engine_storage.dart';
import 'platform_paths.dart';

class ArtifactSource {
  final String url;
  final String version;
  final String platform;
  final String arch;
  final int? bytes;

  /// A checksum published by the upstream project (authenticated evidence).
  final String? publishedSha256;

  /// Filled after download; never treated as upstream authentication.
  final String? localSha256;
  final String license;
  final String licenseUrl;
  final String? fileName;

  const ArtifactSource({
    required this.url,
    required this.version,
    required this.platform,
    required this.arch,
    required this.license,
    required this.licenseUrl,
    this.bytes,
    this.publishedSha256,
    this.localSha256,
    this.fileName,
  });

  String get effectiveName {
    if (fileName != null) return fileName!;
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final path = segments.isEmpty ? '' : segments.last;
    return path.isEmpty ? 'download.bin' : path;
  }

  String get integrityLabel => publishedSha256 != null
      ? 'published SHA-256'
      : localSha256 != null
          ? 'local SHA-256 (not upstream-authenticated)'
          : 'size/content-length only (no checksum available)';

  ArtifactSource withLocalHash(String hash) => ArtifactSource(
    url: url, version: version, platform: platform, arch: arch,
    license: license, licenseUrl: licenseUrl, bytes: bytes,
    publishedSha256: publishedSha256, localSha256: hash, fileName: fileName,
  );

  Map<String, dynamic> toJson() => {
    'url': url, 'version': version, 'platform': platform, 'arch': arch,
    if (bytes != null) 'bytes': bytes,
    if (publishedSha256 != null) 'publishedSha256': publishedSha256,
    if (localSha256 != null) 'localSha256': localSha256,
    'license': license, 'licenseUrl': licenseUrl,
    'integrity': integrityLabel,
  };
}

/// One installable engine dependency.
class EngineArtifact {
  final String engineId;
  final String label;
  final String version;
  final List<ArtifactSource> sources;
  final String kind; // 'binary', 'wasm', 'model'
  final List<String> dependencies;
  final bool executable;
  final bool extraDownloadOnly;
  const EngineArtifact({
    required this.engineId, required this.label, required this.version,
    required this.sources, required this.kind,
    this.dependencies = const [], this.executable = false,
    this.extraDownloadOnly = false,
  });
  ArtifactSource? sourceFor(String platform, String arch) {
    for (final source in sources) {
      if (source.platform == platform && source.arch == arch) return source;
    }
    for (final source in sources) {
      if (source.platform == platform && source.arch == 'any') return source;
    }
    return null;
  }
  Map<String, dynamic> toJson() => {
    'engineId': engineId, 'label': label, 'version': version, 'kind': kind,
    'executable': executable, 'dependencies': dependencies,
    'sources': [for (final s in sources) s.toJson()],
  };
}

enum DownloadState { queued, running, verifying, installed, failed, cancelled }

class DownloadProgress {
  final String engineId;
  final DownloadState state;
  final int received;
  final int? total;
  final String message;
  final String? error;
  const DownloadProgress({
    required this.engineId, required this.state, this.received = 0,
    this.total, this.message = '', this.error,
  });
  double? get fraction => total == null || total == 0 ? null : received / total!;
  DownloadProgress copyWith({DownloadState? state, int? received, int? total,
      String? message, String? error}) => DownloadProgress(
    engineId: engineId, state: state ?? this.state,
    received: received ?? this.received, total: total ?? this.total,
    message: message ?? this.message, error: error ?? this.error,
  );
}

class DownloadResult {
  final bool ok;
  final String? path;
  final String? sha256;
  final String message;
  const DownloadResult(this.ok, {this.path, this.sha256, required this.message});
}

/// Serialises and coalesces concurrent requests for the same artifact.
class EngineDownloadManager {
  final EngineStorage storage;
  final int maxBytes;
  final Map<String, Future<DownloadResult>> _inflight = {};
  final Map<String, String> _verifiedHashes = {};
  final StreamController<DownloadProgress> _events =
      StreamController<DownloadProgress>.broadcast();
  EngineDownloadManager({required this.storage, this.maxBytes = 2 * 1024 * 1024 * 1024});

  Stream<DownloadProgress> get progress => _events.stream;

  Future<DownloadResult> download(EngineArtifact artifact,
      {String? platform, String? arch, bool Function()? cancelled}) async {
    final targetPlatform = platform ?? currentPlatformName();
    final targetArch = arch ?? currentArchName();
    final key = '${artifact.engineId}/${artifact.version}/$targetPlatform/$targetArch';
    final existing = _inflight[key];
    if (existing != null) return existing;
    final future = _download(artifact, targetPlatform, targetArch, cancelled);
    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<DownloadResult> _download(EngineArtifact artifact, String platform,
      String arch, bool Function()? cancelled) async {
    void emit(DownloadState state,
        {int received = 0, int? total, String message = '', String? error}) {
      if (_events.isClosed) return;
      _events.add(DownloadProgress(
        engineId: artifact.engineId, state: state, received: received,
        total: total, message: message, error: error,
      ));
    }
    final source = artifact.sourceFor(platform, arch);
    if (source == null) {
      emit(DownloadState.failed, error: 'no artifact for $platform/$arch',
          message: 'No officially distributed artifact for this platform.');
      return const DownloadResult(false,
          message: 'No official artifact for platform.');
    }
    final uri = Uri.tryParse(source.url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      emit(DownloadState.failed, error: 'insecure source', message: source.url);
      return const DownloadResult(false,
          message: 'Refusing a non-HTTPS or unparsable download source.');
    }
    final location = await storage.location();
    if (location.isBrowserManaged) {
      return const DownloadResult(false,
          message: 'Browser downloads are managed by Cache Storage; use the '
              'web fetch path.');
    }
    await ensureDirectory(artifactDir(location, artifact));
    final targetPath = artifactPathFor(
        location, artifact.engineId, artifact.version, source.effectiveName);
    // Unique per artifact/version/platform: two artifacts never share a part.
    final partialPath = '$targetPath.part';

    if (await fileExists(targetPath)) {
      // A corrupt or missing sidecar means re-download, not trust.
      final data = await readSidecar(targetPath);
      final hash = data?['sha256'] as String?;
      if (hash != null && await hashFile(targetPath) == hash) {
        final bytes = await fileLength(targetPath) ?? 0;
        emit(DownloadState.installed, received: bytes, total: bytes,
            message: 'Already verified.');
        return DownloadResult(true, path: targetPath, sha256: hash,
            message: 'Already downloaded and verified.');
      }
    }

    final streamed = await streamToFile(
      uri: uri,
      partPath: partialPath,
      maxBytes: maxBytes,
      expectedBytes: source.bytes,
      cancelled: cancelled,
      onProgress: (received, total) =>
          emit(DownloadState.running, received: received, total: total),
    );
    if (!streamed.ok) {
      await deleteQuietly(partialPath);
      emit(streamed.cancelled ? DownloadState.cancelled : DownloadState.failed,
          error: streamed.message);
      return DownloadResult(streamed.cancelled, message: streamed.message);
    }
    emit(DownloadState.verifying, received: streamed.bytes, total: streamed.bytes);
    final localHash = streamed.sha256!;
    if (source.publishedSha256 != null &&
        source.publishedSha256!.toLowerCase() != localHash) {
      await deleteQuietly(partialPath);
      emit(DownloadState.failed, error: 'checksum mismatch');
      return const DownloadResult(false,
          message: 'Published checksum did not match the downloaded bytes; '
              'the file was discarded.');
    }
    await installFile(partialPath, targetPath);
    await writeSidecar(targetPath, {
      'url': source.url,
      'sha256': localHash,
      'bytes': streamed.bytes,
      'publishedSha256': source.publishedSha256,
      'authenticated': source.publishedSha256 != null,
      'at': DateTime.now().toUtc().toIso8601String(),
      'license': source.license,
    });
    _verifiedHashes[targetPath] = localHash;
    emit(DownloadState.installed, received: streamed.bytes, total: streamed.bytes,
        message: source.publishedSha256 != null
            ? 'Verified against the published checksum.'
            : 'Downloaded; only a local hash is available for this artifact.');
    return DownloadResult(true, path: targetPath, sha256: localHash,
        message: source.publishedSha256 != null
            ? 'Verified against the published checksum.'
            : 'Installed with a local hash; upstream publishes no checksum.');
  }

  /// SHA-256 of an installed artifact, for the Engine Manager's integrity row.
  Future<String?> installedHash(EngineArtifact artifact, String path) async {
    final cached = _verifiedHashes[path];
    if (cached != null) return cached;
    return hashFile(path);
  }

  Future<void> dispose() => _events.close();
}

/// Directory the verified artifacts of [artifact] live in. Shared with the
/// Engine Manager's status rows so the two never disagree about the path.
String artifactDir(EngineStorageLocation location, EngineArtifact artifact) =>
    '${location.rootPath}/${artifact.engineId}/${artifact.version}/downloads';

String currentPlatformName() => currentHostPlatform();

String currentArchName() => currentHostArch();

/// A short, human-readable status for the Engine Manager.
class ArtifactStatus {
  final bool installed;
  final bool verified;
  final bool upstreamAuthenticated;
  final String? path;
  final String? sha256;
  final int? bytes;
  final String detail;
  const ArtifactStatus({
    required this.installed, required this.verified,
    required this.upstreamAuthenticated, required this.detail,
    this.path, this.sha256, this.bytes,
  });
  Map<String, dynamic> toJson() => {
    'installed': installed, 'verified': verified,
    'upstreamAuthenticated': upstreamAuthenticated,
    'path': path == null ? null : redactStoragePath(path!),
    if (sha256 != null) 'sha256': sha256,
    if (bytes != null) 'bytes': bytes,
    'detail': detail,
  };
}

/// Checks an installed artifact without network access.
Future<ArtifactStatus> inspectArtifact(
    EngineArtifact artifact, EngineDownloadManager manager,
    {String? platform, String? arch}) async {
  final location = await manager.storage.location();
  if (location.isBrowserManaged) {
    return const ArtifactStatus(
      installed: false, verified: false, upstreamAuthenticated: false,
      detail: 'Browser-managed storage; the browser owns persistence.',
    );
  }
  final source = artifact.sourceFor(platform ?? currentPlatformName(),
      arch ?? currentArchName());
  if (source == null) {
    return const ArtifactStatus(
      installed: false, verified: false, upstreamAuthenticated: false,
      detail: 'No artifact is published for this platform and architecture.',
    );
  }
  final path = '${artifactDir(location, artifact)}/${source.effectiveName}';
  if (!await fileExists(path)) {
    return ArtifactStatus(
      installed: false, verified: false,
      upstreamAuthenticated: source.publishedSha256 != null,
      detail: 'Not downloaded.', bytes: source.bytes,
    );
  }
  final data = await readSidecar(path);
  final recorded = data?['sha256'] as String?;
  final authenticated = data?['authenticated'] == true;
  final actual = await hashFile(path);
  final length = await fileLength(path);
  final sizeOk = source.bytes == null || length == source.bytes;
  return ArtifactStatus(
    installed: sizeOk,
    verified: sizeOk && recorded != null && recorded == actual,
    upstreamAuthenticated: authenticated && source.publishedSha256 != null,
    path: path, sha256: actual, bytes: length,
    detail: recorded == null
        ? 'Installed without a recorded hash; re-download to verify.'
        : recorded == actual && sizeOk
            ? 'Installed and hash-verified.'
            : 'Installed bytes no longer match the recorded hash.',
  );
}

/// Test seam: hashing bytes without files, used by unit tests.
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();
