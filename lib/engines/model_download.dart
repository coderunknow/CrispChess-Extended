/// Lets model engines tell Engine Preflight what they would download, before
/// anything is downloaded ([DownloadAwareEngine]).
library;

import 'engine_initialization.dart';
import 'maia3_dart/onnx/model_fetch.dart';

/// The download that loading [files] (url, cache file name) would start, or
/// null when every file is already in the model cache.
///
/// Only the cache is inspected; nothing is fetched. On the web the browser's
/// HTTP cache cannot be queried, so a requirement is always reported there.
/// [bytes] is passed through only when it is an exact, known size.
Future<EngineDownloadRequirement?> pendingModelDownload({
  required String description,
  required List<(String, String)> files,
  int? bytes,
  String? license,
}) async {
  for (final (url, cacheFileName) in files) {
    if (!await isModelCached(url, cacheFileName)) {
      return EngineDownloadRequirement(
        description: description,
        source: Uri.parse(url),
        bytes: bytes,
        license: license,
      );
    }
  }
  return null;
}
