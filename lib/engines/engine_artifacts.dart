/// Published artifacts for downloadable engines.
///
/// Only values that were actually established from the upstream project are
/// recorded here. Lynx publishes SHA-256 digests with its GitHub release assets
/// and those are written down. Stockfish's GitHub release assets carry no
/// published digest (`digest: null` via the GitHub API), so they are labelled
/// as unauthenticated rather than given an invented checksum. HuggingFace model
/// URLs are mutable `resolve/main` paths; they are unpinned and carry no hash.
///
/// Licences are distributive facts, not guesses: Lynx is MIT, Stockfish is
/// GPL-3.0 (downloaded separately, never bundled into the MIT app), and the
/// ONNX weight repositories declare their own terms upstream.
library;

import 'download_manager.dart';

/// Lynx 1.11.0 — SHA-256 values published in the GitHub release.
const String kLynxVersion = '1.11.0';
const String _lynxBase =
    'https://github.com/lynx-chess/Lynx/releases/download/v$kLynxVersion';
const String kLynxLicense = 'MIT';
const String kLynxLicenseUrl =
    'https://github.com/lynx-chess/Lynx/blob/main/LICENSE';

const Map<String, String> kLynxPublishedSha256 = {
  'https://github.com/lynx-chess/Lynx/releases/download/v1.11.0/Lynx-1.11.0-linux-x64.zip':
      '123faf887673c2b7a018132c3909c785693c9a33e3793fc7a69c25a3e27e396c',
  'https://github.com/lynx-chess/Lynx/releases/download/v1.11.0/Lynx-1.11.0-win-x64.zip':
      '5f73e82a959800deb7fa862910ea3578e4473656ea32f99ee1a6f44d11230580',
  'https://github.com/lynx-chess/Lynx/releases/download/v1.11.0/Lynx-1.11.0-osx-arm64.zip':
      '60f431c71faf2cc1f36be86dbda5cd437e901212f3703754bdbc39c5b5e27aef',
};

EngineArtifact lynxArtifact(String platform, String arch) {
  final suffix = switch ((platform, arch)) {
    ('linux', _) => 'linux-x64',
    ('windows', _) => 'win-x64',
    ('macos', 'arm64') => 'osx-arm64',
    ('macos', _) => 'osx-x64',
    _ => null,
  };
  if (suffix == null) {
    return const EngineArtifact(
      engineId: 'lynx', label: 'Lynx', version: kLynxVersion,
      kind: 'binary', executable: true, sources: [],
    );
  }
  final url = '$_lynxBase/Lynx-$kLynxVersion-$suffix.zip';
  return EngineArtifact(
    engineId: 'lynx', label: 'Lynx', version: kLynxVersion,
    kind: 'binary', executable: true,
    sources: [
      ArtifactSource(
        url: url,
        version: kLynxVersion,
        platform: platform,
        arch: platform == 'macos' ? arch : 'x64',
        license: kLynxLicense,
        licenseUrl: kLynxLicenseUrl,
        publishedSha256: kLynxPublishedSha256[url],
      ),
    ],
  );
}

/// Stockfish desktop binaries from the official `official-stockfish` releases.
/// The release assets are published without checksums; the manifest says so.
EngineArtifact stockfishArtifact(String platform, String arch) {
  const version = 'sf_16';
  // `stockfishInstallHint()` in stockfish_engine.dart is the authority on
  // supported platforms; the catalog repeats its set rather than inventing
  // downloads for platforms that cannot run a native process.
  if (platform == 'android' || platform == 'ios') {
    return const EngineArtifact(
      engineId: 'stockfish', label: 'Stockfish', version: version,
      kind: 'binary', executable: true, sources: [],
    );
  }
  return EngineArtifact(
    engineId: 'stockfish', label: 'Stockfish', version: version,
    kind: 'binary', executable: true,
    sources: const [
      ArtifactSource(
        url: 'https://github.com/official-stockfish/Stockfish/releases/tag/sf_16',
        version: version, platform: 'any', arch: 'any',
        license: 'GPL-3.0-or-later',
        licenseUrl: 'https://github.com/official-stockfish/Stockfish/blob/master/Copying.txt',
        // The release page is the official source. Assets under sf_16 carry no
        // published digest (GitHub API: digest null) and there is no sf_16.1
        // release, so no checksum is claimed.
      ),
    ],
  );
}

/// Model weights. These loaders fetch their files themselves; the catalog entry
/// exists so the Engine Manager can show provenance, size and licence and so
/// Preflight can ask consent. No checksum is claimed.
EngineArtifact modelArtifact({
  required String engineId,
  required String label,
  required String version,
  required List<String> urls,
  required String license,
  required String licenseUrl,
  int? bytes,
}) => EngineArtifact(
  engineId: engineId, label: label, version: version, kind: 'model',
  extraDownloadOnly: true,
  sources: [
    for (final url in urls)
      ArtifactSource(
        url: url, version: version,
        platform: currentPlatformName(), arch: currentArchName(),
        bytes: bytes, license: license, licenseUrl: licenseUrl,
      ),
  ],
);

/// The full catalog the Engine Manager and Preflight share.
List<EngineArtifact> engineArtifactCatalog({String? platform, String? arch}) {
  final p = platform ?? currentPlatformName();
  final a = arch ?? currentArchName();
  return [
    lynxArtifact(p, a),
    stockfishArtifact(p, a),
    modelArtifact(
      engineId: 'maia3', label: 'Maia3 ONNX weights', version: 'resolve/main',
      urls: const [
        'https://huggingface.co/cstr/maia3-onnx-int32/resolve/main/maia3_1100.onnx',
      ],
      license: 'see upstream model card',
      licenseUrl: 'https://huggingface.co/cstr/maia3-onnx-int32',
    ),
    modelArtifact(
      engineId: 'chessmamba', label: 'ChessMamba ONNX weights', version: 'resolve/main',
      urls: const [
        'https://huggingface.co/cstr/chessmamba-onnx/resolve/main/chessmamba_step_batch.onnx',
      ],
      license: 'see upstream model card',
      licenseUrl: 'https://huggingface.co/cstr/chessmamba-onnx',
    ),
  ];
}
