/// Picks the diagnostic log sink for the platform.
///
/// Native platforms get a rotating file sink under the application support
/// directory; browsers log to memory only.
library;

export 'diag_log_sink_io.dart'
    if (dart.library.js_interop) 'diag_log_sink_stub.dart';
