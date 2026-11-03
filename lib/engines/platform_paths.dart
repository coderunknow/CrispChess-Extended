/// The few host facts the download/storage code needs, without importing
/// `dart:io` into a web build.
///
/// Every function is a total answer: on the web there is no filesystem, so the
/// "path" is the browser-managed cache namespace and nothing pretends a
/// selectable directory exists.
library;

export 'platform_paths_io.dart'
    if (dart.library.js_interop) 'platform_paths_web.dart';
