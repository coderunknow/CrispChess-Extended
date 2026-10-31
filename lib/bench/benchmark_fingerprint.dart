/// Binary fingerprints: SHA-256 of an engine executable, cached by size and
/// modification time.
///
/// Hashing a 40 MB binary on every application start is not acceptable, so the
/// caller caches the digest against the cheap `stat` fields; this file only
/// does the reading. On web there is no user-supplied executable and therefore
/// nothing to fingerprint.
library;

export 'benchmark_fingerprint_io.dart'
    if (dart.library.js_interop) 'benchmark_fingerprint_web.dart';
