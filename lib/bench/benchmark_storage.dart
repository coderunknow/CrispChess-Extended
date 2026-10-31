/// Picks the storage backend for the running platform.
///
/// Files on every platform that has a filesystem, `shared_preferences` in a
/// browser. Both implement [BenchmarkStorage]; nothing above this layer knows
/// which one it is talking to.
library;

export 'benchmark_storage_base.dart';
export 'benchmark_storage_io.dart'
    if (dart.library.js_interop) 'benchmark_storage_web.dart';
