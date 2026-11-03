/// Web model fetch: plain `fetch()`, relying on the browser's own HTTP
/// cache (HuggingFace's CDN serves these as long-lived immutable assets) —
/// no custom Cache Storage layer needed.
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<Uint8List> fetchModelBytes(String url, String cacheFileName) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// The browser's HTTP cache cannot be queried, so a model is never known to be
/// present: Engine Preflight asks before loading one.
Future<bool> isModelCached(String url, String cacheFileName) async => false;

/// No file system on the web; native libraries that load a model from disk
/// are not available there either.
Future<String> fetchModelFile(String url, String cacheFileName,
        {void Function(int received, int? total)? onProgress}) =>
    throw UnsupportedError('fetchModelFile is not available on the web');
