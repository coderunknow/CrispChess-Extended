/// The Hardware Protection resource-reading seam.
///
/// Selects the native implementation when `dart:io` is available and the web
/// stub otherwise, so callers never import `dart:io` and the web build still
/// links. Both implementations expose the same functions; the data types they
/// return live in `hardware_protection.dart`.
library;

export 'process_memory_web.dart'
    if (dart.library.io) 'process_memory_io.dart';
