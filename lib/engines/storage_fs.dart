/// The filesystem operations [EngineStorage] needs, behind a conditional
/// import.
///
/// The web build has no filesystem at all, so the alternative implementation
/// answers every probe honestly instead of pulling `dart:io` into a build that
/// cannot link it.
library;

export 'storage_fs_io.dart' if (dart.library.js_interop) 'storage_fs_web.dart';
