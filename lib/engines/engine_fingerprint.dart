import 'generic_uci_engine_stub.dart' show EngineProfile;
import 'engine_fingerprint_stub.dart'
    if (dart.library.io) 'engine_fingerprint_native.dart' as platform;

/// Refresh a custom UCI executable's cached SHA-256 fingerprint. This does no
/// file I/O on unsupported platforms. The native implementation stats first
/// and hashes only when metadata changes or [force] is requested.
Future<bool> refreshEngineFingerprint(EngineProfile profile, {bool force = false}) =>
    platform.refreshEngineFingerprint(profile, force: force);
